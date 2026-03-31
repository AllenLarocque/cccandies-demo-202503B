# ws3Verify_FRESH Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a SpaDES module (`ws3Verify_FRESH`) that collects annual harvest/fire statistics during a simulation and generates a standard suite of verification plots at end(sim).

**Architecture:** A two-event module — `collectStats` fires every year (priority 6) accumulating three simList data.tables and a cumulative harvest raster; `makePlots` fires once at `end(sim)` generating 6 time-series figures and 6 maps. All computational logic lives in pure helper functions (`R/collectStatsHelpers.R`, `R/makePlotsHelpers.R`) that are unit-testable without SpaDES.

**Tech Stack:** R, SpaDES.core, data.table, ggplot2, terra, reticulate (for Python ForestModel queries)

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `modules/ws3Verify_FRESH/ws3Verify_FRESH.R` | Create | Module definition, doEvent, Init/CollectStats/MakePlots event functions |
| `modules/ws3Verify_FRESH/R/collectStatsHelpers.R` | Create | Pure helper functions: DT init, burn biomass join, missed harvest, fm query |
| `modules/ws3Verify_FRESH/R/makePlotsHelpers.R` | Create | Pure helper functions: 6 time-series plot functions, 6 map functions |
| `modules/ws3Verify_FRESH/tests/testthat/test-collectStatsHelpers.R` | Create | Unit tests for collect helpers |
| `modules/ws3Verify_FRESH/tests/testthat/test-makePlotsHelpers.R` | Create | Unit tests for plot helpers |
| `global.R` | Modify | Add ws3Verify_FRESH to modules list and params |

---

## Task 1: Module scaffold

**Files:**
- Create: `modules/ws3Verify_FRESH/ws3Verify_FRESH.R`

- [ ] **Step 1: Create the module directory**

```bash
mkdir -p modules/ws3Verify_FRESH/R
mkdir -p modules/ws3Verify_FRESH/tests/testthat
```

- [ ] **Step 2: Create `modules/ws3Verify_FRESH/ws3Verify_FRESH.R`**

