library(testthat)
library(data.table)

source(test_path("..", "..", "R", "plotsCore.R"))
source(test_path("..", "..", "R", "plotsVerification.R"))

vFuns <- c("plotV1Harvest", "plotV2FireReset", "plotV3AgeBalance", "plotV4HarvestRule", "plotV5PlanVsCut",
           "plotV6FireRegime", "plotV7Conservation")

test_that("every verification plot builds for one run, many runs x two TSAs, and per-TSA facets", {
  one <- .tablesFixture()
  many <- .tablesFixture(nRuns = 3, tsas = c("tsa41", "tsa40"))
  for (f in vFuns) {
    fn <- get(f)
    expect_true(.builds(fn(one)), label = paste(f, "one run"))
    expect_true(.builds(fn(many)), label = paste(f, "many runs"))
    expect_true(.builds(fn(many, facet = "tsa")), label = paste(f, "facet tsa"))
    expect_true(.builds(fn(many, tsa = "tsa40")), label = paste(f, "one TSA"))
  }
})

test_that("V1 says its evidence is landscape-only without harvestTimingStats", {
  tb <- .tablesFixture()
  tb$harvestDT[, c("planned_ws3_ha", "applied_ws3_ha", "skippedBurned_ws3_ha") := NA_real_]
  p <- plotV1Harvest(tb)
  expect_true(.builds(p))
  expect_match(p$labels$subtitle, "landscape evidence only")
})

test_that("V1 reports the largest gap between ws3's applied harvest and the landscape's", {
  tb <- .tablesFixture()
  tb$harvestDT[year == 3, applied_ws3_ha := applied_ws3_ha + 12.5]
  expect_match(plotV1Harvest(tb)$labels$subtitle, "12.5 ha")
})

test_that("V3 and V4 put the failure counts in the subtitle", {
  tb <- .tablesFixture(nRuns = 2)
  tb$checkDT[rep == 2 & year == 4 & landBase == "THLB", unexplainedAgeChange_n := 7L]
  expect_match(plotV3AgeBalance(tb)$labels$subtitle, "7")
  tb$harvestDT[year == 5, planRuleViolations_n := 2L]
  expect_match(plotV4HarvestRule(tb)$labels$subtitle, "runs: 4\\.")
})

test_that("V6 says when no scfm summary was gathered", {
  tb <- .tablesFixture(); tb$scfmSummaryDT <- NULL
  p <- plotV6FireRegime(tb)
  expect_true(.builds(p))
  expect_match(p$labels$title, "no scfm summary")
})

test_that("V6's subtitle describes points per run, not a band it does not draw", {
  s <- plotV6FireRegime(.tablesFixture(nRuns = 2))$labels$subtitle
  expect_false(grepl("band", s))
  expect_match(s, "one point per run")
})

test_that("V4 reports cuts within ws3's age tolerance next to the graph", {
  tb <- .tablesFixture(nRuns = 2)
  tb$harvestDT[, planRuleTolerated_n := 0L][year == 5, planRuleTolerated_n := 3L]
  s <- plotV4HarvestRule(tb, tolerance = 10)$labels$subtitle
  expect_match(s, "within ws3's allocation tolerance")
  expect_match(s, "6 pixels")                  # 2 runs x 3
  expect_match(s, "Violations, all years and runs: 0")
  expect_true(.builds(plotV4HarvestRule(tb, tolerance = 10)))
})
