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
    burnedBiomass_gm2 = numeric(0),
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
                             burnedBiomass_gm2,
                             harvestVol_m3 = NA_real_,
                             growingStock_m3 = NA_real_) {
  new_row <- data.table::data.table(
    year              = year,
    harvestArea_ha    = harvestArea_ha,
    burnArea_ha       = burnArea_ha,
    burnedBiomass_gm2 = burnedBiomass_gm2,
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
computeBurnBiomass <- function(rstCurrentBurn, pixelGroupMap, cohortData) {
  burnedIdx <- which(terra::values(rstCurrentBurn) > 0)
  if (length(burnedIdx) == 0) return(0)

  pgVals <- terra::values(pixelGroupMap)[burnedIdx]
  burnedPGs <- data.table::data.table(pixelGroup = pgVals)
  burnedPGs <- burnedPGs[!is.na(pixelGroup)]
  if (nrow(burnedPGs) == 0) return(0)

  joined <- cohortData[burnedPGs, on = "pixelGroup", allow.cartesian = TRUE, nomatch = 0]
  sum(joined$B, na.rm = TRUE)
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
