library(testthat)
library(data.table)

source(test_path("..", "..", "R", "gather.R"))

.saveRun <- function(dir, scenario, rep, scfm = TRUE) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  tb <- .tablesFixture(years = 0:3, scenarios = scenario)
  r <- as.integer(rep)                     # inside [ ], `rep` would be the column
  tb <- lapply(tb, function(d) d[, rep := r])
  tb$scfmSummaryDT <- NULL
  saveRDS(tb, file.path(dir, "ws3VerifyTables_year3.rds"))
  if (scfm) utils::write.csv(data.frame(PolyID = 1:2, targetFRI = c(300, 600), achievedFRI = c(250, 700)),
                             file.path(dir, "scfmDiagnostics_single_summary_dt.csv"))
  m <- terra::rast(nrows = 2, ncols = 2, nlyrs = 4, vals = rep)
  names(m) <- c("burnCount", "harvestCount", "timeSinceDisturbance", "lastDisturbance")
  terra::writeRaster(m, file.path(dir, "ws3VerifyMaps_year3.tif"))
}

test_that("gatherWs3VerifyTables stacks runs found under output folders, keys intact", {
  d <- withr::local_tempdir()
  .saveRun(file.path(d, "fm15_rep1"), "fm15", 1)
  .saveRun(file.path(d, "fm15_rep2"), "fm15", 2, scfm = FALSE)
  tb <- gatherWs3VerifyTables(d)
  expect_setequal(unique(tb$ageDT$rep), 1:2)
  expect_equal(nrow(tb$harvestDT), 2 * 4)
  expect_equal(unique(tb$scfmSummaryDT[, .(scenario, rep)]), data.table(scenario = "fm15", rep = 1L))
  expect_true(all(is.na(tb$scfmSummaryDT$tsa)))
})

test_that("gatherWs3VerifyTables refuses two runs with the same scenario and rep", {
  d <- withr::local_tempdir()
  .saveRun(file.path(d, "a"), "fm15", 1)
  .saveRun(file.path(d, "b"), "fm15", 1)
  expect_error(gatherWs3VerifyTables(d), "fm15.*1")
})

test_that("gatherWs3VerifyTables reads sims held in an environment (SpaDES.experiment simLists)", {
  e <- new.env()
  for (r in 1:2) {
    tb <- lapply(.tablesFixture(years = 0:2), function(d) d[, rep := r])
    assign(sprintf("fm15_rep%d", r), list(ws3VerifyTables = tb, scfmSummaryDT = data.table(PolyID = 1L, targetFRI = 300)), envir = e)
  }
  tb <- gatherWs3VerifyTables(e)
  expect_setequal(unique(tb$ageDT$rep), 1:2)
  expect_equal(nrow(tb$scfmSummaryDT), 2)
})

test_that("gatherWs3VerifyMaps returns one SpatRaster per run", {
  d <- withr::local_tempdir()
  .saveRun(file.path(d, "r1"), "s", 1); .saveRun(file.path(d, "r2"), "s", 2)
  m <- gatherWs3VerifyMaps(d)
  expect_length(m, 2)
  expect_s4_class(m[[1]], "SpatRaster")
  expect_equal(names(m[[1]]), c("burnCount", "harvestCount", "timeSinceDisturbance", "lastDisturbance"))
})
