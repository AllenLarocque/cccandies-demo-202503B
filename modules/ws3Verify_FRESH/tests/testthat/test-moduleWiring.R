library(testthat)

moduleFile <- normalizePath(test_path("..", "..", "ws3Verify_FRESH.R"))
src <- paste(readLines(moduleFile), collapse = "\n")

# body of a top-level function of the module, as text (the file needs SpaDES to source whole)
fnText <- function(name) {
  for (e in parse(moduleFile, keep.source = FALSE))
    if (is.call(e) && identical(e[[1]], as.name("<-")) && identical(e[[2]], as.name(name)))
      return(paste(deparse(e[[3]]), collapse = "\n"))
  stop("no function ", name)
}

test_that("the module declares the new outputs and parameters", {
  for (o in c("ws3VerifyTables", "ws3VerifyMaps"))
    expect_match(src, sprintf('createsOutput\\("%s"', o))
  for (p in c("scenario", "rep", "oldForestAges", "resetAgeMax", "mode", "multiPaths"))
    expect_match(src, sprintf('defineParameter\\("%s"', p))
})

test_that("Init registers the tables and maps with outputs() by basename, keeping earlier outputs", {
  init <- fnText("Init")
  expect_match(init, "outputs\\(sim\\)")
  expect_match(init, "ws3VerifyTables")
  expect_match(init, "ws3VerifyOutputRows")
  expect_match(init, "rbindlist")
})

test_that("CollectStats fills ws3VerifyTables", {
  cs <- fnText("CollectStats")
  expect_match(cs, "CollectTables")
})

test_that("MakePlots writes the figure sets and the module declares patchwork", {
  expect_match(fnText("MakePlots"), "writeFigureSets")
  expect_match(src, '"patchwork"')
})

test_that("mode = 'multi' gathers saved runs and draws the figure sets instead of collecting", {
  expect_match(src, 'P\\(sim\\)\\$mode == "multi"')
  mp <- fnText("MultiPlots")
  expect_match(mp, "gatherWs3VerifyTables")
  expect_match(mp, "gatherWs3VerifyMaps")
  expect_match(mp, "writeFigureSets")
})
