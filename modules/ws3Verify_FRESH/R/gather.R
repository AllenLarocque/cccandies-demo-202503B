# gather.R
# Stack ws3VerifyTables (and ws3VerifyMaps) from several runs, for multi-run figures and analysis.
# Works outside SpaDES: source this file and call gatherWs3VerifyTables().

.scfmFile <- "scfmDiagnostics_single_summary_dt.csv"

.runKeysOf <- function(tb) unique(tb$ageDT[, .(scenario, rep)])

.stackTables <- function(runs) {
  keys <- data.table::rbindlist(lapply(runs, .runKeysOf))
  dup <- keys[duplicated(keys)]
  if (nrow(dup))
    stop("ws3Verify_FRESH: several runs share scenario/rep: ",
         paste(dup$scenario, dup$rep, sep = " rep ", collapse = ", "), call. = FALSE)
  nms <- unique(unlist(lapply(runs, names)))
  out <- lapply(stats::setNames(nms, nms), function(n)
    data.table::rbindlist(lapply(runs, `[[`, n), use.names = TRUE, fill = TRUE))
  out[vapply(out, nrow, 1L) > 0]
}

.withScfm <- function(tb, scfm) {
  if (is.null(scfm) || !NROW(scfm)) return(tb)
  k <- .runKeysOf(tb)
  s <- data.table::as.data.table(scfm)
  s <- s[, setdiff(names(s), c("V1", "")), with = FALSE]       # write.csv's row-name column
  tb$scfmSummaryDT <- cbind(k[rep(1, nrow(s))], tsa = NA_character_, s)
  tb
}

#' Stack ws3VerifyTables from several runs.
#'
#' @param x Output folder(s), searched recursively for ws3VerifyTables*.rds (each run's
#'   scfmDiagnostics_single_summary_dt.csv, if next to it, becomes scfmSummaryDT); or an
#'   environment of simLists such as SpaDES.experiment::experiment2()'s result.
#' @return Named list of stacked tables. Errors if two runs share scenario and rep.
gatherWs3VerifyTables <- function(x) {
  runs <- if (is.environment(x)) {
    lapply(ls(x), function(n) { s <- get(n, envir = x); .withScfm(s$ws3VerifyTables, s$scfmSummaryDT) })
  } else {
    files <- list.files(x, pattern = "^ws3VerifyTables.*\\.rds$", recursive = TRUE, full.names = TRUE)
    if (!length(files)) stop("ws3Verify_FRESH: no ws3VerifyTables*.rds under ", paste(x, collapse = ", "), call. = FALSE)
    lapply(files, function(f) {
      sf <- file.path(dirname(f), .scfmFile)
      .withScfm(readRDS(f), if (file.exists(sf)) utils::read.csv(sf) else NULL)
    })
  }
  .stackTables(runs)
}

#' Each run's end-of-run maps (ws3VerifyMaps*.tif under the folders, or sim$ws3VerifyMaps).
gatherWs3VerifyMaps <- function(x) {
  if (is.environment(x)) return(lapply(ls(x), function(n) get(n, envir = x)$ws3VerifyMaps))
  files <- list.files(x, pattern = "^ws3VerifyMaps.*\\.tif$", recursive = TRUE, full.names = TRUE)
  lapply(files, terra::rast)
}
