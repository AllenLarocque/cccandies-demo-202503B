library(testthat)
library(data.table)

source(test_path("..", "..", "R", "collectStatsHelpers.R"))
source(test_path("..", "..", "R", "tablesCore.R"))
source(test_path("..", "..", "R", "tablesHarvest.R"))

.pf <- function(age, landBase = rep("THLB", length(age)), tsa = rep("tsa41", length(age)), au = 11) {
  data.table(cell = seq_along(age), tsa = tsa, landBase = landBase, au = au, age = age, vol_m3ha = 0)
}

test_that("harvestedCells are the cells whose age went down since last year", {
  pf <- .pf(age = c(1, 121, 1, 41))
  expect_identical(harvestedCells(pf, prevAge = c(130, 120, 0, 40)), 1L)  # cell 3: burned last year, now ageing
  expect_identical(harvestedCells(pf, prevAge = NULL), integer(0))
})

test_that("harvestedCells needs a reset to a young age: a stand stuck at 150 or without a previous age is not cut", {
  pf <- .pf(age = c(150, 1, 1))
  expect_identical(harvestedCells(pf, prevAge = c(150, NA, 90)), 3L)
})

test_that("tabulateHarvest compares ws3's applied harvest with the landscape's resets", {
  pf <- .pf(age = c(1, 1, 1, 51, 61))
  timing <- data.table(year = 2021L, basename = "tsa41", plannedPixels = 4L, appliedPixels = 3L,
                       skippedResetPixels = 1L)
  out <- tabulateHarvest(pf, cut = 1:3, planAge = c(110, 120, 130, 50, 55), prevAge = c(115, 125, 135, 50, 60),
                         plannedCells = 1:4, timing = timing, yearCal = 2021L, resInHA = 2,
                         yields = .yieldFixture())
  expect_equal(out$applied_ws3_ha, out$harvested_landscape_ha)
  expect_equal(out$planned_ws3_ha, 8)
  expect_equal(out$skippedBurned_ws3_ha, 2)
  expect_equal(out$planned_raster_ha, 8)
  expect_equal(out$plannedNotCut_ha, 2)
  expect_equal(out$meanAgeAtCut, 125)
  expect_equal(out$vol_m3, 3 * 300 * 2)                      # curve 101 held at 300 past age 30
  expect_equal(out$skippedVolPlanAge_m3, 0)                  # cell 4 aged normally: not a confirmed skip
  expect_equal(out$missedUnexplainedVol_m3, 300 * 2)         # ... so an unexplained miss (plan age 50 -> 300 m3/ha)
  expect_equal(out$planRuleViolations_n, 0L)
})

test_that("tabulateHarvest without harvestTimingStats keeps the landscape side and NA for ws3", {
  pf <- .pf(age = c(1, 51))
  out <- tabulateHarvest(pf, cut = 1L, planAge = c(110, 50), prevAge = c(115, 50), plannedCells = 1L,
                         timing = NULL, yearCal = 2021L, resInHA = 1, yields = .yieldFixture())
  expect_true(is.na(out$applied_ws3_ha))
  expect_true(is.na(out$planned_ws3_ha))
  expect_equal(out$harvested_landscape_ha, 1)
})

test_that("the harvest rule is checked at plan-year age: 400 then cut at 409 passes, 99 fails", {
  pf <- .pf(age = c(1, 1, 1), landBase = c("THLB", "THLB", "Non-THLB"))
  out <- tabulateHarvest(pf, cut = 1:3, planAge = c(400, 99, 150), prevAge = c(409, 105, 160),
                         plannedCells = 1:3, timing = NULL, yearCal = 2021L, resInHA = 1,
                         yields = .yieldFixture())
  expect_equal(out$planRuleViolations_n, 2L)                 # cell 2 too young at plan, cell 3 non-THLB
})

