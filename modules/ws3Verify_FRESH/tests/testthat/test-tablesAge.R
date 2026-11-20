library(testthat)
library(data.table)

source(test_path("..", "..", "R", "collectStatsHelpers.R"))
source(test_path("..", "..", "R", "tablesCore.R"))
source(test_path("..", "..", "R", "tablesAge.R"))

.pf <- function(age, tsa = rep("tsa41", length(age)), landBase = rep("THLB", length(age)),
                vol = rep(10, length(age))) {
  data.table(cell = seq_along(age), tsa = tsa, landBase = landBase, au = 11, age = age, vol_m3ha = vol)
}

test_that("tabulateAge returns the full TSA x land base x bin grid with area and volume", {
  pf <- .pf(age = c(5, 15, 15, 420, 30, 30),
            tsa = c("tsa41", "tsa41", "tsa40", "tsa40", "tsa41", "tsa41"),
            landBase = c("THLB", "THLB", "Non-THLB", "THLB", "Non-THLB", "Non-THLB"),
            vol = c(1, 2, 3, 4, 5, 6))
  out <- tabulateAge(pf, resInHA = 6.25)
  expect_named(out, c("tsa", "landBase", "ageBin", "area_ha", "vol_m3"))
  expect_equal(nrow(out), 2 * 2 * 41)
  expect_equal(sum(out$area_ha), 6 * 6.25)
  expect_equal(out[tsa == "tsa41" & landBase == "Non-THLB" & ageBin == 30, c(area_ha, vol_m3)], c(2 * 6.25, 11 * 6.25))
  expect_equal(out[tsa == "tsa40" & landBase == "THLB" & ageBin == 400, area_ha], 6.25)
  expect_equal(out[tsa == "tsa40" & landBase == "THLB" & ageBin == 0, area_ha], 0)
})

test_that("checkAges finds nothing to flag when every pixel ages by one year", {
  pf <- .pf(age = c(11, 21, 31))
  out <- checkAges(pf, prevAge = c(10, 20, 30), burnedLast = integer(0), resInHA = 1)[landBase == "THLB"]
  expect_equal(out$pixels, 3L)
  expect_equal(out$forest_ha, 3)
  expect_equal(out$reset_n, 0L)
  expect_equal(out$unexplainedAgeChange_n, 0L)
  expect_equal(out$burnedLastYear_n, 0L)
  expect_equal(out$meanAgeChange, 1)
  expect_equal(out$expectedMeanAgeChange, 1)
})

test_that("checkAges: a burned pixel that keeps ageing shows in the reset ratio, not as unexplained", {
  # the original coupling bug: fire burned cells 1 and 2 last year, only cell 1 restarted
  pf <- .pf(age = c(1, 51, 31))
  out <- checkAges(pf, prevAge = c(0, 50, 30), burnedLast = c(1L, 2L), resInHA = 1)[landBase == "THLB"]
  expect_equal(out$burnedLastYear_n, 2L)
  expect_equal(out$burnedLastYearReset_n, 1L)
  expect_equal(out$unexplainedAgeChange_n, 0L)
})

test_that("checkAges counts a jump of more than one year as unexplained (the decadal pulse)", {
  pf <- .pf(age = c(30, 21, 1))
  out <- checkAges(pf, prevAge = c(20, 20, 80), burnedLast = integer(0), resInHA = 1)[landBase == "THLB"]
  expect_equal(out$unexplainedAgeChange_n, 1L)
  expect_equal(out$reset_n, 1L)                       # cell 3 harvested: 80 -> 1
  expect_equal(out$meanAgeChange, (10 + 1 - 79) / 3)
  expect_equal(out$expectedMeanAgeChange, (1 + 1 - 79) / 3)
})

test_that("checkAges counts a reset to an age above resetAgeMax as unexplained", {
  pf <- .pf(age = c(40))
  out <- checkAges(pf, prevAge = c(80), burnedLast = integer(0), resInHA = 1, resetAgeMax = 2L)[landBase == "THLB"]
  expect_equal(out$reset_n, 1L)
  expect_equal(out$unexplainedAgeChange_n, 1L)
})

test_that("checkAges in the first year has counts but no change columns", {
  pf <- .pf(age = c(10, 20))
  out <- checkAges(pf, prevAge = NULL, burnedLast = integer(0), resInHA = 1)[landBase == "THLB"]
  expect_equal(out$pixels, 2L)
  expect_true(is.na(out$meanAgeChange))
  expect_true(is.na(out$unexplainedAgeChange_n))
})

test_that("checkAges reports one row per TSA x land base and carries NA-age counts", {
  pf <- .pf(age = c(11, 21, 31), tsa = c("tsa41", "tsa40", "tsa40"), landBase = c("THLB", "THLB", "Non-THLB"))
  na <- data.table(tsa = "tsa40", landBase = "THLB", naAge_n = 2L)
  out <- checkAges(pf, prevAge = c(10, 20, 30), burnedLast = integer(0), resInHA = 1, naAge = na)
  expect_equal(nrow(out), 4)
  expect_equal(out[tsa == "tsa40" & landBase == "THLB", naAge_n], 2L)
  expect_equal(out[tsa == "tsa41" & landBase == "Non-THLB", pixels], 0L)
  expect_equal(out[tsa == "tsa41" & landBase == "THLB", naAge_n], 0L)
})

test_that("naAgeCounts counts forest cells with a TSA but no age", {
  ls <- .landscapeFixture(fmuid = c(41, 41, 40, 40), thlb = c(1, 0, 1, 1), au = 11, age = c(10, NA, NA, 5))
  out <- naAgeCounts(ls, basenames = list("tsa41", "tsa40"))
  expect_equal(out[tsa == "tsa41" & landBase == "Non-THLB", naAge_n], 1L)
  expect_equal(out[tsa == "tsa40" & landBase == "THLB", naAge_n], 1L)
})
