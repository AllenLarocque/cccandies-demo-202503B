# ws3Verify_FRESH — Design Spec

**Date:** 2026-03-31
**Author:** Allen Larocque
**Branch:** `feature-verification_plots`
**Project:** `cccandies-demo-202503B`

---

## Background

The `cccandies-demo-202503B` stack integrates forest harvesting (ws3), stochastic fire (scfm), and
age tracking (spades_ws3_landrAge). There is currently no unified diagnostic module that verifies
the interaction between fire and harvest over a simulation. Two diagnostic modules
(`spades_ws3_diag_FRESH`, `spades_ws3_scfm_diag_FRESH`) are referenced but commented out in
`global.R` and have no implementation. `ws3Verify_FRESH` replaces both with a single, comprehensive
verification module.

---

## Goal

Produce a reusable SpaDES module (`ws3Verify_FRESH`) that generates a standard suite of
verification plots and supporting data.tables for any run of the ws3+scfm stack. Not tied to any
specific run or parameter sweep.

---

## Architecture

Two event types:

### `collectStats` (every year, priority 6)

Fires after harvest and fire events have settled each year. Accumulates data into three simList
objects. Queries the Python ForestModel (`sim$fm`) only on planning years to avoid unnecessary
overhead.

### `makePlots` (once at `end(sim)`)

Reads the three accumulated objects plus existing sim objects and generates all figures via
`SpaDES.core::Plots()`.

### Load order

`ws3Verify_FRESH` loads after: `spades_ws3`, `spades_ws3_landrAge`, `scfmSpread`.

---

## simList Outputs

### `ws3VerifyAnnualDT` — `data.table`

One row per simulation year. All area/biomass metrics are annual; volume and growing stock are
populated only on planning years (NA otherwise).

| Column | Type | Source | Notes |
|---|---|---|---|
| `year` | numeric | `time(sim)` | |
| `harvestArea_ha` | numeric | `harvestStats$ws3_harvestArea_pixels * resInHA` | |
| `burnArea_ha` | numeric | `sum(burnSummary[year==t, areaBurned])` | |
| `burnedBiomass_gm2` | numeric | burned pixels → cohortData join → `sum(B)` | proxy for burned volume |
| `harvestVol_m3` | numeric | `py$fm$compile_product(period, 'totvol', acode='harvest')` | NA in non-planning years |
| `growingStock_m3` | numeric | `py$fm$inventory(period, 'totvol')` | NA in non-planning years |

### `ws3MissedHarvestDT` — `data.table`

One row per simulation year. Tracks the gap between what ws3 planned and what was actually
harvested, attributing missed area to fire overlap.

| Column | Type | Source | Notes |
|---|---|---|---|
| `year` | numeric | `time(sim)` | |
| `plannedHarvestArea_ha` | numeric | pixel count from `projected_harvest_<year>.tif` × resInHA | path: `inputPath(sim)/tif/<basename>/projected_harvest_<year>.tif`; written by spades_ws3 Python layer |
| `actualHarvestArea_ha` | numeric | `harvestStats$ws3_harvestArea_pixels * resInHA` | |
| `missedDueToFire_ha` | numeric | pixels where planned==1 AND `rstCurrentBurn > 0` × resInHA | |

### `cumulativeHarvestMap` — `SpatRaster`

Pixel-level count of harvest events over the simulation. Initialized as zeros matching
`rasterToMatch`, incremented each year by `rstCurrentHarvest`.

### `ageAtStart` — `SpatRaster`

Snapshot of `landscape$age` taken during the `init` event, for the age-at-start map.

---

## Figures

### Time Series (ggplot2, saved via `Plots()`)

