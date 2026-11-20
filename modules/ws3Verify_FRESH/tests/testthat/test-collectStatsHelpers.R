library(testthat)
library(data.table)
library(terra)

source(test_path("..", "..", "R", "collectStatsHelpers.R"))
source(test_path("..", "..", "R", "tablesCore.R"))

test_that("initAnnualDT returns empty data.table with correct columns", {
  dt <- initAnnualDT()
  expect_s3_class(dt, "data.table")
  expect_equal(nrow(dt), 0)
  expect_named(dt, c("year", "harvestArea_ha", "burnArea_ha", "burnedVol_m3",
                      "burnedBiomass_t", "harvestVol_m3", "growingStock_m3"))
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
                         burnedVol_m3 = 7000, burnedBiomass_t = 5000)
  expect_equal(nrow(dt), 1)
  expect_equal(dt$year, 5)
  expect_equal(dt$harvestArea_ha, 200)
  expect_equal(dt$burnArea_ha, 100)
  expect_equal(dt$burnedVol_m3, 7000)
  expect_equal(dt$burnedBiomass_t, 5000)
  expect_true(is.na(dt$harvestVol_m3))
  expect_true(is.na(dt$growingStock_m3))
})

test_that("appendAnnualRow stores volume and GS when provided", {
  dt <- initAnnualDT()
  dt <- appendAnnualRow(dt, year = 10, harvestArea_ha = 300, burnArea_ha = 50,
                         burnedVol_m3 = 3000, burnedBiomass_t = 2000,
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

# resInHA = 100 ha = 1e6 m2, so the expected tonnes equal the summed B (g/m2).
test_that("computeBurnBiomass returns 0 when nothing burned", {
  rstCurrentBurn <- terra::rast(nrows = 3, ncols = 3, vals = 0)
  pixelGroupMap  <- terra::rast(nrows = 3, ncols = 3, vals = 1:9)
  cohortData <- data.table::data.table(pixelGroup = 1:9, B = rep(100, 9))

  result <- computeBurnBiomass(rstCurrentBurn, pixelGroupMap, cohortData, resInHA = 100)
  expect_equal(result, 0)
})

test_that("computeBurnBiomass sums B for all burned pixel groups", {
  # 3x3 raster, pixels 1 and 4 (indices) burned
  rstCurrentBurn <- terra::rast(nrows = 3, ncols = 3,
                                 vals = c(1, 0, 0, 1, 0, 0, 0, 0, 0))
  pixelGroupMap  <- terra::rast(nrows = 3, ncols = 3, vals = 1:9)
  cohortData <- data.table::data.table(pixelGroup = 1:9, B = rep(100, 9))

  result <- computeBurnBiomass(rstCurrentBurn, pixelGroupMap, cohortData, resInHA = 100)
  expect_equal(result, 200)  # pixels 1 and 4, each B=100
})

test_that("computeBurnBiomass handles multiple cohorts per pixel group", {
  rstCurrentBurn <- terra::rast(nrows = 2, ncols = 2, vals = c(1, 0, 0, 0))
  pixelGroupMap  <- terra::rast(nrows = 2, ncols = 2, vals = c(1, 2, 3, 4))
  # pixel group 1 has 2 cohorts
  cohortData <- data.table::data.table(pixelGroup = c(1, 1, 2, 3, 4),
                                        B = c(50, 75, 100, 100, 100))

  result <- computeBurnBiomass(rstCurrentBurn, pixelGroupMap, cohortData, resInHA = 100)
  expect_equal(result, 125)  # 50 + 75 for the two cohorts in pixel group 1
})

test_that("computeBurnBiomass ignores NA pixels in pixelGroupMap", {
  rstCurrentBurn <- terra::rast(nrows = 2, ncols = 2, vals = c(1, 1, 0, 0))
  pgVals <- c(1, NA, 3, 4)
  pixelGroupMap  <- terra::rast(nrows = 2, ncols = 2, vals = pgVals)
  cohortData <- data.table::data.table(pixelGroup = c(1, 3, 4), B = c(100, 100, 100))

  result <- computeBurnBiomass(rstCurrentBurn, pixelGroupMap, cohortData, resInHA = 100)
  expect_equal(result, 100)  # only pixel group 1 (not NA pixel group)
})

test_that("computeBurnBiomass converts g/m2 to tonnes with the pixel area", {
  rstCurrentBurn <- terra::rast(nrows = 1, ncols = 2, vals = c(1, 1))
  pixelGroupMap  <- terra::rast(nrows = 1, ncols = 2, vals = c(1, 1))
  cohortData <- data.table::data.table(pixelGroup = 1, B = 5000)   # 5000 g/m2 = 50 t/ha
  # 2 burned pixels x 6.25 ha x 50 t/ha
  expect_equal(computeBurnBiomass(rstCurrentBurn, pixelGroupMap, cohortData, resInHA = 6.25), 625)
})

.writeYieldTables <- function(dir) {
  utils::write.csv(data.frame(au_id = c(11, 12), unmanaged_curve_id = c(101, 102),
                              managed_curve_id = c(101, 102)),
                   file.path(dir, "au_table.csv"))
  utils::write.csv(data.frame(curve_id = c(rep(101, 5), rep(102, 3)),
                              x = c(0, 10, 15, 20, 30, 0, 10, 20),
                              y = c(0, 100, 999, 200, 300, 0, 50, 100)),
                   file.path(dir, "curve_points_table.csv"))
}

test_that("loadYieldCurves maps AUs to curves and keeps only period points", {
  d <- withr::local_tempdir()
  .writeYieldTables(d)
  y <- loadYieldCurves(file.path(d, "au_table.csv"), file.path(d, "curve_points_table.csv"))
  expect_equal(unname(y$auToCurve[c("11", "12")]), c(101, 102))
  expect_equal(y$points[["101"]]$x, c(0, 10, 20, 30))   # x = 15 dropped, as in bootstrap_yields
  expect_equal(y$points[["101"]]$y, c(0, 100, 200, 300))
})

test_that("computeBurnVolume sums curve volume x area over burned pixels", {
  d <- withr::local_tempdir()
  .writeYieldTables(d)
  y <- loadYieldCurves(file.path(d, "au_table.csv"), file.path(d, "curve_points_table.csv"))
  burn <- terra::rast(nrows = 1, ncols = 5, vals = c(1, 1, 1, 1, 0))
  au   <- terra::rast(nrows = 1, ncols = 5, vals = c(11, 11, 12, NA, 11))
  age  <- terra::rast(nrows = 1, ncols = 5, vals = c(15, 99, 20, 30, 30))
  # pixel 1: AU 11 at 15 -> 150 (interpolated); pixel 2: at 99 -> 300 (held at the last point);
  # pixel 3: AU 12 at 20 -> 100; pixel 4: no AU -> 0; pixel 5 did not burn.
  expect_equal(computeBurnVolume(burn, au, age, y, resInHA = 2), (150 + 300 + 100) * 2)
  expect_equal(computeBurnVolume(burn * 0, au, age, y, resInHA = 2), 0)
})

test_that("computeBurnVolume uses AU ids, not category indices, of a categorical au layer", {
  d <- withr::local_tempdir()
  .writeYieldTables(d)
  y <- loadYieldCurves(file.path(d, "au_table.csv"), file.path(d, "curve_points_table.csv"))
  burn <- terra::rast(nrows = 1, ncols = 2, vals = c(1, 1))
  au   <- terra::rast(nrows = 1, ncols = 2, vals = c(1, 2))   # category indices
  levels(au) <- data.frame(ID = 1:2, value = c(11, 12))       # AU ids
  age  <- terra::rast(nrows = 1, ncols = 2, vals = c(20, 20))
  expect_equal(computeBurnVolume(burn, au, age, y, resInHA = 1), 200 + 100)
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
  #   stats <- queryFmStats(fm = py$fm)
  #   stopifnot(is.numeric(stats$harvestVol), is.numeric(stats$growingStock))
  #   cat("harvestVol:", stats$harvestVol, "growingStock:", stats$growingStock, "\n")
})

test_that("queryFmStats reads the current plan: harvest from period 1, stock from period 0", {
  # Mock ForestModel that, like ws3, only knows periods 0..horizon of the plan just made
  horizon <- 10L
  calls <- list()
  fm <- list(
    compile_product = function(period, expr, acode) {
      calls$harvest <<- period
      if (period < 1L || period > horizon) stop("KeyError: ", period)
      c(500, 0, 0, 0, 0, 0, 0, 0, 0, 0)[period]
    },
    inventory = function(period, yname) {
      calls$stock <<- period
      if (period < 0L || period > horizon) stop("KeyError: ", period)
      1e6 - 1e4 * period
    }
  )
  stats <- queryFmStats(fm)
  expect_identical(calls$harvest, 1L)
  expect_identical(calls$stock, 0L)
  expect_equal(stats$harvestVol, 500)
  expect_equal(stats$growingStock, 1e6)
})

test_that("CollectStats queries the fm without a period counted from the simulation start", {
  # Regression: period = (time - start) / planFreq walked off the 10-period plan at year 110
  src <- paste(readLines(test_path("..", "..", "ws3Verify_FRESH.R")), collapse = "\n")
  expect_false(grepl("queryFmStats\\(fm = sim\\$fm, period", src))
  expect_match(src, "queryFmStats\\(fm = sim\\$fm\\)")
})

test_that("calendarYear converts simulation time to the calendar year spades_ws3 uses", {
  expect_identical(calendarYear(0, 0, 2020), 2020L)
  expect_identical(calendarYear(37, 0, 2020), 2057L)
  expect_identical(calendarYear(2011, 2011, 2015), 2015L)
  expect_error(calendarYear(1, 0, NULL), "base.year")
})

test_that("CollectStats looks up the planned-harvest raster by calendar year", {
  # Regression: it passed time(sim), so it looked for projected_harvest_0.tif and never found one
  src <- paste(readLines(test_path("..", "..", "ws3Verify_FRESH.R")), collapse = "\n")
  expect_match(src, "year += calendarYear\\(t, start\\(sim\\), baseYear\\)")
  expect_match(src, "baseYear <- params\\(sim\\)\\$spades_ws3\\$base\\.year")
  expect_false(grepl("year += t,\\s*\\n\\s*rstCurrentBurn", src))
})

test_that("computeMissedHarvest finds the calendar-year file spades_ws3 writes", {
  tifDir <- withr::local_tempdir()
  dir.create(file.path(tifDir, "tsaX"))
  r <- terra::rast(nrows = 2, ncols = 2, vals = c(1, 1, NA, NA))
  terra::writeRaster(r, file.path(tifDir, "tsaX", "projected_harvest_2025.tif"))
  burn <- terra::rast(r); terra::values(burn) <- c(1, 0, 0, 0)
  res <- computeMissedHarvest("tsaX", tifDir, calendarYear(5, 0, 2020), burn, resInHA = 6.25)
  expect_equal(res$planned, 2 * 6.25)
  expect_equal(res$missed, 6.25)
})

test_that("missedFromTimingStats sums planned and skipped pixels over units for the year", {
  ts <- data.table::data.table(year = c(2025, 2025, 2026), basename = c("a", "b", "a"),
                               plannedPixels = c(10, 6, 9), appliedPixels = c(9, 6, 9),
                               skippedResetPixels = c(1, 0, 0))
  expect_equal(missedFromTimingStats(ts, 2025, 6.25), list(planned = 16 * 6.25, missed = 6.25))
  expect_equal(missedFromTimingStats(ts, 2030, 6.25), list(planned = NA_real_, missed = NA_real_))
})

test_that("tabulateAgeByLandBase splits area by THLB and age class, with zero rows", {
  age  <- terra::rast(nrows = 2, ncols = 4, vals = c(0, 49, 50, 150, 250, 300, 450, NA))
  thlb <- terra::rast(nrows = 2, ncols = 4, vals = c(1, 1, 1, 1, 0, 0, 0, 0))
  out <- tabulateAgeByLandBase(age, thlb, year = 7, resInHA = 6.25)
  expect_equal(nrow(out), 2 * 5)
  expect_true(all(out$year == 7L))
  expect_equal(sum(out$area_ha), 7 * 6.25)                       # NA age dropped
  get <- function(lb, cl) out[landBase == lb & ageClass == cl, area_ha]
  expect_equal(get("THLB", "0-49"), 2 * 6.25)
  expect_equal(get("THLB", "50-99"), 6.25)
  expect_equal(get("THLB", "100-199"), 6.25)
  expect_equal(get("THLB", "300+"), 0)
  expect_equal(get("Non-THLB", "200-299"), 6.25)
  expect_equal(get("Non-THLB", "300+"), 2 * 6.25)               # 300 is in 300+, as is 450
})

test_that("tabulateAgeByLandBase reads categorical thlb layers by label", {
  age  <- terra::rast(nrows = 1, ncols = 3, vals = c(10, 120, 320))
  thlb <- terra::rast(nrows = 1, ncols = 3, vals = c(2, 1, 1))   # indices; labels 1 and 0
  levels(thlb) <- data.frame(value = 1:2, thlb = c(0, 1))
  out <- tabulateAgeByLandBase(age, thlb, year = 0, resInHA = 1)
  expect_equal(out[landBase == "THLB", sum(area_ha)], 1)
  expect_equal(out[landBase == "THLB" & ageClass == "0-49", area_ha], 1)
  expect_equal(out[landBase == "Non-THLB", sum(area_ha)], 2)
})

test_that("ageClassLabels names the classes", {
  expect_equal(ageClassLabels(), c("0-49", "50-99", "100-199", "200-299", "300+"))
})
