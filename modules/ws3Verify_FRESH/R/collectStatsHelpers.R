# collectStatsHelpers.R
# Pure helper functions for the collectStats event in ws3Verify_FRESH.
# All functions are side-effect free (no sim access) for easy unit testing.

# ---------------------------------------------------------------------------
# DT initializers
# ---------------------------------------------------------------------------

initAnnualDT <- function() {
  data.table::data.table(
    year              = numeric(0),
    harvestArea_ha    = numeric(0),
    burnArea_ha       = numeric(0),
    burnedVol_m3      = numeric(0),
    burnedBiomass_t   = numeric(0),
    harvestVol_m3     = numeric(0),
    growingStock_m3   = numeric(0)
  )
}

initMissedHarvestDT <- function() {
  data.table::data.table(
    year                  = numeric(0),
    plannedHarvestArea_ha = numeric(0),
    actualHarvestArea_ha  = numeric(0),
    missedDueToFire_ha    = numeric(0)
  )
}

# ---------------------------------------------------------------------------
# Append helpers
# ---------------------------------------------------------------------------

appendAnnualRow <- function(dt, year, harvestArea_ha, burnArea_ha,
                             burnedVol_m3, burnedBiomass_t,
                             harvestVol_m3 = NA_real_,
                             growingStock_m3 = NA_real_) {
  new_row <- data.table::data.table(
    year              = year,
    harvestArea_ha    = harvestArea_ha,
    burnArea_ha       = burnArea_ha,
    burnedVol_m3      = burnedVol_m3,
    burnedBiomass_t   = burnedBiomass_t,
    harvestVol_m3     = harvestVol_m3,
    growingStock_m3   = growingStock_m3
  )
  data.table::rbindlist(list(dt, new_row), use.names = TRUE, fill = TRUE)
}

appendMissedHarvestRow <- function(dt, year, plannedHarvestArea_ha,
                                    actualHarvestArea_ha, missedDueToFire_ha) {
  new_row <- data.table::data.table(
    year                  = year,
    plannedHarvestArea_ha = plannedHarvestArea_ha,
    actualHarvestArea_ha  = actualHarvestArea_ha,
    missedDueToFire_ha    = missedDueToFire_ha
  )
  data.table::rbindlist(list(dt, new_row), use.names = TRUE, fill = TRUE)
}

# ---------------------------------------------------------------------------
# Burn biomass
# ---------------------------------------------------------------------------

#' Compute total biomass of cohorts on pixels that burned this year.
#'
#' @param rstCurrentBurn SpatRaster. Values > 0 indicate burned pixels.
#' @param pixelGroupMap  SpatRaster. Integer pixel group IDs.
#' @param cohortData     data.table with columns: pixelGroup (integer), B (numeric, g/m2).
#' @return Numeric scalar: sum of B across all cohorts in all burned pixel groups.
#' Total biomass (tonnes) of the cohorts in this year's burned pixels.
#'
#' Needs LandR cohortData: one row per pixelGroup x cohort, B in g/m2.
#' spades_ws3_landrAge's placeholder cohortData (one row per pixel, B = 7777) does not
#' qualify; set the module parameter burnedBiomass = FALSE when it is the only source.
#'
#' @param resInHA Numeric. Pixel area in hectares.
computeBurnBiomass <- function(rstCurrentBurn, pixelGroupMap, cohortData, resInHA) {
  burnedIdx <- which(terra::values(rstCurrentBurn) > 0)
  if (length(burnedIdx) == 0) return(0)

  pgVals <- terra::values(pixelGroupMap)[burnedIdx]
  burnedPGs <- data.table::data.table(pixelGroup = pgVals)
  burnedPGs <- burnedPGs[!is.na(pixelGroup)]
  if (nrow(burnedPGs) == 0) return(0)

  joined <- cohortData[burnedPGs, on = "pixelGroup", allow.cartesian = TRUE, nomatch = 0]
  # g/m2 summed over burned pixels x pixel area (m2) / 1e6 g per tonne
  sum(joined$B, na.rm = TRUE) * resInHA * 1e4 / 1e6
}

# ---------------------------------------------------------------------------
# Burned volume (ws3 yield curves)
# ---------------------------------------------------------------------------

#' Read the ws3 yield curves (merchantable volume, m3/ha, by age).
#'
#' Same tables and the same subset of points as spades_ws3's bootstrap_yields():
#' au_table.csv maps each AU (the landscape "au" layer) to its unmanaged curve, and only
#' points at multiples of periodLength up to xMax are used.
#'
#' @param auTablePath,curvePointsPath Paths to au_table.csv and curve_points_table.csv.
#' @return list(auToCurve = named vector au_id -> curve_id, points = list of data.tables (x, y)
#'   named by curve_id).
loadYieldCurves <- function(auTablePath, curvePointsPath, periodLength = 10, xMax = 350) {
  au <- data.table::fread(auTablePath)
  cp <- data.table::fread(curvePointsPath)
  cp <- cp[x %% periodLength == 0 & x <= xMax]
  data.table::setorder(cp, curve_id, x)
  list(
    auToCurve = stats::setNames(au$unmanaged_curve_id, au$au_id),
    points    = split(cp[, .(curve_id, x, y)], by = "curve_id", keep.by = FALSE)
  )
}