```r
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
    "data.table", "ggplot2", "terra", "reticulate",
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
                 "Cohort biomass data. Has columns: pixelGroup, B (biomass g/m2), and others.",
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
  # Source helpers (SpaDES loads files in R/ automatically, but sourcing explicitly
  # makes them available in the module environment)
  source(file.path(moduleSourceDir(), "R", "collectStatsHelpers.R"), local = TRUE)
  source(file.path(moduleSourceDir(), "R", "makePlotsHelpers.R"), local = TRUE)

  # Resolve resInHA
  if (is.na(P(sim)$resInHA)) {
    sim$.resInHA <- as.numeric(prod(terra::res(sim$rasterToMatch)) / 1e4)
  } else {
    sim$.resInHA <- P(sim)$resInHA
  }

  # Snapshot age at start
  sim$ageAtStart <- sim$landscape[["age"]]

  # Initialize output data.tables
  sim$ws3VerifyAnnualDT   <- initAnnualDT()
  sim$ws3MissedHarvestDT  <- initMissedHarvestDT()

  # Initialize cumulative harvest map (zeros, matching rasterToMatch extent/res)
  sim$cumulativeHarvestMap <- terra::rast(sim$rasterToMatch)
  terra::values(sim$cumulativeHarvestMap) <- 0

  return(invisible(sim))
}

CollectStats <- function(sim) {
  source(file.path(moduleSourceDir(), "R", "collectStatsHelpers.R"), local = TRUE)

  t        <- time(sim)
  resInHA  <- sim$.resInHA
  basenames <- params(sim)$.globals$basenames
  tifDir   <- file.path(inputPath(sim), params(sim)$.globals$tif.path)

  # 1. Area metrics from harvestStats and burnSummary
  harvestRow <- tail(sim$harvestStats, 1)
  harvestArea_ha <- harvestRow$ws3_harvestArea_pixels * resInHA
  burnArea_ha    <- sum(sim$burnSummary[year == t, areaBurned], na.rm = TRUE)

  # 2. Burned biomass: burned pixels -> cohortData join -> sum(B)
  burnedBiomass_gm2 <- computeBurnBiomass(
    rstCurrentBurn = sim$rstCurrentBurn,
    pixelGroupMap  = sim$pixelGroupMap,
    cohortData     = sim$cohortData
  )

  # 3. Volume + growing stock: only on planning years
  planFreq <- params(sim)$.globals$planning_period_freq
  harvestVol_m3   <- NA_real_
  growingStock_m3 <- NA_real_
  if ((t - start(sim)) %% planFreq == 0 && t > start(sim)) {
    period <- as.integer((t - start(sim)) / planFreq)
    fmStats <- queryFmStats(fm = sim$fm, period = period)
    harvestVol_m3   <- fmStats$harvestVol
    growingStock_m3 <- fmStats$growingStock
  }

  # 4. Append to ws3VerifyAnnualDT
  sim$ws3VerifyAnnualDT <- appendAnnualRow(
    dt               = sim$ws3VerifyAnnualDT,
    year             = t,
    harvestArea_ha   = harvestArea_ha,
    burnArea_ha      = burnArea_ha,
    burnedBiomass_gm2 = burnedBiomass_gm2,
    harvestVol_m3    = harvestVol_m3,
    growingStock_m3  = growingStock_m3
  )

  # 5. Missed harvest: planned tif vs rstCurrentBurn
  missed <- computeMissedHarvest(
    basenames      = basenames,
    tifDir         = tifDir,
    year           = t,
    rstCurrentBurn = sim$rstCurrentBurn,
    resInHA        = resInHA
  )
  sim$ws3MissedHarvestDT <- appendMissedHarvestRow(
    dt                   = sim$ws3MissedHarvestDT,
    year                 = t,
    plannedHarvestArea_ha = missed$planned,
    actualHarvestArea_ha  = harvestArea_ha,
    missedDueToFire_ha    = missed$missed
  )

  # 6. Increment cumulative harvest map
  harvestRst <- sim$rstCurrentHarvest
  harvestRst[is.na(harvestRst)] <- 0
  sim$cumulativeHarvestMap <- sim$cumulativeHarvestMap + harvestRst

  return(invisible(sim))
}

MakePlots <- function(sim) {
  source(file.path(moduleSourceDir(), "R", "makePlotsHelpers.R"), local = TRUE)

  outPath <- outputPath(sim)
  plotTypes <- P(sim)$.plots
  annDT    <- sim$ws3VerifyAnnualDT
  missedDT <- sim$ws3MissedHarvestDT

  # Time series figures
  SpaDES.core::Plots(data = plotHarvestArea(annDT),  types = plotTypes,
                     filename = file.path(outPath, "figures", "fig_harvestArea"))
  SpaDES.core::Plots(data = plotBurnArea(annDT),     types = plotTypes,
                     filename = file.path(outPath, "figures", "fig_burnArea"))
  SpaDES.core::Plots(data = plotHarvestVol(annDT),   types = plotTypes,
                     filename = file.path(outPath, "figures", "fig_harvestVol"))
  SpaDES.core::Plots(data = plotGrowingStock(annDT), types = plotTypes,
                     filename = file.path(outPath, "figures", "fig_growingStock"))
  SpaDES.core::Plots(data = plotBurnedBiomass(annDT), types = plotTypes,
                     filename = file.path(outPath, "figures", "fig_burnedBiomass"))
  SpaDES.core::Plots(data = plotMissedHarvest(missedDT), types = plotTypes,
                     filename = file.path(outPath, "figures", "fig_missedHarvest"))

  # Maps
  mapDir <- file.path(outPath, "figures", "maps")
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

# Helper: returns the directory containing this module's source files
moduleSourceDir <- function() {
  # In SpaDES, the module R files live in the module directory
  # This works whether the module is loaded from disk or sourced directly
  if (exists("sim", envir = parent.frame(2))) {
    modulePath(parent.frame(2)$sim)[[1]] |>
      file.path("ws3Verify_FRESH")
  } else {
    dirname(sys.frame(1)$ofile)
  }
}
```

- [ ] **Step 3: Commit scaffold**

```bash
git add modules/ws3Verify_FRESH/ws3Verify_FRESH.R
git commit -m "feat: add ws3Verify_FRESH module scaffold (defineModule + doEvent)"
```

---

## Task 2: collectStats helpers — DT init + area metrics + cumulative harvest map

**Files:**
- Create: `modules/ws3Verify_FRESH/R/collectStatsHelpers.R`
- Create: `modules/ws3Verify_FRESH/tests/testthat/test-collectStatsHelpers.R`

- [ ] **Step 1: Write failing tests**

Create `modules/ws3Verify_FRESH/tests/testthat/test-collectStatsHelpers.R`:

