defineModule(sim, list(
  name = "ws3Verify_FRESH",
  description = paste("Verification plots for the ws3+scfm stack.",
                      "Collects annual harvest/fire statistics and generates plots at end(sim)."),
  keywords = c("verification", "diagnostics", "ws3", "scfm"),
  authors = person("Allen", "Larocque"),
  childModules = character(0),
  version = list(ws3Verify_FRESH = "0.0.1"),
  timeframe = as.POSIXlt(c(NA, NA)),
  timeunit = "year",
  citation = list(),
  documentation = list(),
  loadOrder = list(after = c("spades_ws3", "spades_ws3_landrAge", "scfmSpread")),
  reqdPkgs = list(
    "data.table", "ggplot2", "terra", "reticulate", "geodata",
    "PredictiveEcology/SpaDES.core@development (>= 3.0.3.9003)"
  ),
  parameters = bindrows(
    defineParameter(".plots", "character", "png", NA, NA,
                    "Passed to SpaDES.core::Plots(). e.g. c('png','screen')"),
    defineParameter("resInHA", "numeric", NA_real_, NA, NA,
                    "Pixel resolution in hectares. NA = auto-calculate from rasterToMatch."),
    defineParameter(".plotInitialTime", "numeric", NA_real_, NA, NA,
                    "Simulation time for makePlots event. NA = end(sim)."),
    defineParameter(".plotInterval", "numeric", NA_real_, NA, NA,
                    "Interval between plot events. NA = once only.")
  ),
  inputObjects = bindrows(
    expectsInput("harvestStats", "data.frame",
                 "Annual harvest pixel counts. Has columns: ws3_harvestArea_pixels, LandR_harvestArea_pixels, year.",
                 sourceURL = NA),
    expectsInput("rstCurrentHarvest", "SpatRaster",
                 "Current-year harvest raster (1=harvested, NA=not applicable). From spades_ws3_landrAge.",
                 sourceURL = NA),
    expectsInput("rstCurrentBurn", "SpatRaster",
                 "Current-year burn raster (>0 = burned). From scfmSpread.",
                 sourceURL = NA),
    expectsInput("burnSummary", "data.table",
                 "Annual burn summary. Has columns: igLoc, grp, N, year, areaBurned, PolyID.",
                 sourceURL = NA),
    expectsInput("burnMap", "SpatRaster",
                 "Cumulative burn map from scfmSpread.",
                 sourceURL = NA),
    expectsInput("pixelGroupMap", "SpatRaster",
                 "Pixel group IDs. From spades_ws3_landrAge.",
                 sourceURL = NA),
    expectsInput("cohortData", "data.table",
                 "Cohort biomass data. Has columns: pixelGroup (integer), B (numeric, g/m2), and others.",
                 sourceURL = NA),
    expectsInput("landscape", "SpatRaster",
                 "Landscape raster stack with layers: fmuid, thlb, au, blockid, age.",
                 sourceURL = NA),
    expectsInput("studyArea", "sf",
                 "Study area polygon. From spades_ws3_landrAge.",
                 sourceURL = NA),
    expectsInput("rasterToMatch", "SpatRaster",
                 "Template raster for spatial operations. From spades_ws3_landrAge.",
                 sourceURL = NA),
    expectsInput("fm", "ANY",
                 "Python ForestModel object (reticulate proxy). From spades_ws3 via py$fm.",
                 sourceURL = NA)
  ),
  outputObjects = bindrows(
    createsOutput("ws3VerifyAnnualDT", "data.table",
                  paste("Annual time series. Columns: year, harvestArea_ha, burnArea_ha,",
                        "burnedBiomass_gm2, harvestVol_m3 (planning years only),",
                        "growingStock_m3 (planning years only).")),
    createsOutput("ws3MissedHarvestDT", "data.table",
                  paste("Annual planned vs actual harvest. Columns: year,",
                        "plannedHarvestArea_ha, actualHarvestArea_ha, missedDueToFire_ha.")),
    createsOutput("cumulativeHarvestMap", "SpatRaster",
                  "Pixel-level count of harvest events accumulated over the simulation."),
    createsOutput("ageAtStart", "SpatRaster",
                  "Snapshot of landscape$age taken at simulation start.")
  )
))

