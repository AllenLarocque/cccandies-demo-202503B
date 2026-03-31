library(testthat)
library(data.table)
library(terra)

source("/home/allarocq/projects/WS3/cccandies-demo-202503B/modules/ws3Verify_FRESH/R/collectStatsHelpers.R")

test_that("initAnnualDT returns empty data.table with correct columns", {
  dt <- initAnnualDT()
  expect_s3_class(dt, "data.table")
  expect_equal(nrow(dt), 0)
  expect_named(dt, c("year", "harvestArea_ha", "burnArea_ha",
                      "burnedBiomass_gm2", "harvestVol_m3", "growingStock_m3"))
})

test_that("initMissedHarvestDT returns empty data.table with correct columns", {
  dt <- initMissedHarvestDT()
  expect_s3_class(dt, "data.table")
  expect_equal(nrow(dt), 0)
  expect_named(dt, c("year", "plannedHarvestArea_ha", "actualHarvestArea_ha",
                      "missedDueToFire_ha"))
})

test_that("appendAnnualRow adds a row with correct values and NA defaults for volume", {
  dt <- initAnnualDT()
  dt <- appendAnnualRow(dt, year = 5, harvestArea_ha = 200, burnArea_ha = 100,
                         burnedBiomass_gm2 = 5000)
  expect_equal(nrow(dt), 1)
  expect_equal(dt$year, 5)
  expect_equal(dt$harvestArea_ha, 200)
  expect_equal(dt$burnArea_ha, 100)
  expect_equal(dt$burnedBiomass_gm2, 5000)
  expect_true(is.na(dt$harvestVol_m3))
  expect_true(is.na(dt$growingStock_m3))
})

test_that("appendAnnualRow stores volume and GS when provided", {
  dt <- initAnnualDT()
  dt <- appendAnnualRow(dt, year = 10, harvestArea_ha = 300, burnArea_ha = 50,
                         burnedBiomass_gm2 = 2000,
                         harvestVol_m3 = 15000, growingStock_m3 = 500000)
  expect_equal(dt$harvestVol_m3, 15000)
  expect_equal(dt$growingStock_m3, 500000)
})

test_that("appendMissedHarvestRow adds a row with correct values", {
  dt <- initMissedHarvestDT()
  dt <- appendMissedHarvestRow(dt, year = 3, plannedHarvestArea_ha = 500,
                                actualHarvestArea_ha = 420, missedDueToFire_ha = 80)
  expect_equal(nrow(dt), 1)
  expect_equal(dt$missedDueToFire_ha, 80)
})

test_that("computeBurnBiomass returns 0 when nothing burned", {
  rstCurrentBurn <- terra::rast(nrows = 3, ncols = 3, vals = 0)
  pixelGroupMap  <- terra::rast(nrows = 3, ncols = 3, vals = 1:9)
  cohortData <- data.table::data.table(pixelGroup = 1:9, B = rep(100, 9))

  result <- computeBurnBiomass(rstCurrentBurn, pixelGroupMap, cohortData)
  expect_equal(result, 0)
})

test_that("computeBurnBiomass sums B for all burned pixel groups", {
  # 3x3 raster, pixels 1 and 4 (indices) burned
  rstCurrentBurn <- terra::rast(nrows = 3, ncols = 3,
                                 vals = c(1, 0, 0, 1, 0, 0, 0, 0, 0))
  pixelGroupMap  <- terra::rast(nrows = 3, ncols = 3, vals = 1:9)
  cohortData <- data.table::data.table(pixelGroup = 1:9, B = rep(100, 9))

  result <- computeBurnBiomass(rstCurrentBurn, pixelGroupMap, cohortData)
  expect_equal(result, 200)  # pixels 1 and 4, each B=100
})

test_that("computeBurnBiomass handles multiple cohorts per pixel group", {
  rstCurrentBurn <- terra::rast(nrows = 2, ncols = 2, vals = c(1, 0, 0, 0))
  pixelGroupMap  <- terra::rast(nrows = 2, ncols = 2, vals = c(1, 2, 3, 4))
  # pixel group 1 has 2 cohorts
  cohortData <- data.table::data.table(pixelGroup = c(1, 1, 2, 3, 4),
                                        B = c(50, 75, 100, 100, 100))

  result <- computeBurnBiomass(rstCurrentBurn, pixelGroupMap, cohortData)
  expect_equal(result, 125)  # 50 + 75 for the two cohorts in pixel group 1
})