#' Cell values of a one-layer SpatRaster; for a categorical layer, its category labels as numbers.
#'
#' spades_ws3_dataInit's landscape layers are categorical, so values() gives category indices
#' (1, 2, ...), not the AU ids. terra::as.numeric() also returns the indices here.
layerValues <- function(r) {
  v <- terra::values(r)[, 1]
  if (terra::is.factor(r)) {
    lv <- terra::cats(r)[[1]]
    labels <- lv[[terra::activeCat(r) + 1]]   # column 1 is ID; activeCat counts from the next one
    v <- as.numeric(as.character(labels[match(v, lv[[1]])]))
  }
  v
}

#' Merchantable volume (m3) standing in this year's burned pixels, before the burn resets ages.
#'
#' Each burned pixel's volume is its AU's yield curve at its age (linear between curve points,
#' held at the ends, as ws3 does) times the pixel area. Pixels with no AU or curve count 0.
#'
#' @param au,age  SpatRasters: the landscape "au" and "age" layers.
#' @param yields  Output of loadYieldCurves().
#' @param resInHA Numeric. Pixel area in hectares.
computeBurnVolume <- function(rstCurrentBurn, au, age, yields, resInHA) {
  burnedIdx <- which(terra::values(rstCurrentBurn) > 0)
  if (length(burnedIdx) == 0) return(0)

  dt <- data.table::data.table(au  = layerValues(au)[burnedIdx],
                               age = layerValues(age)[burnedIdx])
  dt <- dt[!is.na(au) & !is.na(age)]
  dt[, curve := yields$auToCurve[as.character(au)]]
  dt <- dt[!is.na(curve)]
  if (nrow(dt) == 0) return(0)

  dt[, vol := {
    pts <- yields$points[[as.character(curve[1])]]
    if (is.null(pts) || nrow(pts) == 0) 0 else stats::approx(pts$x, pts$y, xout = age, rule = 2)$y
  }, by = curve]
  sum(dt$vol) * resInHA
}

# ---------------------------------------------------------------------------
# Missed harvest
# ---------------------------------------------------------------------------

#' Compute planned harvest area and how much of it burned before harvest.
#'
#' Reads the projected_harvest_<year>.tif written by the spades_ws3 Python layer
#' for each basename and compares it to the current-year burn raster.
#'
#' @param basenames      Character vector of TSA basenames (e.g. c("tsa40","tsa41")).
#' @param tifDir         Path to the tif directory (inputPath(sim)/tif.path).
#'                       Each basename has a subdirectory: tifDir/<basename>/.
#' @param year           Numeric. Simulation year (used to build file name).
#' @param rstCurrentBurn SpatRaster. Values > 0 indicate pixels that burned this year.
#' @param resInHA        Numeric. Pixel area in hectares.
#' @return Named list: planned (ha), missed (ha). Both NA if no tif found.
computeMissedHarvest <- function(basenames, tifDir, year, rstCurrentBurn, resInHA) {
  fname  <- paste0("projected_harvest_", year, ".tif")
  paths  <- file.path(tifDir, basenames, fname)
  exists <- file.exists(paths)

  if (!any(exists)) {
    return(list(planned = NA_real_, missed = NA_real_))
  }

  rasts <- lapply(paths[exists], terra::rast)
  if (length(rasts) == 1) {
    plannedRst <- rasts[[1]]
  } else {
    plannedRst <- do.call(terra::mosaic, rasts)
  }
  terra::values(plannedRst)[is.nan(terra::values(plannedRst))] <- NA
  if (!terra::compareGeom(plannedRst, rstCurrentBurn, stopOnError = FALSE)) {
    plannedRst <- terra::resample(plannedRst, rstCurrentBurn, method = "near")
  }

  plannedPixels <- sum(terra::values(plannedRst) == 1, na.rm = TRUE)
  missedPixels  <- sum(terra::values(plannedRst) == 1 &
                         terra::values(rstCurrentBurn) > 0, na.rm = TRUE)

  list(
    planned = plannedPixels * resInHA,
    missed  = missedPixels  * resInHA
  )
}

# ---------------------------------------------------------------------------
# ForestModel queries (reticulate)
# ---------------------------------------------------------------------------

#' Query harvested volume and growing stock from a ws3 ForestModel for a given period.
#'
#' @param fm     A reticulate Python proxy for a ws3 ForestModel instance.
#'               Requires methods: compile_product(period, expr, acode) and
#'               inventory(period, yname).
#' @param period Integer. ws3 planning period index (1-based).
#'               Compute as: (time(sim) - start(sim)) / planning_period_freq
#' @return Named list: harvestVol (m3, numeric), growingStock (m3, numeric).
queryFmStats <- function(fm, period) {
  period <- as.integer(period)
  harvestVol   <- fm$compile_product(period, 'totvol', acode = 'harvest')
  growingStock <- fm$inventory(period, 'totvol')
  list(
    harvestVol   = as.numeric(harvestVol),
    growingStock = as.numeric(growingStock)
  )
}
