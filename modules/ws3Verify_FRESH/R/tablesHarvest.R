# tablesHarvest.R
# harvestDT (V1, B3), harvestAgeDT (V4, B3) and planDT (V5). Pure functions.

#' Cells harvested this year, from the landscape alone: age went down since last year's end.
#'
#' At collectStats this year's burns are not yet reset (landrAge resets them at priority 9), and
#' last year's were already in the end-of-year snapshot, so every reset here is a harvest.
harvestedCells <- function(pf, prevAge, resetAgeMax = 2L) {
  if (is.null(prevAge)) return(integer(0))
  p <- prevAge[pf$cell]
  # a cut restarts the stand: an age that merely failed to grow is not a harvest (V3 flags it)
  pf$cell[!is.na(p) & pf$age - p < 1 & pf$age <= resetAgeMax]
}

#' Harvest this year by TSA: ws3's own account against the landscape's.
#'
#' @param cut          harvestedCells() of this year.
#' @param planAge      Age of every cell when ws3 made the current plan.
#' @param prevAge      Age of every cell at the end of last year (pre-cut age).
#' @param plannedCells Cells in this year's projected_harvest raster(s).
#' @param timing       sim$harvestTimingStats, or NULL (harvestTiming = "period").
#' @param yearCal      Calendar year (timing and raster file names use it).
#' @param yields       loadYieldCurves() result.
#' @param ageTolerance Years outside [minAge, maxAge] a cut stand may be at plan time and still count as
#'   following ws3's rule (planRuleTolerated_n): ws3's spatial allocation matches pixels within one period
#'   of the planned age (ws3/spatial.py, ForestRaster._transition_cells). 0 = the strict rule.
#' @return data.table(tsa, planned_ws3_ha, applied_ws3_ha, skippedBurned_ws3_ha, planned_raster_ha,
#'   harvested_landscape_ha, plannedNotCut_ha, vol_m3, cutVolPlanAge_m3, skippedVolPlanAge_m3,
#'   meanAgeAtCut, planRuleViolations_n, planRuleTolerated_n)
tabulateHarvest <- function(pf, cut, planAge, prevAge, plannedCells, timing, yearCal, resInHA, yields,
                            minAge = 100, maxAge = 400, elapsed = 0L, cutEarlier = integer(0),
                            ageTolerance = 0) {
  d <- pf[, .(cell, tsa, landBase, au)]
  d[, `:=`(cut = cell %in% cut, planned = cell %in% plannedCells & !cell %in% cutEarlier)]
  d[, `:=`(pAge = planAge[cell], cAge = if (is.null(prevAge)) NA_real_ else prevAge[cell])]
  # planned, not cut: "skipped" only with evidence the stand restarted since the plan (it burned);
  # otherwise the miss is unexplained. Cells cut earlier in the period (period mode) are neither.
  d[, notCut := planned & !cut]
  d[, resetSincePlan := !is.na(cAge) & !is.na(pAge) & cAge < pAge + elapsed]
  d[, `:=`(skipped = notCut & resetSincePlan, missed = notCut & !resetSincePlan)]
  d[(cut | notCut), volPlan := pixelVolume(au, pAge, yields)]
  d[(cut), volCut := pixelVolume(au, cAge, yields)]
  out <- d[, .(planned_raster_ha = sum(planned) * resInHA,
               harvested_landscape_ha = sum(cut) * resInHA,
               plannedNotCut_ha = sum(notCut) * resInHA,
               missedUnexplained_ha = sum(missed) * resInHA,
               vol_m3 = sum(volCut[cut]) * resInHA,
               cutVolPlanAge_m3 = sum(volPlan[cut]) * resInHA,
               skippedVolPlanAge_m3 = sum(volPlan[skipped]) * resInHA,
               missedUnexplainedVol_m3 = sum(volPlan[missed]) * resInHA,
               meanAgeAtCut = if (any(cut)) mean(cAge[cut]) else NA_real_,
               planRuleViolations_n = sum(cut & (landBase != "THLB" | is.na(pAge) |
                                                 pAge < minAge - ageTolerance | pAge > maxAge + ageTolerance)),
               planRuleTolerated_n = sum(cut & landBase == "THLB" & !is.na(pAge) &
                                           ((pAge < minAge & pAge >= minAge - ageTolerance) |
                                              (pAge > maxAge & pAge <= maxAge + ageTolerance)))),
           by = tsa]
  out[, `:=`(planned_ws3_ha = NA_real_, applied_ws3_ha = NA_real_, skippedBurned_ws3_ha = NA_real_)]
  if (!is.null(timing) && nrow(timing)) {
    tm <- data.table::as.data.table(timing)[year == yearCal]
    out[tm, `:=`(planned_ws3_ha = i.plannedPixels * resInHA, applied_ws3_ha = i.appliedPixels * resInHA,
                 skippedBurned_ws3_ha = i.skippedResetPixels * resInHA), on = c(tsa = "basename")]
  }
  data.table::setcolorder(out, c("tsa", "planned_ws3_ha", "applied_ws3_ha", "skippedBurned_ws3_ha"))
  out[]
}