doEvent.ws3Verify_FRESH <- function(sim, eventTime, eventType) {
  switch(
    eventType,
    init = {
      sim <- Init(sim)
      sim <- scheduleEvent(sim, time(sim) + 1, "ws3Verify_FRESH", "collectStats",
                           eventPriority = 6)
      plotTime <- if (is.na(P(sim)$.plotInitialTime)) end(sim) else P(sim)$.plotInitialTime
      sim <- scheduleEvent(sim, plotTime, "ws3Verify_FRESH", "makePlots")
    },
    collectStats = {
      sim <- CollectStats(sim)
      if (time(sim) < end(sim)) {
        sim <- scheduleEvent(sim, time(sim) + 1, "ws3Verify_FRESH", "collectStats",
                             eventPriority = 6)
      }
    },
    makePlots = {
      sim <- MakePlots(sim)
      if (!is.na(P(sim)$.plotInterval)) {
        sim <- scheduleEvent(sim, time(sim) + P(sim)$.plotInterval,
                             "ws3Verify_FRESH", "makePlots")
      }
    },
    warning(paste("Undefined event type:", current(sim)[1, "eventType", with = FALSE],
                  "in module ws3Verify_FRESH"))
  )
  return(invisible(sim))
}

# ---------------------------------------------------------------------------
# Event functions
# ---------------------------------------------------------------------------

Init <- function(sim) {
  source(file.path(moduleSourceDir(sim), "R", "collectStatsHelpers.R"))
  source(file.path(moduleSourceDir(sim), "R", "makePlotsHelpers.R"))

  # Resolve resInHA
  if (is.na(P(sim)$resInHA)) {
    sim$.resInHA <- as.numeric(prod(terra::res(sim$rasterToMatch)) / 1e4)
  } else {
    sim$.resInHA <- P(sim)$resInHA
  }

  # Snapshot age at start
  sim$ageAtStart <- sim$landscape[["age"]]

  # Initialize output data.tables
  sim$ws3VerifyAnnualDT  <- initAnnualDT()
  sim$ws3MissedHarvestDT <- initMissedHarvestDT()

  # Initialize cumulative harvest map (zeros, matching rasterToMatch)
  sim$cumulativeHarvestMap <- terra::rast(sim$rasterToMatch)
  terra::values(sim$cumulativeHarvestMap) <- 0

  return(invisible(sim))
}

CollectStats <- function(sim) {
  source(file.path(moduleSourceDir(sim), "R", "collectStatsHelpers.R"))

  t         <- time(sim)
  resInHA   <- sim$.resInHA
  basenames <- params(sim)$.globals$basenames
  tifDir    <- file.path(inputPath(sim), params(sim)$.globals$tif.path)

  # 1. Area metrics
  harvestRow     <- tail(sim$harvestStats, 1)
  harvestArea_ha <- if (nrow(harvestRow) > 0) harvestRow$ws3_harvestArea_pixels * resInHA else 0
  burnArea_ha    <- sum(sim$burnSummary[year == t, areaBurned], na.rm = TRUE)

  # 2. Burned biomass
  burnedBiomass_gm2 <- computeBurnBiomass(
    rstCurrentBurn = sim$rstCurrentBurn,
    pixelGroupMap  = sim$pixelGroupMap,
    cohortData     = sim$cohortData
  )

  # 3. Volume + GS on planning years only
  planFreq        <- params(sim)$.globals$planning_period_freq
  harvestVol_m3   <- NA_real_
  growingStock_m3 <- NA_real_
  if ((t - start(sim)) %% planFreq == 0 && t > start(sim)) {
    period          <- as.integer((t - start(sim)) / planFreq)
    fmStats         <- queryFmStats(fm = sim$fm, period = period)
    harvestVol_m3   <- fmStats$harvestVol
    growingStock_m3 <- fmStats$growingStock
  }

  # 4. Append annual row
  sim$ws3VerifyAnnualDT <- appendAnnualRow(
    dt                = sim$ws3VerifyAnnualDT,
    year              = t,
    harvestArea_ha    = harvestArea_ha,
    burnArea_ha       = burnArea_ha,
    burnedBiomass_gm2 = burnedBiomass_gm2,
    harvestVol_m3     = harvestVol_m3,
    growingStock_m3   = growingStock_m3
  )

  # 5. Missed harvest
  missed <- computeMissedHarvest(
    basenames      = basenames,
    tifDir         = tifDir,
    year           = t,
    rstCurrentBurn = sim$rstCurrentBurn,
    resInHA        = resInHA
  )
  sim$ws3MissedHarvestDT <- appendMissedHarvestRow(
    dt                    = sim$ws3MissedHarvestDT,
    year                  = t,
    plannedHarvestArea_ha = missed$planned,
    actualHarvestArea_ha  = harvestArea_ha,
    missedDueToFire_ha    = missed$missed
  )

  # 6. Increment cumulative harvest map
  harvestRst <- sim$rstCurrentHarvest
  harvestRst[is.na(terra::values(harvestRst))] <- 0
  sim$cumulativeHarvestMap <- sim$cumulativeHarvestMap + harvestRst

  return(invisible(sim))
}

