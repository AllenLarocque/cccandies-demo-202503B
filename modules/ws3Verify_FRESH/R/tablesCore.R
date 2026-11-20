# tablesCore.R
# Shared building blocks for ws3VerifyTables: run keys, TSA labels, age bins, per-pixel volume and
# the per-year pixel frame. Pure functions (no sim access).

#' Scenario and replicate of a run.
#'
#' SpaDES.experiment::experiment2() names each run "<simList name>_rep<n>" and puts its outputs in
#' outputPath/<that name>, so the folder name carries both. Other runs use the module params.
#' as.data.table.simLists() cuts simList names at the first "_", so scenarios should not contain one.
#'
#' @param outPath  outputPath(sim).
#' @param scenario,rep Fallbacks when outPath is not an experiment2 run folder.
#' @return list(scenario = character, rep = integer).
runKeys <- function(outPath, scenario = "default", rep = 1L) {
  m <- regmatches(basename(outPath), regexec("^(.+)_rep([0-9]+)$", basename(outPath)))[[1]]
  if (length(m) == 3) {
    scenario <- m[2]
    rep <- as.integer(m[3])
  }
  if (grepl("_", scenario, fixed = TRUE))
    warning("ws3Verify_FRESH: scenario '", scenario, "' contains '_'; ",
            "SpaDES.experiment::as.data.table.simLists() cuts names at the first '_'.", call. = FALSE)
  list(scenario = as.character(scenario), rep = as.integer(rep))
}

#' TSA basename of each landscape fmuid (the TSA number), e.g. 8 -> "tsa08".
#'
#' Basenames are matched by the number they contain, so zero padding does not matter.
#' @return character, NA where fmuid is NA or matches no basename.
tsaFromFmuid <- function(fmuid, basenames) {
  bn <- unlist(basenames)
  num <- suppressWarnings(as.integer(gsub("\\D", "", bn)))
  bn[match(as.integer(fmuid), num)]
}

#' 10-year age bin, as its lower edge; ages >= top fall in the top bin.
ageBin <- function(age, width = 10L, top = 400L) {
  as.integer(pmin(floor(age / width) * width, top))
}

#' Merchantable volume (m3/ha) of each pixel from its AU's ws3 yield curve at its age.
#'
#' Linear between curve points and held at the ends, as ws3 does; 0 with no AU, curve or age.
#' @param yields Output of loadYieldCurves().
pixelVolume <- function(au, age, yields) {
  vol <- numeric(length(age))
  curve <- unname(yields$auToCurve[as.character(au)])
  ok <- !is.na(curve) & !is.na(age)
  for (cv in unique(curve[ok])) {
    pts <- yields$points[[as.character(cv)]]
    if (is.null(pts) || nrow(pts) == 0) next
    i <- which(ok & curve == cv)
    vol[i] <- stats::approx(pts$x, pts$y, xout = age[i], rule = 2)$y
  }
  vol
}

#' One row per forest pixel (non-NA age) this year: cell, tsa, landBase, au, age, vol_m3ha.
#'
#' @param landscape sim$landscape (layers fmuid, thlb, au, age; categorical layers read by label).
#' @param basenames TSA basenames of the run.
#' @param yields    Output of loadYieldCurves().
pixelFrame <- function(landscape, basenames, yields) {
  age <- layerValues(landscape[["age"]])
  cell <- which(!is.na(age))
  au <- layerValues(landscape[["au"]])[cell]
  thlb <- layerValues(landscape[["thlb"]])[cell]
  data.table::data.table(
    cell     = as.integer(cell),
    tsa      = tsaFromFmuid(layerValues(landscape[["fmuid"]])[cell], basenames),
    landBase = ifelse(!is.na(thlb) & thlb > 0, "THLB", "Non-THLB"),
    au       = au,
    age      = age[cell],
    vol_m3ha = pixelVolume(au, age[cell], yields)
  )
}

#' Prepend the run keys (scenario, rep) and year to a table; tsa, if present, comes after rep.
addKeys <- function(dt, keys, year) {
  dt <- data.table::copy(data.table::as.data.table(dt))
  dt[, `:=`(scenario = keys$scenario, rep = keys$rep, year = as.integer(year))]
  front <- intersect(c("scenario", "rep", "tsa", "year"), names(dt))
  data.table::setcolorder(dt, c(front, setdiff(names(dt), front)))
  dt[]
}

#' outputs() rows that save ws3VerifyTables and ws3VerifyMaps at the end of the run, by basename.
#' @param endTime end(sim) (may carry a unit attribute).
ws3VerifyOutputRows <- function(endTime) {
  data.frame(objectName = c("ws3VerifyTables", "ws3VerifyMaps"),
             file = c("ws3VerifyTables.rds", "ws3VerifyMaps.tif"),
             fun = c("saveRDS", "writeRaster"), package = c("base", "terra"),
             saveTime = rep(as.numeric(endTime), 2), stringsAsFactors = FALSE)
}
