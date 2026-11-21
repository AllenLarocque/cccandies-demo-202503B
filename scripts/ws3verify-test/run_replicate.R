## Test run for the ws3Verify_FRESH figure sets: tsa41 + tsa40, 100 years, one replicate per call.
## Peaks at about 52 GB (first re-plan, year 10). Run replicates one after another, never in parallel.
## Usage, from the repo root:  Rscript scripts/ws3verify-test/run_replicate.R <rep>
## Writes output/fixed_fm15_rep<rep>/ (ws3VerifyTables_year100.rds, ws3VerifyMaps_year100.tif, figures/).
r <- as.integer(commandArgs(TRUE)[1])
stopifnot(!is.na(r))
t0 <- Sys.time()
runOverrides <- list(
  basenames = list("tsa41", "tsa40"), base.year = 2020, horizon = 10, period_length = 10,
  planning_period_freq = 10, scheduler.mode = "optimize",
  times = list(start = 0, end = 100), .rep = sprintf("fixed_fm15_rep%d", r),
  n_ws3_workers = 1L, fireMultiplier = 1.5, targetN = 1000,
  verifyScenario = "fm15", verifyRep = r)
# Recovery mode copies the whole simList every event (minutes and tens of GB with two TSAs); it only
# serves restarting after an error, and with it on a two-TSA run was OOM-killed.
options(spades.recoveryMode = FALSE)
# Each .rep gets its own input folder; reuse replicate 1's downloads (about 10 GB of land cover)
# instead of fetching them again. reproducible links files it finds here.
if (r > 1 && dir.exists("input/fixed_fm15_rep1"))
  options(reproducible.inputPaths = normalizePath("input/fixed_fm15_rep1"))
system2("uv", c("python", "install", "3.12"))
runOverrides$pythonPath <- system2("uv", c("python", "find", "--managed-python", "3.12"), stdout = TRUE)
tryCatch(source("global.R"), finally = rm(runOverrides, envir = globalenv()))
message("DONE rep ", r, " in ", format(Sys.time() - t0))
tb <- simout$ws3VerifyTables
cat("CHECK unexplained:", sum(tb$checkDT$unexplainedAgeChange_n, na.rm = TRUE),
    " burnedReset:", sum(tb$checkDT$burnedReset_n, na.rm = TRUE), "/", sum(tb$checkDT$burned_n, na.rm = TRUE),
    " V1 maxGap:", max(abs(tb$harvestDT$applied_ws3_ha - tb$harvestDT$harvested_landscape_ha), na.rm = TRUE),
    " violations:", sum(tb$harvestDT$planRuleViolations_n),
    " tolerated:", sum(tb$harvestDT$planRuleTolerated_n),
    " naAge:", sum(tb$checkDT$naAge_n), "\n")
print(list.files(outputPath(simout), "ws3Verify"))
