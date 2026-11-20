library(testthat)
library(data.table)

source(test_path("..", "..", "R", "plotsCore.R"))
source(test_path("..", "..", "R", "plotsBiology.R"))

bFuns <- c("plotB1AgeStructure", "plotB2GrowingStock", "plotB3WoodSupply", "plotB4OldForest", "plotB5Fire",
           "plotB6FireSelectivity", "plotB7DisturbanceMix", "plotB8BurnedVolume")

.buildsAny <- function(p) { if (inherits(p, "patchwork")) print(p) else ggplot2::ggplot_build(p); TRUE }

test_that("every biological plot builds for one run, many runs x two TSAs, per-TSA facets and one TSA", {
  pdf(NULL); on.exit(dev.off())
  one <- .tablesFixture(years = 0:60)
  many <- .tablesFixture(nRuns = 3, tsas = c("tsa41", "tsa40"), years = 0:60)
  for (f in bFuns) {
    fn <- get(f)
    expect_true(.buildsAny(fn(one)), label = paste(f, "one run"))
    expect_true(.buildsAny(fn(many)), label = paste(f, "many runs"))
    expect_true(.buildsAny(fn(many, facet = "tsa")), label = paste(f, "facet tsa"))
    expect_true(.buildsAny(fn(many, tsa = "tsa40")), label = paste(f, "one TSA"))
  }
})

test_that("B1 shares sum to 1 per land base, and a TSA without THLB gives no NaN", {
  tb <- .tablesFixture(tsas = c("tsa41", "tsa40"), thlbIn = "tsa41")
  p <- plotB1AgeStructure(tb, tsa = "tsa40")
  d <- p$data
  expect_false(any(is.nan(d$share)))
  expect_equal(unique(round(d[landBase == "Non-THLB", sum(share), by = year]$V1, 10)), 1)
})

test_that("B1 orders age classes young to old in the legend", {
  p <- plotB1AgeStructure(.tablesFixture())
  expect_equal(rev(levels(p$data$ageClass)), c("0-49", "50-99", "100-199", "200-299", "300+"))
})

test_that("B4 counts area at or above each threshold", {
  tb <- .tablesFixture(years = 0:1)
  tb$ageDT[, area_ha := 1]
  s <- oldForestArea(tb$ageDT, thresholds = c(140, 250))
  expect_equal(s[threshold == 140 & landBase == "THLB" & year == 0, area_ha], length(seq(140, 400, 10)))
  expect_equal(s[threshold == 250 & landBase == "THLB" & year == 0, area_ha], length(seq(250, 400, 10)))
})

test_that("B6 selectivity is 1 when every class burns in proportion to its area", {
  tb <- .tablesFixture(years = 0:1)
  tb$ageDT[, area_ha := 10]
  tb$fireDT <- tb$ageDT[, .(scenario, rep, tsa, year, landBase, ageBin, burned_ha = area_ha / 100, burnedVol_m3 = 0)]
  s <- fireSelectivity(tb)
  expect_equal(unique(round(s$mean, 10)), 1)
})

test_that("fire cycle = forest area / mean annual burned area of that land base", {
  tb <- .tablesFixture(years = 0:9)
  tb$ageDT[, area_ha := ifelse(landBase == "THLB", 1000 / 41, 0)]
  tb$fireDT <- data.table(scenario = "s", rep = 1L, tsa = "tsa41", year = 0:9, landBase = "THLB", ageBin = 0L,
                          burned_ha = 10, burnedVol_m3 = 0)
  fc <- fireCycle(tb, window = 10)
  expect_equal(fc[landBase == "THLB" & year == 9, mean], 100)
})

test_that("mapB9 draws one run's four maps and the mean of several runs' counts", {
  pdf(NULL); on.exit(dev.off())
  m <- terra::rast(nrows = 3, ncols = 3, nlyrs = 4, vals = 1)
  names(m) <- c("burnCount", "harvestCount", "timeSinceDisturbance", "lastDisturbance")
  expect_silent(mapB9(m))
  expect_silent(mapB9(list(m, m * 3)))
})
