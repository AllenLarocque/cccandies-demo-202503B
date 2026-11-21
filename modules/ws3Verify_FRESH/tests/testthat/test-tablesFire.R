library(testthat)
library(data.table)

source(test_path("..", "..", "R", "collectStatsHelpers.R"))
source(test_path("..", "..", "R", "tablesCore.R"))
source(test_path("..", "..", "R", "tablesFire.R"))

.pf <- data.table(cell = 1:4, tsa = c("tsa41", "tsa41", "tsa40", "tsa40"),
                  landBase = c("THLB", "Non-THLB", "THLB", "THLB"), au = 11,
                  age = c(15, 99, 25, 5), vol_m3ha = c(150, 300, 250, 50))

test_that("tabulateFire splits burned area and volume by TSA, land base and pre-fire age", {
  out <- tabulateFire(.pf, burnedCells = c(1L, 2L, 3L, 4L), resInHA = 2)
  expect_named(out, c("tsa", "landBase", "ageBin", "burned_ha", "burnedVol_m3"))
  expect_equal(sum(out$burned_ha), 8)
  expect_equal(out[tsa == "tsa41" & landBase == "Non-THLB", c(ageBin, burned_ha, burnedVol_m3)], c(90, 2, 600))
  expect_equal(out[tsa == "tsa40" & landBase == "THLB", sum(burned_ha)], 4)
})

test_that("burned cells outside ws3's forest are kept as 'outside forest'", {
  out <- tabulateFire(.pf, burnedCells = c(1L, 7L, 9L), resInHA = 1)
  o <- out[landBase == "outside forest"]
  expect_equal(nrow(o), 1)
  expect_true(is.na(o$tsa))
  expect_true(is.na(o$ageBin))
  expect_equal(o$burned_ha, 2)
  expect_equal(o$burnedVol_m3, 0)
})

test_that("tabulateFire's volume equals computeBurnVolume on the same pixels", {
  y <- .yieldFixture()
  au <- terra::rast(nrows = 1, ncols = 4, vals = c(11, 11, 12, 11))
  age <- terra::rast(nrows = 1, ncols = 4, vals = c(15, 99, 20, 5))
  burn <- terra::rast(nrows = 1, ncols = 4, vals = c(1, 1, 1, 0))
  pf <- data.table(cell = 1:4, tsa = "tsa41", landBase = "THLB", au = c(11, 11, 12, 11), age = c(15, 99, 20, 5))
  pf[, vol_m3ha := pixelVolume(au, age, y)]
  expect_equal(sum(tabulateFire(pf, 1:3, resInHA = 2)$burnedVol_m3), computeBurnVolume(burn, au, age, y, 2))
})

test_that("tabulateFire returns an empty table with the right columns in a year without fire", {
  out <- tabulateFire(.pf, burnedCells = integer(0), resInHA = 1)
  expect_equal(nrow(out), 0)
  expect_named(out, c("tsa", "landBase", "ageBin", "burned_ha", "burnedVol_m3"))
})

test_that("fireEvents gives one row per fire with its size and the TSA of its ignition cell", {
  bs <- data.table(igLoc = c(1L, 3L, 9L, 2L), grp = 1L, N = c(4, 1, 2, 3), year = c(5, 5, 5, 6),
                   areaBurned = c(25, 6.25, 12.5, 18.75), PolyID = c(1L, 2L, 2L, 1L))
  cellTsa <- c("tsa41", "tsa41", "tsa40", "tsa40", rep(NA, 5))
  out <- fireEvents(bs, year = 5, cellTsa = cellTsa)
  expect_equal(out$size_ha, c(25, 6.25, 12.5))
  expect_equal(out$tsa, c("tsa41", "tsa40", NA))
  expect_equal(out$PolyID, c(1L, 2L, 2L))
  expect_equal(nrow(fireEvents(bs, year = 7, cellTsa = cellTsa)), 0)
})