test_that("tabulateHarvest gives one zero row per TSA in a year with no harvest", {
  pf <- .pf(age = c(51, 61), tsa = c("tsa41", "tsa40"))
  out <- tabulateHarvest(pf, cut = integer(0), planAge = c(50, 60), prevAge = c(50, 60), plannedCells = integer(0),
                         timing = NULL, yearCal = 2021L, resInHA = 1, yields = .yieldFixture())
  expect_equal(sort(out$tsa), c("tsa40", "tsa41"))
  expect_equal(out$harvested_landscape_ha, c(0, 0))
  expect_equal(out$planRuleViolations_n, c(0L, 0L))
  expect_true(all(is.na(out$meanAgeAtCut)))
})

test_that("tabulateHarvestAge bins cut area by plan-year and cut-time age", {
  pf <- .pf(age = c(1, 1), landBase = c("THLB", "Non-THLB"))
  out <- tabulateHarvestAge(pf, cut = 1:2, planAge = c(400, 150), prevAge = c(409, 158), resInHA = 2)
  expect_equal(out[ageRef == "plan" & landBase == "THLB", ageBin], 400L)
  expect_equal(out[ageRef == "cut" & landBase == "Non-THLB", ageBin], 150L)
  expect_equal(sum(out$area_ha), 2 * 2 * 2)
})

test_that("planRow asks ws3 for each TSA's period-1 harvest volume and area", {
  calls <- list()
  product <- function(fm, bn, expr) {
    calls$bn <<- c(calls$bn, bn)
    (if (expr == "totvol") 1000 else 10) * (if (bn == "tsa41") 1 else 2)
  }
  out <- planRow(fm = "fm", basenames = list("tsa41", "tsa40"), product = product)
  expect_equal(out$tsa, c("tsa41", "tsa40"))
  expect_equal(out$plannedVol_m3, c(1000, 2000))
  expect_equal(out$plannedArea_ha, c(10, 20))
  expect_equal(unique(calls$bn), c("tsa41", "tsa40"))
})

test_that("planProduct's Python helper keeps development-type keys in Python", {
  # Regression: keys from fm.unmask() came back to R as lists and went back to Python as lists,
  # which compile_product() never matches (its keys are tuples), so planned volume was always 0.
  src <- paste(deparse(planProduct), collapse = "\n")
  expect_match(src, "py_run_string")
  expect_match(src, "dtype_keys=fm.unmask")
})

test_that("closePlanPeriod sums the period's harvest into the plan row: cut + skipped = planned", {
  planDT <- data.table(scenario = "s", rep = 1L, tsa = "tsa41", year = 10L, plannedVol_m3 = 900,
                       plannedArea_ha = 30)
  hv <- data.table(scenario = "s", rep = 1L, tsa = "tsa41", year = 10:20,
                   harvested_landscape_ha = 3, cutVolPlanAge_m3 = 80, skippedVolPlanAge_m3 = 10, vol_m3 = 85,
                   missedUnexplainedVol_m3 = 0)
  out <- closePlanPeriod(planDT, hv, planYear = 10L, periodLength = 10L)
  expect_equal(out$cutArea_ha, 30)
  expect_equal(out$cutVolPlanAge_m3 + out$skippedVolPlanAge_m3, out$plannedVol_m3)
  expect_equal(out$cutVolCutAge_m3, 850)
})

test_that("closePlanPeriod fills each TSA's own row and leaves other plan years alone", {
  planDT <- data.table(scenario = "s", rep = 1L, tsa = c("tsa41", "tsa40", "tsa41", "tsa40"),
                       year = c(0L, 0L, 10L, 10L), plannedVol_m3 = 1, plannedArea_ha = 1)
  hv <- data.table(scenario = "s", rep = 1L, tsa = rep(c("tsa40", "tsa41"), each = 10), year = rep(10:19, 2),
                   harvested_landscape_ha = rep(c(1, 5), each = 10), cutVolPlanAge_m3 = 0,
                   skippedVolPlanAge_m3 = 0, vol_m3 = 0, missedUnexplainedVol_m3 = 0)
  out <- closePlanPeriod(planDT, hv, planYear = 10L, periodLength = 10L)
  expect_equal(out[year == 10 & tsa == "tsa41", cutArea_ha], 50)
  expect_equal(out[year == 10 & tsa == "tsa40", cutArea_ha], 10)
  expect_true(all(is.na(out[year == 0, cutArea_ha])))
})