| Name | Geom | X | Y | Data |
|---|---|---|---|---|
| `fig_harvestArea` | line | year | `harvestArea_ha` | `ws3VerifyAnnualDT` |
| `fig_burnArea` | line | year | `burnArea_ha` | `ws3VerifyAnnualDT` |
| `fig_harvestVol` | bar | planning period | `harvestVol_m3` | `ws3VerifyAnnualDT` (NA rows dropped) |
| `fig_growingStock` | line | planning period | `growingStock_m3` | `ws3VerifyAnnualDT` (NA rows dropped) |
| `fig_burnedBiomass` | line | year | `burnedBiomass_gm2` | `ws3VerifyAnnualDT` |
| `fig_missedHarvest` | stacked bar | year | area (ha) | `ws3MissedHarvestDT`; stacks `actualHarvestArea_ha` + `missedDueToFire_ha` to show planned total split by outcome |

### Maps (terra/tmap, saved via `Plots()`)

| Name | Source | Notes |
|---|---|---|
| `map_studyAreaContext` | `studyArea` over country outline | country basemap via `geodata` or similar |
| `map_studyArea` | `landscape$fmuid` or `studyArea` | TSA boundaries, labelled |
| `map_ageStart` | `ageAtStart` | snapshotted at init |
| `map_ageEnd` | `landscape$age` at `end(sim)` | read during `makePlots` |
| `map_cumulativeBurn` | `sim$burnMap` | already produced by scfmSpread |
| `map_cumulativeHarvest` | `cumulativeHarvestMap` | built annually in collectStats |

---

## `collectStats` Data Flow (per year)

1. **Area metrics** — append row to `ws3VerifyAnnualDT` from current `harvestStats` and `burnSummary`
2. **Burn biomass** — `rstCurrentBurn > 0` pixel indices → join `pixelGroupMap` → join `cohortData` → `sum(B)` → store as `burnedBiomass_gm2`
3. **Volume + GS** — only on planning years (`(time(sim) - start(sim)) %% planning_period_freq == 0`): call `reticulate::py$fm$compile_product()` and `py$fm$inventory()`; else store `NA`. The ws3 period index is `(time(sim) - start(sim)) / planning_period_freq + 1`.
4. **Missed harvest** — read `projected_harvest_<year>.tif` (path: `inputPath(sim)/tif/<basename>/projected_harvest_<year>.tif`; use `terra::mosaic` for multiple basenames, matching `buildHarvest()` in `spades_ws3_landrAge`) → count pixels where planned == 1 AND `rstCurrentBurn > 0` → append to `ws3MissedHarvestDT`
5. **Cumulative harvest map** — `cumulativeHarvestMap <- cumulativeHarvestMap + rstCurrentHarvest`

---

## Module Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `.plots` | character | `"png"` | Passed to `SpaDES.core::Plots()` |
| `resInHA` | numeric | `NULL` | Pixel resolution in hectares; NULL = auto-calculate from `rasterToMatch` |
| `.plotInitialTime` | numeric | `end(sim)` | When to run makePlots (conventional SpaDES param) |
| `.plotInterval` | numeric | `NA` | Plot interval (NA = once only) |

---

## Input Objects Required

| Object | Class | Provided by |
|---|---|---|
| `harvestStats` | data.frame | `spades_ws3_landrAge` |
| `rstCurrentHarvest` | SpatRaster | `spades_ws3_landrAge` |
| `rstCurrentBurn` | SpatRaster | `scfmSpread` |
| `burnSummary` | data.table | `scfmSpread` |
| `burnMap` | SpatRaster | `scfmSpread` |
| `pixelGroupMap` | SpatRaster | `spades_ws3_landrAge` |
| `cohortData` | data.table | `spades_ws3_landrAge` / `Biomass_core` |
| `landscape` | SpatRaster | `spades_ws3` / `spades_ws3_dataInit` |
| `studyArea` | sf | `spades_ws3_landrAge` |
| `rasterToMatch` | SpatRaster | `spades_ws3_landrAge` |
| `fm` | Python object | `spades_ws3` (via reticulate) |

---

## Out of Scope

- Multi-replicate / ensemble comparison (not part of this module)
- CBM carbon outputs
- Per-species breakdown of harvested or burned biomass
