# tablesHarvest.R
# harvestDT (V1, B3), harvestAgeDT (V4, B3) and planDT (V5). Pure functions.

#' Cells harvested this year, from the landscape alone: age went down since last year's end.
#'
#' At collectStats this year's burns are not yet reset (landrAge resets them at priority 9), and
#' last year's were already in the end-of-year snapshot, so every reset here is a harvest.
harvestedCells <- function(pf, prevAge) {
  if (is.null(prevAge)) return(integer(0))
  pf$cell[pf$age - prevAge[pf$cell] < 1]
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
#' @return data.table(tsa, planned_ws3_ha, applied_ws3_ha, skippedBurned_ws3_ha, planned_raster_ha,
#'   harvested_landscape_ha, plannedNotCut_ha, vol_m3, cutVolPlanAge_m3, skippedVolPlanAge_m3,
#'   meanAgeAtCut, planRuleViolations_n)
tabulateHarvest <- function(pf, cut, planAge, prevAge, plannedCells, timing, yearCal, resInHA, yields,
                            minAge = 100, maxAge = 400) {
  d <- pf[, .(cell, tsa, landBase, au)]
  d[, `:=`(cut = cell %in% cut, planned = cell %in% plannedCells)]
  d[, skipped := planned & !cut]
  d[, `:=`(pAge = planAge[cell], cAge = if (is.null(prevAge)) NA_real_ else prevAge[cell])]
  d[(cut | skipped), volPlan := pixelVolume(au, pAge, yields)]
  d[(cut), volCut := pixelVolume(au, cAge, yields)]
  out <- d[, .(planned_raster_ha = sum(planned) * resInHA,
               harvested_landscape_ha = sum(cut) * resInHA,
               plannedNotCut_ha = sum(skipped) * resInHA,
               vol_m3 = sum(volCut[cut]) * resInHA,
               cutVolPlanAge_m3 = sum(volPlan[cut]) * resInHA,
               skippedVolPlanAge_m3 = sum(volPlan[skipped]) * resInHA,
               meanAgeAtCut = if (any(cut)) mean(cAge[cut]) else NA_real_,
               planRuleViolations_n = sum(cut & (landBase != "THLB" | is.na(pAge) | pAge < minAge | pAge > maxAge))),
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

#' The plan just made: each TSA's period-1 harvest volume (totvol) and area, from the ws3 ForestModel.
planRow <- function(fm, basenames) {
  data.table::rbindlist(lapply(unlist(basenames), function(bn) {
    keys <- fm$unmask(paste(bn, "? ? ?"))
    data.table::data.table(
      tsa = bn,
      plannedVol_m3 = as.numeric(fm$compile_product(1L, "totvol", acode = "harvest", dtype_keys = keys)),
      plannedArea_ha = as.numeric(fm$compile_product(1L, "1.", acode = "harvest", dtype_keys = keys)))
  }))
}

#' Fill a plan row with what happened over its period: sums of harvestDT years
#' [planYear, planYear + periodLength) per run and TSA.
closePlanPeriod <- function(planDT, harvestDT, planYear, periodLength) {
  keys <- intersect(c("scenario", "rep", "tsa"), names(planDT))
  per <- harvestDT[year >= planYear & year < planYear + periodLength,
                   .(cutArea_ha = sum(harvested_landscape_ha), cutVolPlanAge_m3 = sum(cutVolPlanAge_m3),
                     skippedVolPlanAge_m3 = sum(skippedVolPlanAge_m3), cutVolCutAge_m3 = sum(vol_m3)),
                   by = keys]
  cols <- setdiff(names(per), keys)
  per[, year := as.integer(planYear)]
  out <- data.table::copy(planDT)
  for (col in cols) if (!col %in% names(out)) data.table::set(out, j = col, value = NA_real_)
  out[per, (cols) := mget(paste0("i.", cols)), on = c(keys, "year")]
  out[]
}
