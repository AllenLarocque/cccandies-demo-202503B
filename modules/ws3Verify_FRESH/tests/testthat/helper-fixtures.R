# Shared fixtures for ws3Verify_FRESH tests (testthat sources helper-*.R before the tests).

.yieldFixture <- function() {
  # AU 11 -> curve 101: 0,10,20,30 -> 0,100,200,300 m3/ha; AU 12 -> curve 102: 0,10,20 -> 0,50,100
  list(auToCurve = c(`11` = 101, `12` = 102),
       points = list(`101` = data.table::data.table(x = c(0, 10, 20, 30), y = c(0, 100, 200, 300)),
                     `102` = data.table::data.table(x = c(0, 10, 20), y = c(0, 50, 100))))
}

# A landscape stack like spades_ws3_dataInit's: categorical fmuid and thlb, numeric au and age.
.landscapeFixture <- function(fmuid, thlb, au, age, nrows = 1) {
  ncols <- length(age) / nrows
  mk <- function(v) terra::rast(nrows = nrows, ncols = ncols, xmin = 0, xmax = ncols, ymin = 0, ymax = nrows, vals = v)
  f <- mk(match(fmuid, sort(unique(stats::na.omit(fmuid)))))
  levels(f) <- data.frame(value = seq_along(sort(unique(stats::na.omit(fmuid)))), fmuid = sort(unique(stats::na.omit(fmuid))))
  t <- mk(thlb + 1)
  levels(t) <- data.frame(value = 1:2, thlb = c(0, 1))
  s <- c(f, t, mk(au), mk(rep(1, length(age))), mk(age))
  names(s) <- c("fmuid", "thlb", "au", "blockid", "age")
  s
}

# Synthetic ws3VerifyTables for plot tests: nRuns replicates x TSAs x years (planning every 10).
.tablesFixture <- function(nRuns = 1, tsas = "tsa41", years = 0:20, scenarios = "s", thlbIn = tsas,
                           disturbance = TRUE) {
  set.seed(1)
  runs <- data.table::CJ(scenario = scenarios, rep = seq_len(nRuns), tsa = tsas, year = as.integer(years))
  lbs <- c("THLB", "Non-THLB")
  ageDT <- runs[, data.table::CJ(landBase = lbs, ageBin = seq(0L, 400L, 10L)), by = .(scenario, rep, tsa, year)]
  ageDT[, area_ha := ifelse(landBase == "THLB" & !tsa %in% thlbIn, 0, stats::runif(.N, 0, 100))]
  ageDT[, vol_m3 := area_ha * pmin(ageBin, 300)]
  checkDT <- runs[, .(landBase = lbs), by = .(scenario, rep, tsa, year)]
  checkDT[, `:=`(pixels = 100L, naAge_n = 0L, forest_ha = 625, burned_n = 5L, burnedReset_n = 5L,
                 reset_n = 3L, unexplainedAgeChange_n = 0L, naChange_n = 0L, meanAgeChange = 0.9,
                 expectedMeanAgeChange = 0.9)]
  harvestDT <- runs[, .(planned_ws3_ha = 60, applied_ws3_ha = 55, skippedBurned_ws3_ha = 5, planned_raster_ha = 60,
                        harvested_landscape_ha = 55, plannedNotCut_ha = 5, missedUnexplained_ha = 0, vol_m3 = 55 * 250,
                        missedUnexplainedVol_m3 = 0,
                        cutVolPlanAge_m3 = 55 * 240, skippedVolPlanAge_m3 = 5 * 240, meanAgeAtCut = 120,
                        planRuleViolations_n = 0L), by = .(scenario, rep, tsa, year)]
  harvestAgeDT <- runs[, data.table::CJ(landBase = "THLB", ageRef = c("plan", "cut"), ageBin = seq(100L, 200L, 10L)),
                       by = .(scenario, rep, tsa, year)][, area_ha := 5]
  planDT <- runs[year %% 10 == 0, .(plannedVol_m3 = 600 * 240, plannedArea_ha = 600, cutArea_ha = 550,
                                    cutVolPlanAge_m3 = 550 * 240, skippedVolPlanAge_m3 = 50 * 240,
                                    cutVolCutAge_m3 = 550 * 250, missedUnexplainedVol_m3 = 0,
                                    periodYears = 10L, periodLength = 10L), by = .(scenario, rep, tsa, year)]
  fireDT <- runs[, data.table::CJ(landBase = lbs, ageBin = seq(0L, 300L, 50L)), by = .(scenario, rep, tsa, year)]
  fireDT[, `:=`(burned_ha = stats::rexp(.N, 1 / 20), burnedVol_m3 = 0)][, burnedVol_m3 := burned_ha * 100]
  fireDT <- rbind(fireDT, runs[, .(tsa = NA_character_, landBase = "outside forest", ageBin = NA_integer_, burned_ha = 3,
                                   burnedVol_m3 = 0), by = .(scenario, rep, year)], use.names = TRUE)
  fireEventsDT <- runs[, .(PolyID = 1L, size_ha = stats::rlnorm(4, 2, 1.5)), by = .(scenario, rep, tsa, year)]
  scfm <- runs[year == 0, .(PolyID = 1:2, targetFRI = c(300, 600), achievedFRI = c(280, 650), targetIgnitions = 2,
                             achievedIgnitions = 1.8, targetEscapes = 0.3, achievedEscapes = 0.25,
                             histMeanSize = 40, modMeanSize = 45), by = .(scenario, rep)]
  scfm[, tsa := NA_character_]
  tb <- list(ageDT = ageDT, checkDT = checkDT, harvestDT = harvestDT, harvestAgeDT = harvestAgeDT, planDT = planDT,
             fireDT = fireDT, fireEventsDT = fireEventsDT, scfmSummaryDT = unique(scfm))
  if (!disturbance) {
    tb$fireDT <- tb$fireDT[0]; tb$fireEventsDT <- tb$fireEventsDT[0]; tb$harvestAgeDT <- tb$harvestAgeDT[0]
    tb$checkDT[, `:=`(burned_n = 0L, burnedReset_n = 0L, reset_n = 0L)]
    num <- setdiff(names(tb$harvestDT), c("scenario", "rep", "tsa", "year"))
    tb$harvestDT[, (num) := lapply(.SD, function(v) v * 0), .SDcols = num][, meanAgeAtCut := NA_real_]
  }
  tb
}

.builds <- function(p) { ggplot2::ggplot_build(p); TRUE }
