# ws3Verify_FRESH: verification and biological plot sets — design

Date: 2026-11-20. Status: approved catalogue (Allen, 2026-11-20); this document adds the data layout and mechanics.

## Intent

The WS3_FRESH stack (ws3 harvest optimisation + scfm fire, BC TSA inputs from UBC FRESH) is moving from "does it
run" to "what does it say". Two kinds of figure are needed, from every run:

1. **Verification**: confirm the code does what we intend. The coupling bugs fixed in Nov 2026 (fire never reaching
   ws3's inventory, decadal harvest pulse, wrong plan period, missed harvest never measured) were found by reading
   figures closely. These plots make each such invariant a standing check, with a number that should be 0 or
   flat, so a regression is obvious.
2. **Biological / management**: what the forest does under harvest and fire — age structure, standing volume, wood
   supply, old forest, fire regime and its selectivity, disturbance mix.

Soon the stack will run on several TSAs and many replicates (and later scenarios such as `fireMultiplier` 1.0 vs
1.5). So every figure must work for one run or many, and for one TSA or several, and the numbers behind the figures
must be stored as tables in the simList and on disk for downstream analysis.

## Goals

- The catalogue below (V1–V7, B1–B9), produced by ws3Verify_FRESH at the end of each run.
- All figure data in long, tidy data.tables in the simList, keyed so runs and TSAs can be stacked and filtered.
- The same plot functions draw one run or many runs, one TSA, all TSAs combined, or TSAs faceted.
- A post-processing path that gathers saved tables from many runs and draws the multi-run figures.

## Non-goals

- Biomass and species-composition figures. The stack's LandR objects are placeholders (spades_ws3_landrAge: one
  cohort per pixel, B = 7777) until it is combined with WS3_LandR. The table layout should leave room for them.
- Changing the fire or harvest models. This is measurement only.
- An interactive dashboard. Figures are files (png via `SpaDES.core::Plots`), plus the tables.

## Anti-goals (a failure even if it technically works)