MakePlots <- function(sim) {
  source(file.path(moduleSourceDir(sim), "R", "makePlotsHelpers.R"))

  outPath   <- outputPath(sim)
  plotTypes <- P(sim)$.plots
  annDT     <- sim$ws3VerifyAnnualDT
  missedDT  <- sim$ws3MissedHarvestDT

  figDir <- file.path(outPath, "figures")
  dir.create(figDir, showWarnings = FALSE, recursive = TRUE)

  # Time series figures
  SpaDES.core::Plots(data = plotHarvestArea(annDT),    types = plotTypes,
                     filename = file.path(figDir, "fig_harvestArea"))
  SpaDES.core::Plots(data = plotBurnArea(annDT),       types = plotTypes,
                     filename = file.path(figDir, "fig_burnArea"))
  SpaDES.core::Plots(data = plotHarvestVol(annDT),     types = plotTypes,
                     filename = file.path(figDir, "fig_harvestVol"))
  SpaDES.core::Plots(data = plotGrowingStock(annDT),   types = plotTypes,
                     filename = file.path(figDir, "fig_growingStock"))
  SpaDES.core::Plots(data = plotBurnedBiomass(annDT),  types = plotTypes,
                     filename = file.path(figDir, "fig_burnedBiomass"))
  SpaDES.core::Plots(data = plotMissedHarvest(missedDT), types = plotTypes,
                     filename = file.path(figDir, "fig_missedHarvest"))

  # Maps
  mapDir <- file.path(figDir, "maps")
  dir.create(mapDir, showWarnings = FALSE, recursive = TRUE)

  saveMap(fn = function() mapAge(sim$ageAtStart, "Stand age at simulation start (years)"),
          path = file.path(mapDir, "map_ageStart"), types = plotTypes)
  saveMap(fn = function() mapAge(sim$landscape[["age"]], "Stand age at simulation end (years)"),
          path = file.path(mapDir, "map_ageEnd"), types = plotTypes)
  saveMap(fn = function() mapCumulativeBurn(sim$burnMap),
          path = file.path(mapDir, "map_cumulativeBurn"), types = plotTypes)
  saveMap(fn = function() mapCumulativeHarvest(sim$cumulativeHarvestMap),
          path = file.path(mapDir, "map_cumulativeHarvest"), types = plotTypes)
  saveMap(fn = function() mapStudyArea(sim$landscape),
          path = file.path(mapDir, "map_studyArea"), types = plotTypes)
  saveMap(fn = function() mapStudyAreaContext(sim$studyArea),
          path = file.path(mapDir, "map_studyAreaContext"), types = plotTypes)

  return(invisible(sim))
}

# ---------------------------------------------------------------------------
# Helper: module source directory
# ---------------------------------------------------------------------------

#' Return the directory containing this module's source files.
#' Works whether called from within a SpaDES sim or sourced directly.
moduleSourceDir <- function(sim) {
  file.path(modulePath(sim)[[1]], "ws3Verify_FRESH")
}