```r
library(testthat)
library(data.table)
library(terra)

source(file.path(dirname(dirname(dirname(getwd()))),
                 "modules", "ws3Verify_FRESH", "R", "collectStatsHelpers.R"))
# Alternative: source relative to this file's location
# source(file.path(dirname(dirname(rstudioapi::getActiveDocumentContext()$path)),
#                  "R", "collectStatsHelpers.R"))

test_that("initAnnualDT returns empty data.table with correct columns", {
  dt <- initAnnualDT()
  expect_s3_class(dt, "data.table")
  expect_equal(nrow(dt), 0)
  expect_named(dt, c("year", "harvestArea_ha", "burnArea_ha",
                      "burnedBiomass_gm2", "harvestVol_m3", "growingStock_m3"))
})

test_that("initMissedHarvestDT returns empty data.table with correct columns", {
  dt <- initMissedHarvestDT()
  expect_s3_class(dt, "data.table")
  expect_equal(nrow(dt), 0)
  expect_named(dt, c("year", "plannedHarvestArea_ha", "actualHarvestArea_ha",
                      "missedDueToFire_ha"))
})

test_that("appendAnnualRow adds a row with correct values and NA defaults for volume", {
  dt <- initAnnualDT()
  dt <- appendAnnualRow(dt, year = 5, harvestArea_ha = 200, burnArea_ha = 100,
                         burnedBiomass_gm2 = 5000)
  expect_equal(nrow(dt), 1)
  expect_equal(dt$year, 5)
  expect_equal(dt$harvestArea_ha, 200)
  expect_equal(dt$burnArea_ha, 100)
  expect_equal(dt$burnedBiomass_gm2, 5000)
  expect_true(is.na(dt$harvestVol_m3))
  expect_true(is.na(dt$growingStock_m3))
})

test_that("appendAnnualRow stores volume and GS when provided", {
  dt <- initAnnualDT()
  dt <- appendAnnualRow(dt, year = 10, harvestArea_ha = 300, burnArea_ha = 50,
                         burnedBiomass_gm2 = 2000,
                         harvestVol_m3 = 15000, growingStock_m3 = 500000)
  expect_equal(dt$harvestVol_m3, 15000)
  expect_equal(dt$growingStock_m3, 500000)
})

test_that("appendMissedHarvestRow adds a row with correct values", {
  dt <- initMissedHarvestDT()
  dt <- appendMissedHarvestRow(dt, year = 3, plannedHarvestArea_ha = 500,
                                actualHarvestArea_ha = 420, missedDueToFire_ha = 80)
  expect_equal(nrow(dt), 1)
  expect_equal(dt$missedDueToFire_ha, 80)
})
```

- [ ] **Step 2: Run tests — expect failure (functions not defined)**

```bash
Rscript -e "testthat::test_file('modules/ws3Verify_FRESH/tests/testthat/test-collectStatsHelpers.R')"
```

Expected output: errors about `initAnnualDT`, `initMissedHarvestDT` not found.

- [ ] **Step 3: Implement DT init and append helpers in `R/collectStatsHelpers.R`**

Create `modules/ws3Verify_FRESH/R/collectStatsHelpers.R`:

```r
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
```

- [ ] **Step 4: Run tests — expect pass**

```bash
Rscript -e "testthat::test_file('modules/ws3Verify_FRESH/tests/testthat/test-collectStatsHelpers.R')"
```

Expected: all 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add modules/ws3Verify_FRESH/R/collectStatsHelpers.R \
        modules/ws3Verify_FRESH/tests/testthat/test-collectStatsHelpers.R
git commit -m "feat: add collectStatsHelpers DT init and append functions with tests"
```

---

## Task 3: collectStats helpers — burn biomass

**Files:**
- Modify: `modules/ws3Verify_FRESH/R/collectStatsHelpers.R`
- Modify: `modules/ws3Verify_FRESH/tests/testthat/test-collectStatsHelpers.R`

- [ ] **Step 1: Add failing tests**

Append to `test-collectStatsHelpers.R`:

```r
test_that("computeBurnBiomass returns 0 when nothing burned", {
  rstCurrentBurn <- terra::rast(nrows = 3, ncols = 3, vals = 0)
  pixelGroupMap  <- terra::rast(nrows = 3, ncols = 3, vals = 1:9)
  cohortData <- data.table::data.table(pixelGroup = 1:9, B = rep(100, 9))

  result <- computeBurnBiomass(rstCurrentBurn, pixelGroupMap, cohortData)
  expect_equal(result, 0)
})

test_that("computeBurnBiomass sums B for all burned pixel groups", {
  # 3x3 raster, pixels 1 and 4 (indices) burned
  rstCurrentBurn <- terra::rast(nrows = 3, ncols = 3,
                                 vals = c(1, 0, 0, 1, 0, 0, 0, 0, 0))
  pixelGroupMap  <- terra::rast(nrows = 3, ncols = 3, vals = 1:9)
  cohortData <- data.table::data.table(pixelGroup = 1:9, B = rep(100, 9))

  result <- computeBurnBiomass(rstCurrentBurn, pixelGroupMap, cohortData)
  expect_equal(result, 200)  # pixels 1 and 4, each B=100
})

test_that("computeBurnBiomass handles multiple cohorts per pixel group", {
  rstCurrentBurn <- terra::rast(nrows = 2, ncols = 2, vals = c(1, 0, 0, 0))
  pixelGroupMap  <- terra::rast(nrows = 2, ncols = 2, vals = c(1, 2, 3, 4))
  # pixel group 1 has 2 cohorts
  cohortData <- data.table::data.table(pixelGroup = c(1, 1, 2, 3, 4),
                                        B = c(50, 75, 100, 100, 100))

  result <- computeBurnBiomass(rstCurrentBurn, pixelGroupMap, cohortData)
  expect_equal(result, 125)  # 50 + 75 for the two cohorts in pixel group 1
})