#' Area cut this year by TSA x land base x 10-year bin of the age at plan time and at cut time.
#' @return data.table(tsa, landBase, ageRef ("plan"/"cut"), ageBin, area_ha); only non-empty rows.
tabulateHarvestAge <- function(pf, cut, planAge, prevAge, resInHA) {
  d <- pf[cell %in% cut, .(cell, tsa, landBase)]
  if (!nrow(d)) return(data.table::data.table(tsa = character(), landBase = character(), ageRef = character(),
                                              ageBin = integer(), area_ha = numeric()))
  rbind(d[, .(tsa, landBase, ageRef = "plan", ageBin = ageBin(planAge[cell]))],
        d[, .(tsa, landBase, ageRef = "cut", ageBin = ageBin(prevAge[cell]))])[
    , .(area_ha = .N * resInHA), by = .(tsa, landBase, ageRef, ageBin)]
}

#' One TSA's product of the plan's period-1 harvest: `expr` "totvol" (m3) or "1." (ha).
#'
#' Runs in Python: fm.unmask() returns development-type keys as tuples, which reticulate would
#' turn into R lists and send back as Python lists that compile_product() never matches.
planProduct <- function(fm, bn, expr) {
  if (!reticulate::py_has_attr(reticulate::import_main(), "_ws3verify_plan_product"))
    reticulate::py_run_string(paste(
      "def _ws3verify_plan_product(fm, bn, expr):",
      "    mask = ' '.join([bn] + ['?'] * (fm.nthemes() - 1))",
      "    return fm.compile_product(1, expr, acode='harvest', dtype_keys=fm.unmask(mask))",
      sep = "\n"))
  as.numeric(reticulate::import_main()$`_ws3verify_plan_product`(fm, bn, expr))
}

#' The plan just made: each TSA's period-1 harvest volume (totvol) and area, from the ws3 ForestModel.
planRow <- function(fm, basenames, product = planProduct) {
  data.table::rbindlist(lapply(unlist(basenames), function(bn) {
    data.table::data.table(tsa = bn, plannedVol_m3 = product(fm, bn, "totvol"),
                           plannedArea_ha = product(fm, bn, "1."))
  }))
}

#' Fill a plan row with what happened over its period: sums of harvestDT years
#' [planYear, planYear + periodLength) per run and TSA.
closePlanPeriod <- function(planDT, harvestDT, planYear, periodLength) {
  keys <- intersect(c("scenario", "rep", "tsa"), names(planDT))
  per <- harvestDT[year >= planYear & year < planYear + periodLength,
                   .(cutArea_ha = sum(harvested_landscape_ha), cutVolPlanAge_m3 = sum(cutVolPlanAge_m3),
                     skippedVolPlanAge_m3 = sum(skippedVolPlanAge_m3),
                     missedUnexplainedVol_m3 = sum(missedUnexplainedVol_m3), cutVolCutAge_m3 = sum(vol_m3)),
                   by = keys]
  cols <- setdiff(names(per), keys)
  per[, year := as.integer(planYear)]
  out <- data.table::copy(planDT)
  for (col in cols) if (!col %in% names(out)) data.table::set(out, j = col, value = NA_real_)
  out[per, (cols) := mget(paste0("i.", cols)), on = c(keys, "year")]
  out[]
}

#' Landscape cells in this year's projected_harvest_<year>.tif of each TSA (value 1).
#'
#' Each TSA's raster has its own extent; cells are mapped onto the landscape grid by coordinates.
#' Missing files contribute nothing.
plannedHarvestCells <- function(tifDir, basenames, yearCal, template) {
  cells <- lapply(unlist(basenames), function(bn) {
    f <- file.path(tifDir, bn, paste0("projected_harvest_", yearCal, ".tif"))
    if (!file.exists(f)) return(integer(0))
    r <- terra::rast(f)
    idx <- which(terra::values(r)[, 1] == 1)
    if (!length(idx)) return(integer(0))
    as.integer(terra::cellFromXY(template, terra::xyFromCell(r, idx)))
  })
  out <- unique(unlist(cells))
  if (is.null(out)) integer(0) else out[!is.na(out)]
}
