library(testthat)
library(data.table)

for (f in c("plotsCore.R", "plotsVerification.R", "plotsBiology.R", "figureSets.R", "makePlotsHelpers.R"))
  source(test_path("..", "..", "R", f))

.savePng <- function(p, file) ggplot2::ggsave(paste0(file, ".png"), p, width = 9, height = 6, dpi = 40)

test_that("writeFigureSets writes the verification and biological sets, V6 only with an scfm summary", {
  d <- withr::local_tempdir()
  tb <- .tablesFixture(nRuns = 2, tsas = c("tsa41", "tsa40"), years = 0:30)
  m <- terra::rast(nrows = 3, ncols = 3, nlyrs = 4, vals = 1)
  names(m) <- c("burnCount", "harvestCount", "timeSinceDisturbance", "lastDisturbance")
  writeFigureSets(tb, m, d, types = "png", save = .savePng)
  v <- list.files(file.path(d, "verification")); b <- list.files(file.path(d, "biology"))
  expect_setequal(v, paste0(c("V1_harvest", "V2_fireReset", "V3_ageBalance", "V4_harvestRule", "V5_planVsCut",
                              "V6_fireRegime", "V7_conservation"), ".png"))
  expect_setequal(b, paste0(c("B1_ageStructure", "B2_growingStock", "B3_woodSupply", "B4_oldForest", "B5_fire",
                              "B6_fireSelectivity", "B7_disturbanceMix", "B8_burnedVolume", "B9_maps"), ".png"))
  tb$scfmSummaryDT <- NULL
  d2 <- withr::local_tempdir()
  writeFigureSets(tb, m, d2, types = "png", save = .savePng)
  expect_false("V6_fireRegime.png" %in% list.files(file.path(d2, "verification")))
})

test_that("writeFigureSets with facet = 'tsa' adds per-TSA versions alongside", {
  d <- withr::local_tempdir()
  tb <- .tablesFixture(tsas = c("tsa41", "tsa40"), years = 0:20)
  writeFigureSets(tb, NULL, d, types = "png", save = .savePng, byTsa = TRUE)
  expect_true("V1_harvest_byTSA.png" %in% list.files(file.path(d, "verification")))
  expect_true("B1_ageStructure_byTSA.png" %in% list.files(file.path(d, "biology")))
})
