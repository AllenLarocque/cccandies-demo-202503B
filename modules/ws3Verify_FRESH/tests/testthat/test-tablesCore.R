library(testthat)
library(data.table)
library(terra)

source(test_path("..", "..", "R", "collectStatsHelpers.R"))
source(test_path("..", "..", "R", "tablesCore.R"))

test_that("runKeys reads scenario and rep from a SpaDES.experiment output folder", {
  expect_equal(runKeys("out/fm15_rep03"), list(scenario = "fm15", rep = 3L))
  expect_equal(runKeys("out/1_optimize", scenario = "s", rep = 2L), list(scenario = "s", rep = 2L))
  expect_warning(k <- runKeys("out/a_b_rep1"), "_")
  expect_equal(k, list(scenario = "a_b", rep = 1L))
})

test_that("tsaFromFmuid matches TSA numbers to basenames, zero padding included", {
  expect_equal(tsaFromFmuid(c(41, 8, 40, NA, 99), list("tsa41", "tsa08", "tsa40")),
               c("tsa41", "tsa08", "tsa40", NA, NA))
})

test_that("ageBin gives 10-year lower edges with an open top bin", {
  expect_identical(ageBin(c(0, 9, 10, 399, 400, 706, NA)), c(0L, 0L, 10L, 390L, 400L, 400L, NA))
})

test_that("pixelVolume interpolates the AU's curve, holds the ends, 0 without a curve", {
  y <- .yieldFixture()
  expect_equal(pixelVolume(au = c(11, 11, 12, NA, 13, 11), age = c(15, 99, 20, 30, 10, NA), yields = y),
               c(150, 300, 100, 0, 0, 0))
})

test_that("computeBurnVolume still sums pixelVolume x area over burned pixels", {
  y <- .yieldFixture()
  burn <- terra::rast(nrows = 1, ncols = 5, vals = c(1, 1, 1, 1, 0))
  au   <- terra::rast(nrows = 1, ncols = 5, vals = c(11, 11, 12, NA, 11))
  age  <- terra::rast(nrows = 1, ncols = 5, vals = c(15, 99, 20, 30, 30))
  expect_equal(computeBurnVolume(burn, au, age, y, resInHA = 2), (150 + 300 + 100) * 2)
})

test_that("pixelFrame has one row per forest pixel with TSA and land base read by label", {
  ls <- .landscapeFixture(fmuid = c(41, 41, 40, 40, 40, 41), thlb = c(1, 0, 1, 0, 1, 1),
                          au = c(11, 11, 12, 12, 11, 11), age = c(10, 20, 10, 20, NA, 30), nrows = 2)
  pf <- pixelFrame(ls, basenames = list("tsa41", "tsa40"), yields = .yieldFixture())
  expect_equal(nrow(pf), 5)
  expect_named(pf, c("cell", "tsa", "landBase", "au", "age", "vol_m3ha"))
  expect_equal(pf$cell, c(1L, 2L, 3L, 4L, 6L))
  expect_equal(pf$tsa, c("tsa41", "tsa41", "tsa40", "tsa40", "tsa41"))
  expect_equal(pf$landBase, c("THLB", "Non-THLB", "THLB", "Non-THLB", "THLB"))
  expect_equal(pf$vol_m3ha, c(100, 200, 50, 100, 300))
})

test_that("addKeys prepends scenario, rep and year", {
  dt <- data.table(tsa = "tsa41", x = 1)
  out <- addKeys(dt, list(scenario = "s", rep = 2L), year = 5)
  expect_named(out, c("scenario", "rep", "tsa", "year", "x"))
  expect_identical(out$year, 5L)
  expect_identical(out$rep, 2L)
})

test_that("ws3VerifyOutputRows builds outputs() rows from an end time that carries a unit", {
  endTime <- structure(10, unit = "year")
  rows <- ws3VerifyOutputRows(endTime)
  expect_equal(nrow(rows), 2)
  expect_equal(rows$file, c("ws3VerifyTables.rds", "ws3VerifyMaps.tif"))
  expect_equal(rows$fun, c("saveRDS", "writeRaster"))
  expect_equal(rows$saveTime, c(10, 10))
})

test_that("pixelFrame leaves out cells outside the ws3 inventory (no fmuid), even with an age", {
  # landrAge may give a burned non-forest cell age 0; it must not join the forest
  ls <- .landscapeFixture(fmuid = c(41, NA, 41), thlb = c(1, 0, 0), au = 11, age = c(10, 0, 20))
  pf <- pixelFrame(ls, basenames = list("tsa41"), yields = .yieldFixture())
  expect_equal(pf$cell, c(1L, 3L))
})