test_that("computeBurnBiomass ignores NA pixels in pixelGroupMap", {
  rstCurrentBurn <- terra::rast(nrows = 2, ncols = 2, vals = c(1, 1, 0, 0))
  pgVals <- c(1, NA, 3, 4)
  pixelGroupMap  <- terra::rast(nrows = 2, ncols = 2, vals = pgVals)
  cohortData <- data.table::data.table(pixelGroup = c(1, 3, 4), B = c(100, 100, 100))

  result <- computeBurnBiomass(rstCurrentBurn, pixelGroupMap, cohortData)
  expect_equal(result, 100)  # only pixel group 1 (not NA pixel group)
})

test_that("computeMissedHarvest returns NA when no tif exists for that year", {
  result <- computeMissedHarvest(
    basenames      = "tsa_nonexistent",
    tifDir         = tempdir(),
    year           = 9999,
    rstCurrentBurn = terra::rast(nrows = 2, ncols = 2, vals = 0),
    resInHA        = 1
  )
  expect_true(is.na(result$planned))
  expect_true(is.na(result$missed))
})

test_that("computeMissedHarvest counts planned pixels and overlap with burn", {
  tmp <- tempdir()
  bn  <- "testTSA_missed"
  dir.create(file.path(tmp, bn), showWarnings = FALSE)

  # Write planned harvest raster: pixels 1 and 2 planned (out of 4)
  plannedVals <- c(1, 1, 0, 0)
  plannedRst  <- terra::rast(nrows = 2, ncols = 2, vals = plannedVals)
  terra::writeRaster(plannedRst,
                     file.path(tmp, bn, "projected_harvest_5.tif"),
                     overwrite = TRUE)

  # Burn raster: pixel 1 burned
  burnRst <- terra::rast(nrows = 2, ncols = 2, vals = c(1, 0, 0, 0))

  result <- computeMissedHarvest(
    basenames      = bn,
    tifDir         = tmp,
    year           = 5,
    rstCurrentBurn = burnRst,
    resInHA        = 1
  )
  expect_equal(result$planned, 2)   # 2 planned pixels × 1 ha/pixel
  expect_equal(result$missed,  1)   # 1 pixel was both planned and burned
})

test_that("computeMissedHarvest mosaics multiple basenames", {
  tmp <- tempdir()
  for (bn in c("tsaA_missed", "tsaB_missed")) {
    dir.create(file.path(tmp, bn), showWarnings = FALSE)
    r <- terra::rast(nrows = 2, ncols = 2, vals = c(1, 0, 0, 0))
    terra::writeRaster(r, file.path(tmp, bn, "projected_harvest_10.tif"),
                       overwrite = TRUE)
  }
  burnRst <- terra::rast(nrows = 2, ncols = 2, vals = 0)

  result <- computeMissedHarvest(
    basenames      = c("tsaA_missed", "tsaB_missed"),
    tifDir         = tmp,
    year           = 10,
    rstCurrentBurn = burnRst,
    resInHA        = 1
  )
  # Each basename contributes 1 planned pixel; mosaic merges them
  # Since both rasters have same extent and pixel 1 = 1, mosaic gives 1 planned pixel
  expect_gte(result$planned, 1)
  expect_equal(result$missed, 0)
})

test_that("queryFmStats returns numeric harvestVol and growingStock (integration, skipped)", {
  skip("Integration test: requires Python + ws3. Run manually with a live sim.")
  # Manual verification: after running global.R, call:
  #   reticulate::py_run_string("import ws3")
  #   stats <- queryFmStats(fm = py$fm, period = 1L)
  #   stopifnot(is.numeric(stats$harvestVol), is.numeric(stats$growingStock))
  #   cat("harvestVol:", stats$harvestVol, "growingStock:", stats$growingStock, "\n")
})
