## Redraw the ws3Verify_FRESH figure sets from saved tables, without SpaDES (e.g. after a plot change).
## Usage, from the repo root:
##   Rscript scripts/ws3verify-test/render_figs.R <ws3VerifyTables.rds> <outDir> [ws3VerifyMaps.tif]
## Uses the default harvestAgeTolerance of 0 unless HARVEST_AGE_TOLERANCE is set (the module's
## default is the period length, 10 in the test runs).
suppressMessages({library(data.table); library(ggplot2)})
a <- commandArgs(TRUE)
stopifnot(length(a) >= 2)
for (f in c("plotsCore.R", "plotsVerification.R", "plotsBiology.R", "figureSets.R", "makePlotsHelpers.R"))
  source(file.path("modules/ws3Verify_FRESH/R", f))
tb <- readRDS(a[1])
sv <- function(p, file) ggsave(paste0(file, ".png"), p, width = 10,
                               height = if (grepl("B5", file)) 10 else 5.5, dpi = 100, bg = "white")
maps <- if (length(a) > 2) terra::rast(a[3]) else NULL
tol <- as.numeric(Sys.getenv("HARVEST_AGE_TOLERANCE", "0"))
writeFigureSets(tb, maps, a[2], save = sv, byTsa = TRUE, harvestAgeTolerance = tol)
