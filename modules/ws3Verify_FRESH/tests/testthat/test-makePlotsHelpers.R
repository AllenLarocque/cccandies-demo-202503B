library(testthat)
library(data.table)
library(ggplot2)

source("/home/allarocq/projects/WS3/cccandies-demo-202503B/modules/ws3Verify_FRESH/R/makePlotsHelpers.R")

# Shared test data
annDT <- data.table(
  year              = 1:10,
  harvestArea_ha    = seq(100, 1000, 100),
  burnArea_ha       = seq(50, 500, 50),
  burnedBiomass_gm2 = seq(1000, 10000, 1000),
  harvestVol_m3     = c(NA, NA, NA, NA, NA, 50000, NA, NA, NA, 100000),
  growingStock_m3   = c(NA, NA, NA, NA, NA, 5e5, NA, NA, NA, 4.5e5)
)

missedDT <- data.table(
  year                  = 1:10,
  plannedHarvestArea_ha = seq(500, 1400, 100),
  actualHarvestArea_ha  = seq(100, 1000, 100),
  missedDueToFire_ha    = seq(400, 400, 0)
)

test_that("plotHarvestArea returns a ggplot", {
  p <- plotHarvestArea(annDT)
  expect_s3_class(p, "ggplot")
})

test_that("plotBurnArea returns a ggplot", {
  p <- plotBurnArea(annDT)
  expect_s3_class(p, "ggplot")
})

test_that("plotHarvestVol returns a ggplot and drops NA rows", {
  p <- plotHarvestVol(annDT)
  expect_s3_class(p, "ggplot")
  # Data used should have only 2 non-NA rows
  expect_equal(nrow(p$data), 2)
})

test_that("plotGrowingStock returns a ggplot and drops NA rows", {
  p <- plotGrowingStock(annDT)
  expect_s3_class(p, "ggplot")
  expect_equal(nrow(p$data), 2)
})

test_that("plotBurnedBiomass returns a ggplot", {
  p <- plotBurnedBiomass(annDT)
  expect_s3_class(p, "ggplot")
})

test_that("plotMissedHarvest returns a ggplot with two fill levels", {
  p <- plotMissedHarvest(missedDT)
  expect_s3_class(p, "ggplot")
  expect_equal(nlevels(p$data$outcome), 2)
})

library(terra)

# Minimal SpatRaster for map tests
makeRast <- function(vals = 1:4) terra::rast(nrows = 2, ncols = 2, vals = vals)

test_that("mapAge executes without error and accepts a title", {
  r <- makeRast()
  expect_no_error(mapAge(r, "Test age map"))
})

test_that("mapCumulativeBurn executes without error", {
  r <- makeRast(c(0, 1, 2, 0))
  expect_no_error(mapCumulativeBurn(r))
})

test_that("mapCumulativeHarvest executes without error", {
  r <- makeRast(c(0, 0, 1, 2))
  expect_no_error(mapCumulativeHarvest(r))
})

test_that("mapStudyArea executes without error given a SpatRaster", {
  landscape <- c(makeRast(c(41, 41, 40, 40)))
  names(landscape) <- "fmuid"
  expect_no_error(mapStudyArea(landscape))
})

test_that("saveMap writes a png file when type is png", {
  tmp <- tempfile(fileext = "")
  r   <- makeRast()
  saveMap(fn = function() terra::plot(r), path = tmp, types = "png")
  expect_true(file.exists(paste0(tmp, ".png")))
  unlink(paste0(tmp, ".png"))
})