test_that("computeBurnBiomass ignores NA pixels in pixelGroupMap", {
  rstCurrentBurn <- terra::rast(nrows = 2, ncols = 2, vals = c(1, 1, 0, 0))
  pgVals <- c(1, NA, 3, 4)
  pixelGroupMap  <- terra::rast(nrows = 2, ncols = 2, vals = pgVals)
  cohortData <- data.table::data.table(pixelGroup = c(1, 3, 4), B = c(100, 100, 100))

  result <- computeBurnBiomass(rstCurrentBurn, pixelGroupMap, cohortData)
  expect_equal(result, 100)  # only pixel group 1 (not NA pixel group)
})
```

- [ ] **Step 2: Run tests — expect failure on new tests only**

```bash
Rscript -e "testthat::test_file('modules/ws3Verify_FRESH/tests/testthat/test-collectStatsHelpers.R')"
```

Expected: 5 previous tests pass, 4 new tests fail with "could not find function computeBurnBiomass".

- [ ] **Step 3: Implement `computeBurnBiomass` in `R/collectStatsHelpers.R`**

Append to `modules/ws3Verify_FRESH/R/collectStatsHelpers.R`:

```r
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
```

- [ ] **Step 4: Run tests — expect all pass**

```bash
Rscript -e "testthat::test_file('modules/ws3Verify_FRESH/tests/testthat/test-collectStatsHelpers.R')"
```

Expected: all 9 tests pass.

- [ ] **Step 5: Commit**

```bash
git add modules/ws3Verify_FRESH/R/collectStatsHelpers.R \
        modules/ws3Verify_FRESH/tests/testthat/test-collectStatsHelpers.R
git commit -m "feat: add computeBurnBiomass helper with tests"
```

---

## Task 4: collectStats helpers — missed harvest

**Files:**
- Modify: `modules/ws3Verify_FRESH/R/collectStatsHelpers.R`
- Modify: `modules/ws3Verify_FRESH/tests/testthat/test-collectStatsHelpers.R`

- [ ] **Step 1: Add failing tests**

Append to `test-collectStatsHelpers.R`:

```r
test_that("computeMissedHarvest returns NA when no tif exists for that year", {
  result <- computeMissedHarvest(
    basenames      = "tsa_nonexistent",
    tifDir         = tempdir(),
    year           = 9999,
    rstCurrentBurn = terra::rast(nrows = 2, ncols = 2, vals = 0),
    resInHA        = 1
  )
  expect_true(is.na(result$planned))
  expect_true(is.na(result$missed))
})

test_that("computeMissedHarvest counts planned pixels and overlap with burn", {
  tmp <- tempdir()
  bn  <- "testTSA_missed"
  dir.create(file.path(tmp, bn), showWarnings = FALSE)

  # Write planned harvest raster: pixels 1 and 2 planned (out of 4)
  plannedVals <- c(1, 1, 0, 0)
  plannedRst  <- terra::rast(nrows = 2, ncols = 2, vals = plannedVals)
  terra::writeRaster(plannedRst,
                     file.path(tmp, bn, "projected_harvest_5.tif"),
                     overwrite = TRUE)

  # Burn raster: pixel 1 burned
  burnRst <- terra::rast(nrows = 2, ncols = 2, vals = c(1, 0, 0, 0))

  result <- computeMissedHarvest(
    basenames      = bn,
    tifDir         = tmp,
    year           = 5,
    rstCurrentBurn = burnRst,
    resInHA        = 1
  )
  expect_equal(result$planned, 2)   # 2 planned pixels × 1 ha/pixel
  expect_equal(result$missed,  1)   # 1 pixel was both planned and burned
})

