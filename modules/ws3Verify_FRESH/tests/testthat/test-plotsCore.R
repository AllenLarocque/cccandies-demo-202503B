library(testthat)
library(data.table)

source(test_path("..", "..", "R", "plotsCore.R"))

test_that("selectTsa keeps all TSAs by default and filters otherwise", {
  dt <- data.table(tsa = c("a", "b", NA), x = 1:3)
  expect_equal(nrow(selectTsa(dt)), 3)
  expect_equal(selectTsa(dt, "b")$x, 2L)
})

test_that("sumOverTsa sums within a run, or keeps TSAs apart when faceting", {
  dt <- data.table(scenario = "s", rep = 1L, tsa = c("a", "b"), year = 1L, x = c(2, 3))
  expect_equal(sumOverTsa(dt, "x")$x, 5)
  expect_equal(sumOverTsa(dt, "x", facet = "tsa")$x, c(2, 3))
})

test_that("summariseRuns: one run gives lo = hi = mean; many runs give 5-95% quantiles", {
  one <- data.table(scenario = "s", rep = 1L, year = 1L, x = 7)
  s1 <- summariseRuns(one, "x", by = "year")
  expect_equal(c(s1$mean, s1$lo, s1$hi, s1$nRuns), c(7, 7, 7, 1))
  many <- data.table(scenario = "s", rep = 1:21, year = 1L, x = 0:20)
  s2 <- summariseRuns(many, "x", by = "year")
  expect_equal(s2$mean, 10)
  expect_equal(s2$lo, 1)
  expect_equal(s2$hi, 19)
  expect_equal(s2$nRuns, 21L)
})

test_that("ratioPerRun pools numerators and denominators, not per-TSA ratios", {
  dt <- data.table(scenario = "s", rep = 1L, tsa = c("a", "b"), year = 1L, num = c(1, 9), den = c(1, 99))
  r <- ratioPerRun(dt, "num", "den", by = "year")
  expect_equal(r$mean, 10 / 100)                               # mean of ratios would be 0.545
})

test_that("ratioPerRun gives NA, not an error, when the denominator is 0", {
  dt <- data.table(scenario = "s", rep = 1L, tsa = "a", year = 1L, num = 0, den = 0)
  expect_true(is.na(ratioPerRun(dt, "num", "den", by = "year")$mean))
})

test_that("runCount counts runs per scenario", {
  dt <- data.table(scenario = c("s", "s", "t"), rep = c(1L, 2L, 1L))
  expect_equal(runCount(dt), 2L)
})