test_that("plannedHarvestCells maps each TSA's projected-harvest raster onto the landscape grid", {
  d <- withr::local_tempdir()
  tmpl <- terra::rast(nrows = 2, ncols = 4, xmin = 0, xmax = 4, ymin = 0, ymax = 2, vals = 0)
  for (bn in c("tsa41", "tsa40")) dir.create(file.path(d, bn))
  r41 <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 2, ymin = 0, ymax = 2, vals = c(1, 0, NA, 1))
  r40 <- terra::rast(nrows = 2, ncols = 2, xmin = 2, xmax = 4, ymin = 0, ymax = 2, vals = c(0, 1, 0, 0))
  terra::writeRaster(r41, file.path(d, "tsa41", "projected_harvest_2021.tif"))
  terra::writeRaster(r40, file.path(d, "tsa40", "projected_harvest_2021.tif"))
  expect_equal(sort(plannedHarvestCells(d, list("tsa41", "tsa40"), 2021L, tmpl)), c(1L, 4L, 6L))
  expect_identical(plannedHarvestCells(d, list("tsa41"), 1999L, tmpl), integer(0))
})

test_that("only planned stands reset since the plan count as skipped; other misses are unexplained", {
  # plan made 3 years ago; cells 1-3 planned this year, none cut
  pf <- .pf(age = c(2, 113, 1))
  out <- tabulateHarvest(pf, cut = integer(0), planAge = c(100, 110, 50), prevAge = c(1, 112, 0),
                         plannedCells = 1:3, timing = NULL, yearCal = 2021L, resInHA = 1,
                         yields = .yieldFixture(), elapsed = 2L)
  expect_equal(out$skippedVolPlanAge_m3, 300 + 300)   # cells 1 and 3 burned since the plan
  expect_equal(out$missedUnexplained_ha, 1)           # cell 2 aged normally and was not cut
  expect_equal(out$missedUnexplainedVol_m3, 300)
})

test_that("period mode: planned cells already cut earlier in the period are neither skipped nor missed", {
  pf <- .pf(age = c(3, 3))
  out <- tabulateHarvest(pf, cut = integer(0), planAge = c(120, 130), prevAge = c(2, 2), plannedCells = 1:2,
                         timing = NULL, yearCal = 2023L, resInHA = 1, yields = .yieldFixture(), elapsed = 3L,
                         cutEarlier = 1:2)
  expect_equal(out$skippedVolPlanAge_m3, 0)
  expect_equal(out$missedUnexplained_ha, 0)
  expect_equal(out$plannedNotCut_ha, 0)
})

test_that("stands within ws3's allocation tolerance of the age limits are tolerated, not violations", {
  # ws3's spatial allocation matches pixels within one period of the planned age (spatial.py,
  # ForestRaster._transition_cells: age_tolerance = period_length)
  pf <- .pf(age = c(1, 1, 1, 1, 1))
  out <- tabulateHarvest(pf, cut = 1:5, planAge = c(95, 89, 405, 411, 150), prevAge = c(96, 90, 406, 412, 151),
                         plannedCells = 1:5, timing = NULL, yearCal = 2021L, resInHA = 1,
                         yields = .yieldFixture(), ageTolerance = 10)
  expect_equal(out$planRuleTolerated_n, 2L)     # 95 and 405
  expect_equal(out$planRuleViolations_n, 2L)    # 89 and 411
  strict <- tabulateHarvest(pf, cut = 1:5, planAge = c(95, 89, 405, 411, 150), prevAge = c(96, 90, 406, 412, 151),
                            plannedCells = 1:5, timing = NULL, yearCal = 2021L, resInHA = 1, yields = .yieldFixture())
  expect_equal(strict$planRuleViolations_n, 4L) # default tolerance 0: the strict rule
  expect_equal(strict$planRuleTolerated_n, 0L)
})