test_that("computeMissedHarvest mosaics multiple basenames", {
  tmp <- tempdir()
  for (bn in c("tsaA_missed", "tsaB_missed")) {
    dir.create(file.path(tmp, bn), showWarnings = FALSE)
    r <- terra::rast(nrows = 2, ncols = 2, vals = c(1, 0, 0, 0))
    terra::writeRaster(r, file.path(tmp, bn, "projected_harvest_10.tif"),
                       overwrite = TRUE)
  }
  burnRst <- terra::rast(nrows = 2, ncols = 2, vals = 0)

  result <- computeMissedHarvest(
    basenames      = c("tsaA_missed", "tsaB_missed"),
    tifDir         = tmp,
    year           = 10,
    rstCurrentBurn = burnRst,
    resInHA        = 1
  )
  # Each basename contributes 1 planned pixel; mosaic merges them
  # Since both rasters have same extent and pixel 1 = 1, mosaic gives 1 planned pixel
  expect_gte(result$planned, 1)
  expect_equal(result$missed, 0)
})
```

- [ ] **Step 2: Run tests — expect failure on new tests only**

```bash
Rscript -e "testthat::test_file('modules/ws3Verify_FRESH/tests/testthat/test-collectStatsHelpers.R')"
```

Expected: 9 previous pass, 3 new fail with "could not find function computeMissedHarvest".

- [ ] **Step 3: Implement `computeMissedHarvest` in `R/collectStatsHelpers.R`**

Append to `modules/ws3Verify_FRESH/R/collectStatsHelpers.R`:

```r
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
  plannedRst[is.nan(terra::values(plannedRst))] <- NA

  plannedPixels <- sum(terra::values(plannedRst) == 1, na.rm = TRUE)
  missedPixels  <- sum(terra::values(plannedRst) == 1 &
                         terra::values(rstCurrentBurn) > 0, na.rm = TRUE)

  list(
    planned = plannedPixels * resInHA,
    missed  = missedPixels  * resInHA
  )
}
```

- [ ] **Step 4: Run tests — expect all pass**

```bash
Rscript -e "testthat::test_file('modules/ws3Verify_FRESH/tests/testthat/test-collectStatsHelpers.R')"
```

Expected: all 12 tests pass.

- [ ] **Step 5: Commit**

```bash
git add modules/ws3Verify_FRESH/R/collectStatsHelpers.R \
        modules/ws3Verify_FRESH/tests/testthat/test-collectStatsHelpers.R
git commit -m "feat: add computeMissedHarvest helper with tests"
```

---

## Task 5: collectStats helpers — ForestModel query (volume + growing stock)

**Files:**
- Modify: `modules/ws3Verify_FRESH/R/collectStatsHelpers.R`

> **Note:** `queryFmStats` wraps reticulate calls to a Python ForestModel. Unit tests require Python + ws3 installed, so only a smoke-test placeholder is written; the real verification is Task 8 (integration run).

- [ ] **Step 1: Implement `queryFmStats` in `R/collectStatsHelpers.R`**

Append to `modules/ws3Verify_FRESH/R/collectStatsHelpers.R`:

```r
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
```

- [ ] **Step 2: Add a skipped integration test as documentation**

Append to `test-collectStatsHelpers.R`:

```r
test_that("queryFmStats returns numeric harvestVol and growingStock (integration, skipped)", {
  skip("Integration test: requires Python + ws3. Run manually with a live sim.")
  # Manual verification: after running global.R, call:
  #   reticulate::py_run_string("import ws3")
  #   stats <- queryFmStats(fm = py$fm, period = 1L)
  #   stopifnot(is.numeric(stats$harvestVol), is.numeric(stats$growingStock))
  #   cat("harvestVol:", stats$harvestVol, "growingStock:", stats$growingStock, "\n")
})
```

- [ ] **Step 3: Run tests — expect all pass (skipped test counts as pass)**

```bash
Rscript -e "testthat::test_file('modules/ws3Verify_FRESH/tests/testthat/test-collectStatsHelpers.R')"
```

Expected: 12 pass, 1 skip.

- [ ] **Step 4: Commit**

```bash
git add modules/ws3Verify_FRESH/R/collectStatsHelpers.R \
        modules/ws3Verify_FRESH/tests/testthat/test-collectStatsHelpers.R
git commit -m "feat: add queryFmStats helper for ForestModel volume/GS queries"
```

---

## Task 6: makePlots helpers — time series figures

**Files:**
- Create: `modules/ws3Verify_FRESH/R/makePlotsHelpers.R`
- Create: `modules/ws3Verify_FRESH/tests/testthat/test-makePlotsHelpers.R`

- [ ] **Step 1: Write failing tests**

Create `modules/ws3Verify_FRESH/tests/testthat/test-makePlotsHelpers.R`:

```r
library(testthat)
library(data.table)
library(ggplot2)

source(file.path(dirname(dirname(dirname(getwd()))),
                 "modules", "ws3Verify_FRESH", "R", "makePlotsHelpers.R"))

# Shared test data
annDT <- data.table(
  year              = 1:10,
  harvestArea_ha    = seq(100, 1000, 100),
  burnArea_ha       = seq(50, 500, 50),
  burnedBiomass_gm2 = seq(1000, 10000, 1000),
  harvestVol_m3     = c(NA, NA, NA, NA, NA, 50000, NA, NA, NA, 100000),
  growingStock_m3   = c(NA, NA, NA, NA, NA, 5e5, NA, NA, NA, 4.5e5)
)

missedDT <- data.table(
  year                  = 1:10,
  plannedHarvestArea_ha = seq(500, 1400, 100),
  actualHarvestArea_ha  = seq(100, 1000, 100),
  missedDueToFire_ha    = seq(400, 400, 0)
)

