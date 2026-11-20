library(testthat)
library(data.table)

for (f in c("plotsCore.R", "plotsVerification.R", "plotsBiology.R", "figureSets.R", "makePlotsHelpers.R", "gather.R"))
  source(test_path("..", "..", "R", f))

.savePng <- function(p, file) ggplot2::ggsave(paste0(file, ".png"), p, width = 9, height = 6, dpi = 30)

test_that("a run with no harvest and no fire still draws every figure", {
  pdf(NULL); on.exit(dev.off())
  for (tb in list(.tablesFixture(disturbance = FALSE), .tablesFixture(nRuns = 2, tsas = c("tsa41", "tsa40"), disturbance = FALSE))) {
    d <- withr::local_tempdir()
    expect_no_warning(writeFigureSets(tb, NULL, d, save = .savePng, byTsa = TRUE))
    expect_length(list.files(file.path(d, "verification"), pattern = "^V[0-9]_[a-zA-Z]+\\.png$"), 7)
    expect_length(list.files(file.path(d, "biology"), pattern = "^B[0-9]_[a-zA-Z]+\\.png$"), 8)
  }
})

test_that("one failing figure is reported and the others are still written", {
  d <- withr::local_tempdir()
  specs <- figureSpecs()
  specs$verification$V1_harvest <- function(tables, ...) stop("boom")
  expect_warning(writeFigureSets(.tablesFixture(), NULL, d, save = .savePng, specs = specs), "V1_harvest.*boom")
  expect_true(file.exists(file.path(d, "verification", "V2_fireReset.png")))
})

test_that("B5's annual burned area counts fire-free replicates as zero", {
  tb <- .tablesFixture(nRuns = 2, years = 0:1)
  tb$fireDT <- tb$fireDT[rep == 1 & year == 0][, `:=`(burned_ha = 0)][1, burned_ha := 100]
  s <- annualBurn(tb)
  expect_equal(s[year == 0, c(mean, nRuns)], c(50, 2))
  expect_equal(s[year == 1, mean], 0)
})

test_that("B7 and B8 average each scenario over its own runs", {
  a <- .tablesFixture(nRuns = 1, years = 0:9, scenarios = "a")
  b <- .tablesFixture(nRuns = 3, years = 0:9, scenarios = "b")
  tb <- Map(function(x, y) rbind(x, y, fill = TRUE), a, b)
  tb$fireDT[, burned_ha := 1][, burnedVol_m3 := 10]
  s <- decadeTotals(tb)
  fire <- s[disturbance == "Fire" & landBase == "THLB"]
  expect_equal(fire[scenario == "a", mean], fire[scenario == "b", mean])
  expect_true(.builds(plotB7DisturbanceMix(tb)))
  expect_true(.builds(plotB8BurnedVolume(tb)))
})

test_that("plots do not change the tables they are given", {
  tb <- .tablesFixture()
  before <- lapply(tb, function(d) data.table::copy(names(d)))
  invisible(lapply(c(plotB1AgeStructure, plotB6FireSelectivity, plotB3WoodSupply, plotV3AgeBalance), function(f) f(tb)))
  expect_identical(lapply(tb, names), before)
})

test_that("V2's subtitle reports the worst single run, not a quantile", {
  tb <- .tablesFixture(nRuns = 20, years = 0:3)
  tb$checkDT[rep == 7 & year == 2, burnedReset_n := 0L]
  expect_match(plotV2FireReset(tb)$labels$subtitle, "Lowest run-year: 0%")
})

test_that("V5 counts a period complete only at the configured length", {
  tb <- .tablesFixture(years = 0:4)
  tb$planDT[, periodYears := 5L]
  p <- plotV5PlanVsCut(tb)
  expect_true(.builds(p))
  expect_match(p$labels$subtitle, "No complete planning period")
})

test_that("B9 maps runs on different grids without failing", {
  pdf(NULL); on.exit(dev.off())
  mk <- function(xmin) { m <- terra::rast(nrows = 3, ncols = 3, xmin = xmin, xmax = xmin + 3, ymin = 0, ymax = 3, nlyrs = 4, vals = 1)
    names(m) <- c("burnCount", "harvestCount", "timeSinceDisturbance", "lastDisturbance"); m }
  expect_no_error(mapB9(list(mk(0), mk(0), mk(10))))
})

test_that("gather keeps an empty table's columns", {
  d <- withr::local_tempdir()
  tb <- .tablesFixture(years = 0:2, disturbance = FALSE)
  tb$scfmSummaryDT <- NULL
  dir.create(file.path(d, "r1")); saveRDS(tb, file.path(d, "r1", "ws3VerifyTables_year2.rds"))
  g <- gatherWs3VerifyTables(d)
  expect_true("fireDT" %in% names(g))
  expect_equal(nrow(g$fireDT), 0)
  expect_true(all(c("burned_ha", "landBase") %in% names(g$fireDT)))
})
