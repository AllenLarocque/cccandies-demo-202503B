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
    "data.table", "ggplot2", "terra", "reticulate", "geodata", "patchwork",
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
                    "Interval between plot events. NA = once only."),
    defineParameter("burnedBiomass", "logical", TRUE, NA, NA,
                    paste("Compute burned biomass (t) from cohortData and plot it. Needs LandR",
                          "cohortData; set FALSE when only spades_ws3_landrAge's placeholder",
                          "cohortData exists (WS3_FRESH), which gives meaningless values.")),
    defineParameter("scenario", "character", "default", NA, NA,
                    paste("Scenario label stamped on every ws3VerifyTables row. Ignored when the run's",
                          "outputPath is a SpaDES.experiment run folder (<scenario>_rep<n>).",
                          "Avoid '_': SpaDES.experiment cuts simList names at the first one.")),
    defineParameter("rep", "integer", 1L, 1L, NA,
                    "Replicate number stamped on every ws3VerifyTables row (overridden as for scenario)."),
    defineParameter("oldForestAges", "numeric", c(140, 250), 0, NA,
                    "Age thresholds (years) for the old-forest figure (B4)."),
    defineParameter("resetAgeMax", "integer", 2L, 0L, NA,
                    paste("Highest age a harvested or burned pixel may have one year after its reset;",
                          "used by the age-accounting checks (V2, V3).")),
    defineParameter("mode", "character", "single", NA, NA,
                    paste("'single': collect tables and plot during a run. 'multi': post-processing only;",
                          "gather saved tables from multiPaths and draw the multi-run figures.")),
    defineParameter("multiPaths", "character", NA_character_, NA, NA,
                    "mode = 'multi': output folders of the runs to gather (searched recursively)."),
    defineParameter("yieldPath", "character", NA_character_, NA, NA,
                    paste("Folder with the ws3 yield tables au_table.csv and",
                          "curve_points_table.csv, used for burned volume. NA = inputPath(sim)."))
  ),
  inputObjects = bindrows(
    expectsInput("harvestTimingStats", "data.table",
                 paste("From spades_ws3 with harvestTiming = 'annual': planned, applied and skipped (reset",
                       "since the plan) pixels per year. Used for missed harvest when present."),
                 sourceURL = NA),
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
                        "burnedVol_m3, burnedBiomass_t (NA if burnedBiomass = FALSE),",
                        "harvestVol_m3 (planning years only: the decade's harvest in the plan just made),",
                        "growingStock_m3 (planning years only: standing volume at the start of that plan).")),
    createsOutput("ws3MissedHarvestDT", "data.table",
                  paste("Annual planned vs actual harvest. Columns: year,",
                        "plannedHarvestArea_ha, actualHarvestArea_ha, missedDueToFire_ha.")),
    createsOutput("ws3VerifyAgeClassDT", "data.table",
                  paste("Annual forested area by age class and land base. Columns: year, landBase",
                        "(\"THLB\" = timber harvesting land base, landscape thlb > 0; \"Non-THLB\"),",
                        "ageClass (0-49, 50-99, 100-199, 200-299, 300+), area_ha.")),
    createsOutput("ws3VerifyTables", "list",
                  paste("Named list of long data.tables, every row keyed by scenario, rep, tsa (TSA basename;",
                        "NA outside ws3's forest) and year (simulation year).",
                        "ageDT: landBase x 10-year ageBin (400 = 400+): area_ha, vol_m3.",
                        "checkDT: landBase: pixels, naAge_n, forest_ha, reset_n, unexplainedAgeChange_n, naChange_n,",
                        "meanAgeChange, expectedMeanAgeChange, burned_n and burnedReset_n (this year's burned forest",
                        "pixels, and those at age 0 after landrAge's reset; filled at endOfYear).",
                        "harvestDT: planned_ws3_ha, applied_ws3_ha, skippedBurned_ws3_ha (spades_ws3's",
                        "harvestTimingStats; NA without it), planned_raster_ha, harvested_landscape_ha,",
                        "plannedNotCut_ha, missedUnexplained_ha, vol_m3, cutVolPlanAge_m3, skippedVolPlanAge_m3",
                        "(planned stands reset since the plan), missedUnexplainedVol_m3, meanAgeAtCut,",
                        "planRuleViolations_n.",
                        "harvestAgeDT: landBase x ageRef ('plan'/'cut') x ageBin: area_ha.",
                        "planDT (planning years): plannedVol_m3, plannedArea_ha, cutArea_ha, cutVolPlanAge_m3,",
                        "skippedVolPlanAge_m3, missedUnexplainedVol_m3, cutVolCutAge_m3 (filled when the period",
                        "ends), periodYears, periodLength.",
                        "fireDT: landBase ('outside forest' too) x pre-fire ageBin: burned_ha, burnedVol_m3.",
                        "fireEventsDT: one row per fire: PolyID, size_ha (tsa of the ignition cell).")),
    createsOutput("ws3VerifyMaps", "SpatRaster",
                  paste("End-of-run maps: burnCount, harvestCount, timeSinceDisturbance (years; NA if never",
                        "disturbed), lastDisturbance (1 = harvest, 2 = fire).")),
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
      if (P(sim)$mode == "multi") {
        # post-processing: no collection; gather saved runs and draw the multi-run figures
        sim <- scheduleEvent(sim, time(sim), "ws3Verify_FRESH", "multiPlots")
        return(invisible(sim))
      }
      sim <- Init(sim)
      # Init adds ws3VerifyTables/ws3VerifyMaps to outputs(), after the core save module's init has
      # scheduled its saves; ask it to save again at the end so they are written too
      sim <- scheduleEvent(sim, end(sim), "save", "later", .last())
      # From the start year, so fires of the first year are counted. eventPriority 8: after scfmSpread "burn" (7.5), so this year's fires are in
      # burnSummary and rstCurrentBurn when stats are collected.
      sim <- scheduleEvent(sim, time(sim), "ws3Verify_FRESH", "collectStats",
                           eventPriority = 8)
      # eventPriority 9.5: after spades_ws3_landrAge adjustBurnedPixels (9) resets this year's burns
      sim <- scheduleEvent(sim, time(sim), "ws3Verify_FRESH", "endOfYear", eventPriority = 9.5)
      plotTime <- if (is.na(P(sim)$.plotInitialTime)) end(sim) else P(sim)$.plotInitialTime
      # eventPriority 8.5: after collectStats (8), so the plots include the last year's row
      sim <- scheduleEvent(sim, plotTime, "ws3Verify_FRESH", "makePlots", eventPriority = 8.5)
    },
    collectStats = {
      sim <- CollectStats(sim)
      if (time(sim) < end(sim)) {
        sim <- scheduleEvent(sim, time(sim) + 1, "ws3Verify_FRESH", "collectStats",
                             eventPriority = 8)
      }
    },
    multiPlots = {
      sim <- MultiPlots(sim)
    },
    endOfYear = {
      sim <- EndOfYear(sim)
      if (time(sim) < end(sim)) {
        sim <- scheduleEvent(sim, time(sim) + 1, "ws3Verify_FRESH", "endOfYear", eventPriority = 9.5)
      }
    },
    makePlots = {
      sim <- MakePlots(sim)
      if (!is.na(P(sim)$.plotInterval)) {
        sim <- scheduleEvent(sim, time(sim) + P(sim)$.plotInterval,
                             "ws3Verify_FRESH", "makePlots", eventPriority = 8.5)
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
  source(file.path(moduleSourceDir(sim), "R", "tablesCore.R"))
  source(file.path(moduleSourceDir(sim), "R", "makePlotsHelpers.R"))

  # Resolve resInHA
  if (is.na(P(sim)$resInHA)) {
    sim$.resInHA <- as.numeric(prod(terra::res(sim$rasterToMatch)) / 1e4)
  } else {
    sim$.resInHA <- P(sim)$resInHA
  }

  # ws3 yield curves, for burned volume
  yieldPath <- if (is.na(P(sim)$yieldPath)) inputPath(sim) else P(sim)$yieldPath
  mod$yields <- loadYieldCurves(file.path(yieldPath, "au_table.csv"),
                                file.path(yieldPath, "curve_points_table.csv"))

  # Snapshot age at start
  sim$ageAtStart <- sim$landscape[["age"]]

  # Initialize output data.tables
  sim$ws3VerifyAnnualDT  <- initAnnualDT()
  sim$ws3MissedHarvestDT <- initMissedHarvestDT()
  sim$ws3VerifyAgeClassDT <- initAgeClassDT()

  # ws3VerifyTables: run state kept in mod, tables in the simList
  mod$initAge    <- layerValues(sim$landscape[["age"]])
  mod$prevAge    <- mod$initAge        # end-of-previous-year age; at the start, the age ws3 starts from
  mod$planAge    <- NULL               # age when the current plan was made
  mod$burnedForest <- NULL             # this year's burned forest cells (cell, tsa, landBase), for V2
  mod$planYear <- start(sim)
  mod$cutThisPeriod <- integer(0)
  nCell <- terra::ncell(sim$landscape)
  mod$burnCount    <- integer(nCell)
  mod$harvestCount <- integer(nCell)
  mod$lastDist     <- rep(NA_integer_, nCell)
  mod$lastDistYear <- rep(NA_integer_, nCell)
  sim$ws3VerifyTables <- list()
  # Saved at end(sim) by SpaDES outputs(), by basename so SpaDES.experiment's outputPath change
  # (after simInit) moves them into each run's folder. outputs<- replaces, so keep earlier rows.
  outputs(sim) <- data.table::rbindlist(list(
    outputs(sim),
    ws3VerifyOutputRows(end(sim))
  ), fill = TRUE)

  # Initialize cumulative harvest map (zeros, matching rasterToMatch)
  sim$cumulativeHarvestMap <- terra::rast(sim$rasterToMatch)
  terra::values(sim$cumulativeHarvestMap) <- 0

  return(invisible(sim))
}

CollectStats <- function(sim) {
  source(file.path(moduleSourceDir(sim), "R", "collectStatsHelpers.R"))
  source(file.path(moduleSourceDir(sim), "R", "tablesCore.R"))

  t         <- time(sim)
  resInHA   <- sim$.resInHA
  basenames <- params(sim)$.globals$basenames
  tifDir    <- file.path(inputPath(sim), params(sim)$.globals$tif.path)

  # 1. Area metrics
  harvestRow     <- tail(sim$harvestStats, 1)
  harvestArea_ha <- if (nrow(harvestRow) > 0) harvestRow$ws3_harvestArea_pixels * resInHA else 0
  burnArea_ha    <- sum(sim$burnSummary[year == t, areaBurned], na.rm = TRUE)

  # 2. Burned volume (ws3 yield curves at the pre-fire ages) and, optionally, biomass
  burnedVol_m3 <- computeBurnVolume(
    rstCurrentBurn = sim$rstCurrentBurn,
    au             = sim$landscape[["au"]],
    age            = sim$landscape[["age"]],
    yields         = mod$yields,
    resInHA        = resInHA
  )
  burnedBiomass_t <- if (isTRUE(P(sim)$burnedBiomass)) {
    computeBurnBiomass(
      rstCurrentBurn = sim$rstCurrentBurn,
      pixelGroupMap  = sim$pixelGroupMap,
      cohortData     = sim$cohortData,
      resInHA        = resInHA
    )
  } else {
    NA_real_
  }

  # 3. Volume + GS on planning years only (including the start year), from the plan just made
  planFreq        <- params(sim)$.globals$planning_period_freq
  harvestVol_m3   <- NA_real_
  growingStock_m3 <- NA_real_
  if ((t - start(sim)) %% planFreq == 0) {
    fmStats         <- queryFmStats(fm = sim$fm)
    harvestVol_m3   <- fmStats$harvestVol
    growingStock_m3 <- fmStats$growingStock
  }

  # 4. Append annual row
  sim$ws3VerifyAnnualDT <- appendAnnualRow(
    dt                = sim$ws3VerifyAnnualDT,
    year              = t,
    harvestArea_ha    = harvestArea_ha,
    burnArea_ha       = burnArea_ha,
    burnedVol_m3      = burnedVol_m3,
    burnedBiomass_t   = burnedBiomass_t,
    harvestVol_m3     = harvestVol_m3,
    growingStock_m3   = growingStock_m3
  )

  # 5. Missed harvest
  # spades_ws3 names its rasters by calendar year, from its own base.year
  baseYear <- params(sim)$spades_ws3$base.year
  if (is.null(baseYear)) baseYear <- params(sim)$.globals$base.year
  missed <- if (!is.null(sim$harvestTimingStats)) {
    # spades_ws3 harvestTiming = "annual" records the planned pixels it skipped because they
    # were reset (burned) since the plan: that is the harvest missed due to fire
    missedFromTimingStats(sim$harvestTimingStats, calendarYear(t, start(sim), baseYear), resInHA)
  } else {
    computeMissedHarvest(
      basenames      = basenames,
      tifDir         = tifDir,
      year           = calendarYear(t, start(sim), baseYear),
      rstCurrentBurn = sim$rstCurrentBurn,
      resInHA        = resInHA
    )
  }
  sim$ws3MissedHarvestDT <- appendMissedHarvestRow(
    dt                    = sim$ws3MissedHarvestDT,
    year                  = t,
    plannedHarvestArea_ha = missed$planned,
    actualHarvestArea_ha  = harvestArea_ha,
    missedDueToFire_ha    = missed$missed
  )

  # 6. Forested area by age class, THLB vs the rest (ages after this year's harvest and burn resets)
  sim$ws3VerifyAgeClassDT <- rbind(
    sim$ws3VerifyAgeClassDT,
    tabulateAgeByLandBase(sim$landscape[["age"]], sim$landscape[["thlb"]], year = t, resInHA = resInHA)
  )

  # 7. ws3VerifyTables
  sim <- CollectTables(sim)

  # 8. Increment cumulative harvest map
  harvestRst <- sim$rstCurrentHarvest
  harvestRst[is.na(terra::values(harvestRst))] <- 0
  sim$cumulativeHarvestMap <- sim$cumulativeHarvestMap + harvestRst

  return(invisible(sim))
}

#' Append this year's rows to every table in sim$ws3VerifyTables, and update the map counters.
CollectTables <- function(sim) {
  for (f in c("tablesCore.R", "tablesAge.R", "tablesHarvest.R", "tablesFire.R"))
    source(file.path(moduleSourceDir(sim), "R", f))
  t         <- time(sim)
  resInHA   <- sim$.resInHA
  basenames <- params(sim)$.globals$basenames
  keys      <- runKeys(outputPath(sim), P(sim)$scenario, P(sim)$rep)
  baseYear  <- params(sim)$spades_ws3$base.year
  if (is.null(baseYear)) baseYear <- params(sim)$.globals$base.year
  yearCal   <- calendarYear(t, start(sim), baseYear)
  planFreq  <- params(sim)$.globals$planning_period_freq
  planningYear <- (t - start(sim)) %% planFreq == 0
  tifDir    <- file.path(inputPath(sim), params(sim)$.globals$tif.path)
  tb        <- sim$ws3VerifyTables
  add <- function(name, dt) tb[[name]] <<- data.table::rbindlist(list(tb[[name]], addKeys(dt, keys, t)),
                                                                  use.names = TRUE, fill = TRUE)

  pf <- pixelFrame(sim$landscape, basenames, mod$yields)
  # the plan made this year (spades_ws3 harvest, priority 5) used the ages at the end of last year
  if (planningYear) {
    mod$planAge <- mod$prevAge
    mod$planYear <- t
    mod$cutThisPeriod <- integer(0)
  }
  cut <- harvestedCells(pf, mod$prevAge, P(sim)$resetAgeMax)
  burned <- which(terra::values(sim$rstCurrentBurn)[, 1] > 0)
  mod$burnedForest <- pf[cell %in% burned, .(cell, tsa, landBase)]

  add("ageDT", tabulateAge(pf, resInHA))
  # in the start year prevAge is the age at Init: spades_ws3 harvests, then grows, in year 0 too
  add("checkDT", checkAges(pf, mod$prevAge, resInHA, P(sim)$resetAgeMax, naAgeCounts(sim$landscape, basenames)))
  planned <- plannedHarvestCells(tifDir, basenames, yearCal, sim$landscape)
  add("harvestDT", tabulateHarvest(pf, cut, mod$planAge, mod$prevAge, planned, sim$harvestTimingStats,
                                   yearCal, resInHA, mod$yields, elapsed = t - mod$planYear,
                                   cutEarlier = mod$cutThisPeriod))
  mod$cutThisPeriod <- c(mod$cutThisPeriod, cut)
  add("harvestAgeDT", tabulateHarvestAge(pf, cut, mod$planAge, mod$prevAge, resInHA))
  add("fireDT", tabulateFire(pf, burned, resInHA))
  cellTsa <- rep(NA_character_, terra::ncell(sim$landscape)); cellTsa[pf$cell] <- pf$tsa
  if (!is.null(sim$burnSummary)) add("fireEventsDT", fireEvents(sim$burnSummary, t, cellTsa))

  # V5: close the previous plan's period when a new plan starts, and the last one at the end
  if (planningYear && !is.null(sim$fm)) {
    if (!is.null(tb$planDT) && nrow(tb$planDT))
      tb$planDT <- closePlanPeriod(tb$planDT, tb$harvestDT, t - planFreq, planFreq)
    add("planDT", planRow(sim$fm, basenames)[, `:=`(periodYears = NA_integer_, periodLength = as.integer(planFreq))])
  }
  if (t == end(sim) && !is.null(tb$planDT) && nrow(tb$planDT)) {
    last <- max(tb$planDT$year)
    tb$planDT <- closePlanPeriod(tb$planDT, tb$harvestDT, last, planFreq)
  }
  if (!is.null(tb$planDT) && nrow(tb$planDT))
    tb$planDT[, periodYears := as.integer(pmin(planFreq, t - year + 1L))]

  # B9 counters (burns of this year are known now; resets happen later at priority 9)
  mod$harvestCount[cut] <- mod$harvestCount[cut] + 1L
  mod$burnCount[burned] <- mod$burnCount[burned] + 1L
  mod$lastDist[cut] <- 1L;    mod$lastDistYear[cut] <- as.integer(t)
  mod$lastDist[burned] <- 2L; mod$lastDistYear[burned] <- as.integer(t)
  if (t == end(sim)) {
    m <- terra::rast(sim$landscape[[1]], nlyrs = 4)
    terra::values(m) <- cbind(mod$burnCount, mod$harvestCount, as.integer(t) - mod$lastDistYear, mod$lastDist)
    names(m) <- c("burnCount", "harvestCount", "timeSinceDisturbance", "lastDisturbance")
    sim$ws3VerifyMaps <- m
  }
  sim$ws3VerifyTables <- tb
  return(invisible(sim))
}

#' mode = "multi": stack the saved tables and maps of the runs under multiPaths and draw both
#' figure sets (V6 included when the runs' scfmDiagnostics summaries are found).
MultiPlots <- function(sim) {
  for (f in c("gather.R", "plotsCore.R", "plotsVerification.R", "plotsBiology.R", "figureSets.R", "makePlotsHelpers.R"))
    source(file.path(moduleSourceDir(sim), "R", f))
  if (all(is.na(P(sim)$multiPaths))) stop("ws3Verify_FRESH: mode = 'multi' needs multiPaths")
  sim$ws3VerifyTables <- gatherWs3VerifyTables(P(sim)$multiPaths)
  maps <- gatherWs3VerifyMaps(P(sim)$multiPaths)
  writeFigureSets(sim$ws3VerifyTables, if (length(maps) == 1) maps[[1]] else if (length(maps)) maps,
                  file.path(outputPath(sim), "figures"), types = P(sim)$.plots,
                  oldForestAges = P(sim)$oldForestAges, byTsa = TRUE)
  return(invisible(sim))
}

#' After this year's burn resets (landrAge, priority 9): snapshot ages for next year's checks.
EndOfYear <- function(sim) {
  source(file.path(moduleSourceDir(sim), "R", "tablesAge.R"))
  mod$prevAge <- layerValues(sim$landscape[["age"]])
  # V2: this year's burned forest cells (taken at collectStats) should now be at age 0
  tb <- sim$ws3VerifyTables
  if (!is.null(tb$checkDT) && !is.null(mod$burnedForest)) {
    t <- as.integer(time(sim))
    fr <- fireResetCounts(mod$burnedForest, mod$prevAge)
    tb$checkDT[year == t, `:=`(burned_n = 0L, burnedReset_n = 0L)]
    if (nrow(fr)) {
      fr[, year := t]
      tb$checkDT[fr, `:=`(burned_n = i.burned_n, burnedReset_n = i.burnedReset_n), on = c("tsa", "landBase", "year")]
    }
    sim$ws3VerifyTables <- tb
  }
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
  SpaDES.core::Plots(data = plotBurnedVolume(annDT),   types = plotTypes,
                     filename = file.path(figDir, "fig_burnedVolume"))
  if (isTRUE(P(sim)$burnedBiomass)) {
    SpaDES.core::Plots(data = plotBurnedBiomass(annDT), types = plotTypes,
                       filename = file.path(figDir, "fig_burnedBiomass"))
  }
  SpaDES.core::Plots(data = plotMissedHarvest(missedDT), types = plotTypes,
                     filename = file.path(figDir, "fig_missedHarvest"))
  if (!is.null(sim$ws3VerifyAgeClassDT) && nrow(sim$ws3VerifyAgeClassDT) > 0) {
    SpaDES.core::Plots(data = plotAgeByLandBase(sim$ws3VerifyAgeClassDT), types = plotTypes,
                       filename = file.path(figDir, "fig_ageByLandBase"))
  }

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

  # Verification (V) and biological (B) figure sets from ws3VerifyTables; V6 (fire regime vs scfm
  # targets) needs scfmDiagnostics' summary, written after this event, so it is drawn in multi mode
  if (!is.null(sim$ws3VerifyTables$ageDT)) {
    for (f in c("plotsCore.R", "plotsVerification.R", "plotsBiology.R", "figureSets.R"))
      source(file.path(moduleSourceDir(sim), "R", f))
    writeFigureSets(sim$ws3VerifyTables, sim$ws3VerifyMaps, figDir, types = plotTypes,
                    oldForestAges = P(sim)$oldForestAges, byTsa = TRUE)
  }

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