test_that("plotHarvestArea returns a ggplot", {
  p <- plotHarvestArea(annDT)
  expect_s3_class(p, "ggplot")
})

test_that("plotBurnArea returns a ggplot", {
  p <- plotBurnArea(annDT)
  expect_s3_class(p, "ggplot")
})

test_that("plotHarvestVol returns a ggplot and drops NA rows", {
  p <- plotHarvestVol(annDT)
  expect_s3_class(p, "ggplot")
  # Data used should have only 2 non-NA rows
  expect_equal(nrow(p$data), 2)
})

test_that("plotGrowingStock returns a ggplot and drops NA rows", {
  p <- plotGrowingStock(annDT)
  expect_s3_class(p, "ggplot")
  expect_equal(nrow(p$data), 2)
})

test_that("plotBurnedBiomass returns a ggplot", {
  p <- plotBurnedBiomass(annDT)
  expect_s3_class(p, "ggplot")
})

test_that("plotMissedHarvest returns a ggplot with two fill levels", {
  p <- plotMissedHarvest(missedDT)
  expect_s3_class(p, "ggplot")
  expect_equal(nlevels(p$data$outcome), 2)
})
```

- [ ] **Step 2: Run tests — expect failure**

```bash
Rscript -e "testthat::test_file('modules/ws3Verify_FRESH/tests/testthat/test-makePlotsHelpers.R')"
```

Expected: all 6 fail with "could not find function".

- [ ] **Step 3: Implement time series plot functions in `R/makePlotsHelpers.R`**

Create `modules/ws3Verify_FRESH/R/makePlotsHelpers.R`:

```r
# makePlotsHelpers.R
# Pure helper functions for MakePlots event in ws3Verify_FRESH.

# ---------------------------------------------------------------------------
# Time series figures
# ---------------------------------------------------------------------------

plotHarvestArea <- function(dt) {
  ggplot2::ggplot(dt, ggplot2::aes(x = year, y = harvestArea_ha)) +
    ggplot2::geom_line(colour = "darkgreen", linewidth = 1) +
    ggplot2::labs(x = "Year", y = "Harvested area (ha)",
                  title = "Annual harvested area")
}

plotBurnArea <- function(dt) {
  ggplot2::ggplot(dt, ggplot2::aes(x = year, y = burnArea_ha)) +
    ggplot2::geom_line(colour = "firebrick", linewidth = 1) +
    ggplot2::labs(x = "Year", y = "Burned area (ha)",
                  title = "Annual burned area")
}

plotHarvestVol <- function(dt) {
  dtPlan <- dt[!is.na(harvestVol_m3)]
  ggplot2::ggplot(dtPlan, ggplot2::aes(x = year, y = harvestVol_m3)) +
    ggplot2::geom_col(fill = "darkgreen") +
    ggplot2::labs(x = "Year (planning periods only)", y = "Harvested volume (m3)",
                  title = "Harvested volume by planning period")
}

plotGrowingStock <- function(dt) {
  dtPlan <- dt[!is.na(growingStock_m3)]
  ggplot2::ggplot(dtPlan, ggplot2::aes(x = year, y = growingStock_m3)) +
    ggplot2::geom_line(colour = "steelblue", linewidth = 1) +
    ggplot2::geom_point(colour = "steelblue", size = 2) +
    ggplot2::labs(x = "Year (planning periods only)", y = "Growing stock (m3)",
                  title = "Growing stock over time")
}

plotBurnedBiomass <- function(dt) {
  ggplot2::ggplot(dt, ggplot2::aes(x = year, y = burnedBiomass_gm2)) +
    ggplot2::geom_line(colour = "orange", linewidth = 1) +
    ggplot2::labs(x = "Year", y = "Burned biomass (g/m2)",
                  title = "Annual burned biomass (proxy for burned volume)")
}

plotMissedHarvest <- function(dt) {
  dtMelt <- data.table::melt(
    dt[, .(year, actualHarvestArea_ha, missedDueToFire_ha)],
    id.vars      = "year",
    variable.name = "outcome",
    value.name   = "area_ha"
  )
  dtMelt[, outcome := factor(outcome,
                              levels = c("actualHarvestArea_ha", "missedDueToFire_ha"),
                              labels = c("Harvested", "Missed (burned)"))]
  ggplot2::ggplot(dtMelt, ggplot2::aes(x = year, y = area_ha, fill = outcome)) +
    ggplot2::geom_col() +
    ggplot2::scale_fill_manual(values = c("Harvested" = "darkgreen",
                                          "Missed (burned)" = "firebrick")) +
    ggplot2::labs(x = "Year", y = "Area (ha)", fill = NULL,
                  title = "Planned harvest: harvested vs missed due to fire")
}
```

- [ ] **Step 4: Run tests — expect all pass**

```bash
Rscript -e "testthat::test_file('modules/ws3Verify_FRESH/tests/testthat/test-makePlotsHelpers.R')"
```

Expected: all 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add modules/ws3Verify_FRESH/R/makePlotsHelpers.R \
        modules/ws3Verify_FRESH/tests/testthat/test-makePlotsHelpers.R
git commit -m "feat: add time series plot helpers with tests"
```