- **A verification plot that cannot fail.** A check that recomputes a number from the same source it is
  checking (e.g. "applied = planned − skipped" read entirely from spades_ws3's own `harvestTimingStats`) proves
  nothing. Each V plot must compare two independent pieces of evidence: what one module says it did against what
  the landscape/inventory shows. Where only one source exists, say so in the figure subtitle.
- Averaging rates across TSAs or runs when they should be pooled (see "Combining runs and TSAs").
- Changing defaults or behaviour of PredictiveEcology modules (spades_ws3, spades_ws3_landrAge, scfm*). If a
  measurement truly needs a hook in one of them, it goes behind a new parameter whose default is a no-op, with a
  regression test, in its own PR on Allen's fork (house rules in `~/.claude/CLAUDE.md`).
- Breaking existing ws3Verify_FRESH outputs (`ws3VerifyAnnualDT`, `ws3MissedHarvestDT`, `cumulativeHarvestMap`,
  `ageAtStart`, `ws3VerifyAgeClassDT` from PR #7) or the figures other people already look at, in this round.

## Constraints

- ws3Verify_FRESH is a project-local module (`modules/ws3Verify_FRESH`, in the project repo, not a submodule), so
  it may change freely, but stays study-area-agnostic: no hard-coded TSA ids, paths or areas.
- SpaDES conventions: tables are module outputs (`createsOutput`), helpers live in `R/`, tests in
  `tests/testthat/` (run from the project root: `Rscript -e 'testthat::test_dir("modules/ws3Verify_FRESH/tests/testthat")'`),
  packages via module `reqdPkgs`. Saving uses the SpaDES `outputs()` mechanism, not ad hoc writes, where it fits.
- Cost: one run is 300 years × ~360,000 forest pixels per TSA, about 1 hour on one worker today. Annual collection
  must stay a small fraction of that (target < 10% of run time). Pixel-level work per year is fine; storing
  per-pixel histories is not.
- Event order each year (SpaDES priorities): spades_ws3 `harvest` (5) → `grow` (5) → spades_ws3_landrAge
  `outputHarvestRst` (5.5) → scfmSpread `burn` (7.5) → ws3Verify `collectStats` (8) → spades_ws3_landrAge
  `adjustBurnedPixels` (9, resets burned pixels to age 0). At `collectStats`, this year's burned pixels still carry
  their pre-fire age.

## What exists today (inputs the module can use)

- `sim$landscape`: layers `fmuid` (TSA number, e.g. 41; categorical), `thlb` (0/1, categorical), `au`, `blockid`,
  `age`. `layerValues()` in `R/collectStatsHelpers.R` reads categorical layers by label.
- `sim$harvestTimingStats` (spades_ws3, `harvestTiming = "annual"`): year (calendar), basename, plannedPixels,
  appliedPixels, skippedResetPixels.
- `sim$rstCurrentHarvest` (landrAge): this year's harvested pixels. `applied_harvest_<year>.tif` /
  `projected_harvest_<year>.tif` in the ws3 tif folder.
- `sim$rstCurrentBurn`, `sim$burnSummary` (one row per fire: igLoc, N, year, areaBurned, PolyID), `sim$burnMap`
  (scfmSpread).
- `sim$fireRegimePolys` (scfmDataPrep): calibration targets per PolyID (ignition rate, escape probability, mean
  fire size, empirical burn rate, …).
- scfmDiagnostics (already in the module list) builds `scfmSummaryDT` comparing simulated to target fire regime,
  in `single` mode within a run and `multi` mode in post-processing over saved runs.
- `sim$fm` (ws3 ForestModel via reticulate): `queryFmStats()` gives the plan's period-1 harvest volume
  (`compile_product(1, 'totvol', acode = 'harvest')`) and period-0 growing stock, on planning years.
- ws3 yield curves (`mod$yields`, `loadYieldCurves()`), used today for burned volume.
- ws3 harvest rule: THLB = 1 and `100 <= _age <= 400` (`oe_harvest` in `modules/spades_ws3/python/spadesws3_params.py`).

## The catalogue

### Verification (does the code do what we intend?)

| # | Figure | Evidence compared | Pass looks like |
|---|---|---|---|
| V1 | Harvest per year: planned, applied, skipped because the stand burned since the plan | spades_ws3's `harvestTimingStats` vs pixels actually reset by harvest in the landscape (from `rstCurrentHarvest` / the age change) | applied (ws3) = harvested (landscape) every year; applied = planned − skipped |
| V2 | Burned area vs area reset to age 0 | pixels in `rstCurrentBurn` in year t vs the same pixels' age at t+1 (≤ 1, or harvested) | ratio 1 for burns inside ws3's forest; burns outside the forest shown separately |
| V3 | Age balance | each pixel's age vs its age a year earlier: expected +1, or reset if harvested/burned | count of unexplained age changes = 0 every year; mean-age change = expected |
| V4 | Age and land base of harvested stands before the cut | pre-cut age and THLB flag of every harvested pixel vs the ws3 harvest rule | zero violations (non-THLB, age < 100 or > 400) |
| V5 | Planned vs cut volume per planning period | the plan's period-1 volume (`queryFmStats`) vs yield-curve volume at pre-cut age summed over the pixels actually cut in that period | close agreement; a persistent gap means harvest is not landing as planned |
| V6 | Simulated fire regime vs scfm calibration targets, per fire-regime polygon | `scfmSummaryDT` (reuse scfmDiagnostics, do not reimplement) | simulated inside the target range |
| V7 | Conservation | forest area and THLB area per TSA, count of NA ages | flat lines; zero NA |

### Biological / management (what does the forest do?)

| # | Figure | Notes |
|---|---|---|
| B1 | Age structure by land base | exists (PR #7); move onto the new age table |
| B2 | Growing stock every year, by land base | yield-curve volume at current age; complements the plan-year `queryFmStats` value |
| B3 | Wood supply: volume and area cut per year, mean age at cut | |
| B4 | Old-forest area by land base | thresholds are parameters; defaults 140 and 250 years |
| B5 | Fire: area burned per year, fire-size distribution, realised fire cycle by land base | fire cycle = forest area / mean annual burned area, over a window |
| B6 | Fire selectivity by age class | share of burned area in each age class ÷ that class's share of the forest (1 = burns in proportion) |
| B7 | Disturbance mix: harvest vs fire area per decade, by land base | |
| B8 | Merchantable volume burned, by land base | the existing burned-volume calculation, split |
| B9 | End-of-run maps: time since disturbance, last disturbance type, burn count, harvest count | single run; multi-run: mean burn and harvest frequency per pixel |

## Data layout

All tables are long data.tables with the same **run keys** on every row:

| Column | Meaning | Source |
|---|---|---|
| `scenario` | label for a set of runs (e.g. "fm15annual") | SpaDES.experiment's simList name (see below); else ws3Verify param `scenario`, default `"default"` |
| `rep` | replicate number | SpaDES.experiment's replicate number; else ws3Verify param `rep`, default `1L` |
| `tsa` | TSA basename, e.g. `"tsa41"` | from `landscape$fmuid`, matched to `basenames` (handle zero padding, e.g. `tsa08`); `NA` for pixels outside ws3's forest |
| `year` | simulation year (0 = start) | `time(sim)`; calendar year = `base.year + year` is derivable |

Then per table (names are my call; the builder may refine columns but not the keys):

| Table | Grain (beyond run keys) | Columns | Feeds |
|---|---|---|---|
| `ageDT` | landBase × 10-year age bin (last bin open, e.g. 400+) | area_ha, vol_m3 | B1, B2, B4, B6 (denominator), V7 |
| `harvestDT` | — | planned_ha, applied_ws3_ha, harvested_landscape_ha, skippedBurned_ha, vol_m3, meanAgeAtCut | V1, B3, B7 |
| `harvestAgeDT` | landBase × 10-year pre-cut age bin | area_ha | V4, B3 |
| `planDT` | planning year (`year`) | plannedVol_m3, plannedArea_ha (period 1 of that plan); cutArea_ha, cutVolPlanAge_m3, skippedVolPlanAge_m3, cutVolCutAge_m3 (over that period, filled when the period ends) | V5, B3 |
| `fireDT` | landBase (incl. `"outside forest"`) × 10-year pre-fire age bin | burned_ha, burnedVol_m3 | V2 (denominator), B5, B6, B7, B8 |
| `fireEventsDT` | one row per fire | PolyID, size_ha, tsa of the ignition pixel | B5 (size distribution) |
| `checkDT` | landBase | pixels, naAge_n, burnedLastYear_n, burnedLastYearReset_n, unexplainedAgeChange_n, meanAgeChange, expectedMeanAgeChange | V2, V3, V7 |
| `scfmSummaryDT` | as scfmDiagnostics makes it | + run keys | V6 |

`landBase` levels: `"THLB"`, `"Non-THLB"`, and in `fireDT` also `"outside forest"` (burned pixels with no ws3
age). Age bins are fine so that any coarser class (B1's 0–49/50–99/100–199/200–299/300+, B4's thresholds) is
derived at plot time, not baked in.

The tables live in the simList as one named list, `sim$ws3VerifyTables` (one object to save and gather). The
existing outputs stay as they are this round; the builder may derive them from the new tables if that is simpler,
as long as their columns and values do not change.

Size check: 300 years × 2 TSAs × 2 land bases × ~41 age bins ≈ 50,000 rows for `ageDT` per run; fine.

## Mechanics the builder must get right

- **An end-of-year age snapshot.** V2–V4 need each pixel's age at the end of the previous year (after
  `adjustBurnedPixels`). My call: ws3Verify schedules its own event each year at a priority after 9 (e.g. 9.5) that
  stores the age vector in `mod` (not the simList), and `collectStats` compares against it. Pre-cut age for V4/V5
  is that snapshot's age as ws3 sees it when it harvests; the builder must confirm against spades_ws3's
  `harvest`/`grow` order whether that is snapshot age or snapshot + 1, and document the choice in a test.
- **Independent harvest evidence for V1.** The landscape side comes from pixels whose age was reset this year and
  were not burned last year (or from `rstCurrentHarvest`, which is landrAge's view of ws3's applied harvest raster).
  Prefer the age-change evidence; if `rstCurrentHarvest` is used, the subtitle must say it is not independent.
- **TSA assignment.** Each pixel's TSA from `fmuid`; fires get the TSA of their ignition pixel in `fireEventsDT`
  and per-pixel TSAs in `fireDT`. Burned pixels outside ws3's forest have `tsa = NA` and land base
  `"outside forest"`.
- **`harvestTiming = "period"`** (spades_ws3's default) has no `harvestTimingStats`; V1 then shows the landscape
  side only, and the subtitle says so. The module must not fail.
- **V4 checks ws3's rule at the age ws3 applied it: the plan-year age** (my call). ws3 tests THLB and
  `100 <= _age <= 400` once, when it plans; under `harvestTiming = "annual"` a stand planned for year k of the
  period is cut up to 9 years later, so ages 401–409 at cut are correct. So ws3Verify also keeps an age snapshot
  taken in each planning year (before the plan), and V4 counts violations against that: zero means zero. The
  age at cut is shown alongside (B3, and as a second panel in V4) with no pass/fail.
- **V5 separates the expected parts of the gap** (my call). `planDT` stores, per planning period: the plan's
  period-1 volume; the volume of the pixels actually cut, at plan-year age; the volume of planned pixels skipped
  because they burned, at plan-year age; and the volume actually cut at cut age (realised wood, B3). Pass:
  cut at plan-year age + skipped ≈ planned. The growth between plan and cut is shown, not tested.
- **Volume** uses the same yield expression as ws3's plan (`totvol`, no utilisation factor), so V5 compares like
  with like.

## Replicates and scenarios: SpaDES.experiment (Allen, 2026-11-20)

Replicates and scenarios are launched with SpaDES.experiment: `experiment2(fm15 = sim1, fm10 = sim2, replicates = 5)`.
experiment2 names each run `<simList name>_rep<n>` (zero-padded) and sets that run's `outputPath` to
`<original outputPath>/<name>`; it does not stamp the name into the simList.

- ws3Verify takes `scenario` and `rep` from `basename(outputPath(sim))` when it matches `^(.+)_rep([0-9]+)$`,
  falling back to its `scenario`/`rep` params otherwise (plain `global.R` runs). Read at the first `collectStats`,
  not in Init, because experiment2 changes `outputPath` after `simInit`.
- Scenario names must not contain `_`: `as.data.table.simLists()` takes the simList name as everything before the
  first `_`. The module warns if the derived scenario contains one.
- Multi mode and the gather function find runs either from a `simLists` object (experiment2's return value) or from
  a list of output folders; both give the same stacked tables. `as.data.table.simLists()` with `vals =
  "ws3VerifyTables"` should also work for ad hoc use; the builder checks this.

**Blocker outside this design (found while checking, 2026-11-20): spades_ws3 is not replicate-safe under
experiment2.**

- spades_ws3 builds the Python ForestModel (`sim$fm`, a reticulate pointer) in `Init`, which runs inside `simInit`,
  before experiment2 copies the simList per replicate. Python objects are not copied: sequential replicates share
  one ForestModel, so replicate 2 would start from replicate 1's end state. Parallel workers (multisession/callr) get
  an invalid pointer.
- spades_ws3 reads and writes its working rasters (`inventory_<year>.tif`, `projected_harvest_<year>.tif`,
  `applied_harvest_<year>.tif`) under `inputPath(sim)/tif.path`, and experiment2 only makes `outputPath` unique.
  Replicates would overwrite each other's inventories.

Allen (2026-11-20): replicate runs will be designed alongside the other model sets, possibly as a common SpaDES.experiment framework in a fork of this project. Fixing this is a separate piece of work in a PredictiveEcology module (spades_ws3), so it follows the house rules:
new parameters with no-op defaults (e.g. build the ForestModel at the first event rather than in Init, and keep the
working rasters under `outputPath`), regression tests, its own PR on Allen's fork. Until it lands, multi-run
figures can be tested with separate `global.R` runs (each with its own `.rep`), which the folder-list path supports.

## Saving, gathering and plotting

- Saving: `ws3VerifyTables` is registered with SpaDES `outputs()` (at `end(sim)`) so each run writes it under its
  `outputPath`, with scenario and rep in the file name. The existing figures keep working as today.
- Plot functions take a stacked table (any number of runs/TSAs) and arguments for the view:
  `tsa = NULL` (all TSAs combined), a vector (those TSAs), or `facet = "tsa"`; and `runs = "auto"`, which draws
  one run as lines, several as mean with a 5–95% band for time series, and pools distributions (fire sizes, age
  classes) or overlays them where pooling hides the point.
- Multi-run figures: follow scfmDiagnostics' precedent, a `mode` parameter on ws3Verify_FRESH (`"single"` default,
  `"multi"` for post-processing) where `multi` reads the saved tables from a list of output paths, stacks them,
  and draws the multi-run set. A plain gather function in `R/` does the stacking so the tables can also be loaded
  for analysis outside SpaDES.
- B9 maps: each run also saves its four end-of-run rasters (burn count, harvest count, time since disturbance,
  last disturbance type) through `outputs()` (my call: a few MB per run). Multi mode averages burn and harvest
  counts per pixel across runs; time since disturbance and last disturbance type stay single-run.
- `scfmSummaryDT` rows get `tsa = NA` (fire-regime polygons do not line up with TSAs), and are copied into
  `ws3VerifyTables` by a late end-of-run event, after scfmDiagnostics fills it.
- Figure files: `figures/verification/V1_harvest.png` … and `figures/biology/B1_ageByLandBase.png` …, existing
  figure files unchanged.

## Combining runs and TSAs

- **Areas and volumes** (area burned, harvested, by age class; growing stock): sum across TSAs within a run; then
  across runs, the mean and 5–95% band of those sums.
- **Rates and ratios** (fire cycle, share burned, selectivity, applied/planned, V2's reset ratio): within a run,
  recompute from numerators and denominators summed over the TSAs shown, never average per-TSA or per-year
  ratios; across runs, the mean and 5–95% band of those per-run rates, like areas (my call).
- **Verification counts** (violations, unexplained age changes, NA ages): sum, and also report the maximum over
  runs, since one failing run matters even if the mean looks fine.
- **Distributions** (fire sizes, pre-cut ages): pool the events across runs and TSAs; overlay per-TSA when
  `facet = "tsa"`.

## Testing

- Unit tests for every tabulation helper on tiny hand-built rasters (including categorical `fmuid`/`thlb`, two TSAs,
  NA ages, a burned pixel outside the forest), and for every plot function with one run, several runs and two TSAs.
- A test per verification invariant that feeds a deliberately broken case (e.g. a burned pixel that keeps ageing,
  a harvest of a non-THLB pixel) and checks the check catches it.
- A 10-year tsa41 smoke run (as `global_minimal.R`, `harvestTiming = "annual"`) after which V1, V3, V4 and V7 pass,
  and the tables and figures exist. Then a two-TSA run before calling it done.

## Left to the builder

- Exact column names inside each table (keys fixed), figure styling within the dataviz conventions used for B1
  (one-hue ordinal ramp for age classes, no dual axes, legends for ≥ 2 series).
- Whether to split the work into several PRs (suggested: tables + verification set; biological set; multi-run
  mode), all on branches under `fix/` (the project fork's `feature` branch blocks `feature/*` names), stacked on
  PR #7 (`fix/ws3verify-age-by-landbase`).
- How to measure the run-time cost (target < 10% of run time).
