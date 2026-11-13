## Smallest end-to-end run of the WS3_FRESH stack: one TSA (tsa41), one 10-year ws3
## planning period plus the re-plan at year 10, scfm fire, ws3Verify_FRESH plots.
##
## Run from the repo root:
##   Rscript global_minimal.R
##
## It sets the run values in `runOverrides`, which global.R applies over its own, then sources global.R.

# Fresh container: the site library is read-only and global.R's bootstrap installs reticulate
# before setupProject() has set up the project library. Put setupProject()'s default project
# library (as in SpaDES.project:::.libPathDefault()) first so the bootstrap installs there too.
# After the first run, the .Rprofile that setupProject() writes does this.
if (!file.exists(".Rprofile")) {
  projLib <- file.path(tools::R_user_dir(basename(getwd()), which = "data"), "packages",
                       R.version$platform, substr(getRversion(), 1, 3))
  dir.create(projLib, recursive = TRUE, showWarnings = FALSE)
  .libPaths(c(projLib, .libPaths()))
}

runOverrides <- list(
  basenames            = list("tsa41"),
  base.year            = 2020,
  horizon              = 10,      # spadesws3_params.py forces horizon = 10 anyway
  period_length        = 10,
  planning_period_freq = 10,
  scheduler.mode       = "optimize",
  times                = list(start = 0, end = 10),  # plans at years 0 and 10
  .rep                 = "minimal_tsa41",
  n_ws3_workers        = 1L,
  fireMultiplier       = 1.5
)

# reticulate::install_python() builds Python from source with pyenv, which needs `patch` (not in
# this image), and the system Python lacks venv (python3-venv). Use uv's prebuilt CPython 3.12
# instead (the same one reticulate itself downloads).
system2("uv", c("python", "install", "3.12"))
runOverrides$pythonPath <- system2("uv", c("python", "find", "--managed-python", "3.12"), stdout = TRUE)

tryCatch(source("global.R"), finally = rm(runOverrides, envir = globalenv()))