---

## Task 7: makePlots helpers — maps

**Files:**
- Modify: `modules/ws3Verify_FRESH/R/makePlotsHelpers.R`
- Modify: `modules/ws3Verify_FRESH/tests/testthat/test-makePlotsHelpers.R`

- [ ] **Step 1: Add failing tests**

Append to `test-makePlotsHelpers.R`:

```r
library(terra)

# Minimal SpatRaster for map tests
makeRast <- function(vals = 1:4) terra::rast(nrows = 2, ncols = 2, vals = vals)

test_that("mapAge executes without error and accepts a title", {
  r <- makeRast()
  expect_no_error(mapAge(r, "Test age map"))
})

test_that("mapCumulativeBurn executes without error", {
  r <- makeRast(c(0, 1, 2, 0))
  expect_no_error(mapCumulativeBurn(r))
})

test_that("mapCumulativeHarvest executes without error", {
  r <- makeRast(c(0, 0, 1, 2))
  expect_no_error(mapCumulativeHarvest(r))
})

test_that("mapStudyArea executes without error given a SpatRaster", {
  landscape <- c(makeRast(c(41, 41, 40, 40)))
  names(landscape) <- "fmuid"
  expect_no_error(mapStudyArea(landscape))
})

test_that("saveMap writes a png file when type is png", {
  tmp <- tempfile(fileext = "")
  r   <- makeRast()
  saveMap(fn = function() terra::plot(r), path = tmp, types = "png")
  expect_true(file.exists(paste0(tmp, ".png")))
  unlink(paste0(tmp, ".png"))
})
```

- [ ] **Step 2: Run tests — expect failure on new tests**

```bash
Rscript -e "testthat::test_file('modules/ws3Verify_FRESH/tests/testthat/test-makePlotsHelpers.R')"
```

Expected: 6 previous pass, 5 new fail.

- [ ] **Step 3: Implement map functions in `R/makePlotsHelpers.R`**

Append to `modules/ws3Verify_FRESH/R/makePlotsHelpers.R`:

```r
# ---------------------------------------------------------------------------
# Map functions (produce base graphics via terra::plot)
# ---------------------------------------------------------------------------

#' Plot a stand age raster.
mapAge <- function(ageRaster, title = "Stand age (years)") {
  terra::plot(ageRaster, main = title,
              col = grDevices::hcl.colors(50, palette = "YlGn"))
}

#' Plot the cumulative burn map.
mapCumulativeBurn <- function(burnMap) {
  terra::plot(burnMap, main = "Cumulative burn map (times burned)",
              col = grDevices::hcl.colors(50, palette = "Reds"))
}

#' Plot the cumulative harvest map.
mapCumulativeHarvest <- function(cumulativeHarvestMap) {
  terra::plot(cumulativeHarvestMap, main = "Cumulative harvest map (times harvested)",
              col = grDevices::hcl.colors(50, palette = "Greens"))
}

#' Plot study area TSA boundaries (fmuid layer).
mapStudyArea <- function(landscape) {
  terra::plot(landscape[["fmuid"]], main = "Study area (TSA boundaries)",
              col = grDevices::hcl.colors(nrow(table(terra::values(landscape[["fmuid"]]))),
                                          palette = "Set2"))
}

#' Plot study area in country context using geodata world outline.
#' Falls back gracefully if geodata is unavailable.
mapStudyAreaContext <- function(studyArea) {
  tryCatch({
    world <- geodata::world(path = tempdir())
    terra::plot(world, col = "grey90", border = "grey60",
                main = "Study area in geographic context")
    terra::plot(terra::vect(studyArea), col = "firebrick",
                alpha = 0.6, add = TRUE)
  }, error = function(e) {
    message("mapStudyAreaContext: geodata unavailable, plotting studyArea only. ",
            conditionMessage(e))
    terra::plot(terra::vect(studyArea), main = "Study area")
  })
}

# ---------------------------------------------------------------------------
# saveMap: write a base-graphics map to disk via png/pdf device
# ---------------------------------------------------------------------------

#' Save a base-graphics map function to disk.
#'
#' @param fn    A zero-argument function that produces a base graphics plot.
#' @param path  Output file path WITHOUT extension.
#' @param types Character vector of output types. Supported: "png", "pdf", "screen".
saveMap <- function(fn, path, types = "png") {
  for (type in types) {
    if (type == "png") {
      grDevices::png(paste0(path, ".png"), width = 800, height = 700)
      fn()
      grDevices::dev.off()
    } else if (type == "pdf") {
      grDevices::pdf(paste0(path, ".pdf"), width = 10, height = 9)
      fn()
      grDevices::dev.off()
    } else if (type == "screen") {
      fn()
    }
  }
  invisible(NULL)
}
```

- [ ] **Step 4: Run tests — expect all pass**

```bash
Rscript -e "testthat::test_file('modules/ws3Verify_FRESH/tests/testthat/test-makePlotsHelpers.R')"
```

Expected: all 11 tests pass.

- [ ] **Step 5: Commit**

```bash
git add modules/ws3Verify_FRESH/R/makePlotsHelpers.R \
        modules/ws3Verify_FRESH/tests/testthat/test-makePlotsHelpers.R
git commit -m "feat: add map helpers and saveMap with tests"
```

---

## Task 8: Wire module into global.R

**Files:**
- Modify: `global.R`

- [ ] **Step 1: Add `ws3Verify_FRESH` to the modules vector**

In `global.R`, find the `modules = c(...)` block (around line 35) and add the local module:

```r
modules = c(
  "AllenLarocque/spades_ws3_dataInit@dev",
  "AllenLarocque/spades_ws3@dev",
  "AllenLarocque/spades_ws3_landrAge@PE",
  "AllenLarocque/scfm@development",
  "ws3Verify_FRESH"                          # <-- add this line
)
```

- [ ] **Step 2: Add `ws3Verify_FRESH` params block**

In `global.R`, find the `params = list(...)` block and add after the `fireHarvestPlots` entry:

```r
ws3Verify_FRESH = list(
  .plots   = "png",
  resInHA  = NULL      # NULL = auto-calculate from rasterToMatch
)
```

- [ ] **Step 3: Verify `modulePath` includes the local modules directory**

The `paths` block in `setupProject` already sets `modulePath = file.path("modules")`.
`ws3Verify_FRESH` lives in `modules/ws3Verify_FRESH/`, so no path change is needed.

- [ ] **Step 4: Smoke-test the wiring with a short run**

Set at the top of `global.R` (temporarily):
```r
times = list(start = 0, end = 2)
```

Then run:
```bash
Rscript global.R 2>&1 | tail -40
```

Expected: simulation runs to `end = 2`, no errors from `ws3Verify_FRESH`. Check that `ws3VerifyAnnualDT` has 2 rows and figure PNGs appear in `output/<.rep>/figures/`.

- [ ] **Step 5: Restore `times` and commit**

```r
times = list(start = 0, end = 200)   # restore
```

```bash
git add global.R
git commit -m "feat: wire ws3Verify_FRESH into global.R"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task |
|---|---|
| `ws3VerifyAnnualDT` with 6 columns | Tasks 2, 3, 4 |
| `ws3MissedHarvestDT` with 4 columns | Task 2 |
| `cumulativeHarvestMap` SpatRaster | Task 1 (Init), CollectStats step 6 |
| `ageAtStart` snapshot | Task 1 (Init) |
| 6 time-series figures | Task 6 |
| 6 map figures | Task 7 |
| `collectStats` fires at priority 6 every year | Task 1 (doEvent) |
| `makePlots` fires at `end(sim)` | Task 1 (doEvent) |
| Volume/GS from fm on planning years only | Task 5, CollectStats step 3 |
| Missed harvest from projected_harvest tif ∩ burn | Task 4 |
| `computeBurnBiomass` cohortData join | Task 3 |
| `resInHA` auto-calculated when NA | Task 1 (Init) |
| Load order after spades_ws3, spades_ws3_landrAge, scfmSpread | Task 1 (defineModule) |
| All params: .plots, resInHA, .plotInitialTime, .plotInterval | Task 1 (defineModule) |
| Wire into global.R | Task 8 |

**Placeholder scan:** No TBDs. All code blocks are complete. `mapStudyAreaContext` has a graceful fallback if `geodata` is unavailable — this is a real edge case handled explicitly, not a placeholder.

**Type consistency:**
- `initAnnualDT` → `appendAnnualRow` → `plotHarvestArea` etc: all use `harvestArea_ha`, `burnArea_ha`, `burnedBiomass_gm2`, `harvestVol_m3`, `growingStock_m3` ✓
- `initMissedHarvestDT` → `appendMissedHarvestRow` → `plotMissedHarvest`: all use `plannedHarvestArea_ha`, `actualHarvestArea_ha`, `missedDueToFire_ha` ✓
- `computeMissedHarvest` returns `list(planned=, missed=)` and CollectStats reads `missed$planned`, `missed$missed` ✓
- `queryFmStats` returns `list(harvestVol=, growingStock=)` and CollectStats reads `fmStats$harvestVol`, `fmStats$growingStock` ✓
- `saveMap` called with `fn=`, `path=`, `types=` in MakePlots ✓
