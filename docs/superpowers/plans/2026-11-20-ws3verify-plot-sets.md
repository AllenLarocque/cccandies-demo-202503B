# ws3Verify_FRESH plot sets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ws3Verify_FRESH collects run-keyed tables every year and draws a verification set (V1–V7) and a biological set (B1–B9) that work for one or many runs and one or many TSAs.

**Architecture:** Each year one *pixel frame* (cell, tsa, landBase, au, age, volume) is built from `sim$landscape`; pure tabulation helpers turn it plus the module's own end-of-year and plan-year age snapshots (kept in `mod`) into long tables in `sim$ws3VerifyTables`. Pure plot helpers take stacked tables from any number of runs/TSAs, with one aggregation core. A `mode = "multi"` post-processing path gathers saved tables.

**Tech Stack:** R, SpaDES.core modules, data.table, terra, ggplot2, testthat; reticulate for the ws3 ForestModel.

**Spec:** `docs/superpowers/specs/2026-11-20-ws3verify-plot-sets-design.md` (read it first; this plan argues from it).

## Global Constraints

- Only `modules/ws3Verify_FRESH/` changes (plus `global.R` / `global_minimal.R` param wiring and the test-run script). No change to spades_ws3, spades_ws3_landrAge or scfm* (spec anti-goal). Replicate support under SpaDES.experiment is out of scope (Allen, 2026-11-20: a later cross-model framework).
- Existing outputs and figure files unchanged: `ws3VerifyAnnualDT`, `ws3MissedHarvestDT`, `cumulativeHarvestMap`, `ageAtStart`, `ws3VerifyAgeClassDT`, `figures/fig_*.png`, `figures/maps/*`.
- Run keys on every row of every table: `scenario` (chr), `rep` (int), `tsa` (chr, basename such as `"tsa41"`, `NA` outside ws3's forest), `year` (int, simulation year).
- `landBase` levels: `"THLB"`, `"Non-THLB"`, and in fire tables `"outside forest"`.
- Age bins: 10-year, left-closed, label = lower edge as integer (0, 10, …, 390), last bin 400 = 400+.
- Volume = ws3 `totvol` yield curves (`loadYieldCurves()`), no utilisation factor.
- Study-area-agnostic: no hard-coded TSA ids; TSA labels from `basenames` matched to `landscape$fmuid` by the digits in the basename (`"tsa08"` ↔ 8).
- Tests run from the project root: `Rscript -e 'testthat::test_dir("modules/ws3Verify_FRESH/tests/testthat")'`. Current baseline: `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 92 ]`.
- Never edit a script while Rscript runs it (the module re-sources `R/` every event): test runs use a git worktree.
- Branch `fix/ws3verify-plot-sets` (stacked on `fix/ws3verify-age-by-landbase`, PR #7). Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

- A year with no fire and no harvest (all counts 0, no zero-length errors, tables still get their rows) → covered in Task 2/3/4 tests.
- `harvestTiming = "period"` (no `harvestTimingStats`): V1 still draws the landscape side, nothing errors → Task 3 test + Task 5 test.
- A TSA with no THLB pixels, or a land base absent in one TSA: plots still render, shares do not divide by zero → Task 6 test.
- Burned pixels outside ws3's forest (no age): counted under `"outside forest"`, never dropped and never in the V2 denominator → Task 4 test.
- Basenames with zero padding (`tsa08`) and two TSAs in one landscape → Task 1 test.

---

### Task 1: Run keys, TSA labels, age bins, pixel volume, pixel frame

**Files:**
- Create: `modules/ws3Verify_FRESH/R/tablesCore.R`
- Modify: `modules/ws3Verify_FRESH/R/collectStatsHelpers.R` (`computeBurnVolume` uses `pixelVolume`)
- Test: `modules/ws3Verify_FRESH/tests/testthat/test-tablesCore.R`

**Interfaces — Produces:**
- `runKeys(outPath, scenario = "default", rep = 1L) -> list(scenario = chr, rep = int)`: if `basename(outPath)` matches `^(.+)_rep([0-9]+)$` use those, else the args; `warning()` if scenario contains `_`.
- `tsaFromFmuid(fmuid, basenames) -> chr` (same length as fmuid; NA where no match).
- `ageBin(age, width = 10, top = 400) -> int` (lower edge; ages ≥ top → top; NA stays NA).
- `pixelVolume(au, age, yields) -> num` m3/ha per pixel (0 where no AU/curve; linear between points, held at ends — the rule already in `computeBurnVolume`).
- `pixelFrame(landscape, basenames, yields) -> data.table(cell, tsa, landBase, au, age, vol_m3ha)`, one row per non-NA-age forest pixel; `landBase` from `thlb > 0`; uses `layerValues()`.
- `addKeys(dt, keys, year) -> dt` prepends `scenario`, `rep`, `year` (keeps `tsa` where present).

- [ ] **Step 1: Write failing tests** `test-tablesCore.R`:
  - `runKeys("out/fm15_rep03")` → `list(scenario = "fm15", rep = 3L)`; `runKeys("out/1_optimize", "s", 2L)` → `list("s", 2L)`; `expect_warning(runKeys("out/a_b_rep1"))`.
  - `tsaFromFmuid(c(41, 8, 40, NA, 99), list("tsa41", "tsa08", "tsa40"))` → `c("tsa41","tsa08","tsa40",NA,NA)`.
  - `ageBin(c(0, 9, 10, 399, 400, 706, NA))` → `c(0L,0L,10L,390L,400L,400L,NA)`.
  - `pixelVolume` equals the old `computeBurnVolume` per-pixel values on the existing test fixture (sum × resInHA equals the existing expected burned volume).
  - `pixelFrame` on a 2×3 stack with categorical `fmuid` (labels 41, 40) and `thlb` (labels 0, 1) and one NA age: 5 rows, tsa/landBase correct by label.
- [ ] **Step 2: Run tests, expect FAIL** (functions not found).
- [ ] **Step 3: Implement** the six functions in `R/tablesCore.R`; refactor `computeBurnVolume` to call `pixelVolume`.
- [ ] **Step 4: Run the full suite**, expect all PASS (old burned-volume tests unchanged).
- [ ] **Step 5: Commit** `feat(ws3Verify_FRESH): run keys, TSA labels, age bins, pixel frame`.

### Task 2: Age tables and checks — `ageDT`, `checkDT` (B1, B2, B4, V2, V3, V7)

**Files:**
- Create: `modules/ws3Verify_FRESH/R/tablesAge.R`
- Test: `modules/ws3Verify_FRESH/tests/testthat/test-tablesAge.R`

**Interfaces:**
- Consumes: `pixelFrame`, `ageBin` (Task 1).
- Produces:
  - `tabulateAge(pf, resInHA) -> data.table(tsa, landBase, ageBin, area_ha, vol_m3)` — complete grid of tsa × {THLB, Non-THLB} × all bins (zeros included).
  - `checkAges(pf, prevAge, burnedLast, resInHA, resetAgeMax = 2L) -> data.table(tsa, landBase, pixels, naAge_n, forest_ha, burnedLastYear_n, burnedLastYearReset_n, reset_n, unexplainedAgeChange_n, meanAgeChange, expectedMeanAgeChange)`.
    `prevAge`: integer vector over all raster cells, end-of-previous-year age (NULL in the first year → change columns NA). `burnedLast`: integer cell ids burned last year inside the forest.
    Rules: `change = age - prevAge`. `reset` = `change < 1`. `unexplained` = any pixel that is neither `change == 1` nor a reset to `age <= resetAgeMax`. `burnedLastYearReset_n` = burned-last-year pixels with `age <= resetAgeMax` now. `expectedMeanAgeChange` = mean of (1 for unchanged pixels, `age - prevAge` for resets) — i.e. the mean change if only harvest/fire changed ages.
    `naAge_n` counts cells with non-NA `fmuid` but NA age (needs the raw landscape layers; pass `naAge` counts by tsa in as an argument `naAgeByTsa` = named int).
- [ ] **Step 1: Failing tests:**
  - `tabulateAge`: 2 TSAs × 2 land bases × 41 bins = 164 rows; `sum(area_ha)` = pixels × resInHA; volume sums equal `sum(vol_m3ha) * resInHA` per group.
  - `checkAges` all-grow case: every `change == 1` → `unexplainedAgeChange_n == 0`, `reset_n == 0`, `meanAgeChange == expectedMeanAgeChange == 1`.
  - Broken case (pin the bug that started this): a pixel burned last year whose age kept rising → `burnedLastYearReset_n` is one less than `burnedLastYear_n`, `unexplainedAgeChange_n == 0` for it (it grew by 1) — so the V2 ratio, not V3, catches it.
  - A pixel whose age jumps by 10 (the decadal pulse) → `unexplainedAgeChange_n == 1`.
  - First year (`prevAge = NULL`): change columns NA, counts present.
  - No-disturbance year: `burnedLastYear_n == 0`, no division errors.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** in `R/tablesAge.R`.
- [ ] **Step 4: Run full suite, expect PASS.**
- [ ] **Step 5: Commit** `feat(ws3Verify_FRESH): ageDT and checkDT tabulation`.

### Task 3: Harvest tables — `harvestDT`, `harvestAgeDT`, `planDT` (V1, V4, V5, B3)

**Files:**
- Create: `modules/ws3Verify_FRESH/R/tablesHarvest.R`
- Test: `modules/ws3Verify_FRESH/tests/testthat/test-tablesHarvest.R`

**Interfaces:**
- Consumes: Task 1, Task 2's reset definition (`change < 1`).
- Produces:
  - `harvestedCells(pf, prevAge) -> int` cell ids reset this year (at `collectStats`, this year's burns are not yet reset — they reset at priority 9 — so every reset is a harvest). Independent of spades_ws3's stats.
  - `tabulateHarvest(pf, cut, planAge, prevAge, timing, resInHA, year_cal) -> data.table(tsa, planned_ha, applied_ws3_ha, harvested_landscape_ha, skippedBurned_ha, vol_m3, meanAgeAtCut)`.
    `cut` = `harvestedCells()`. `timing` = `sim$harvestTimingStats` or NULL: planned/applied/skipped from its `year == year_cal` rows by `basename` (NA when NULL). `vol_m3` = yield at pre-cut age (`prevAge`) × resInHA; `meanAgeAtCut` from `prevAge`.
  - `tabulateHarvestAge(pf, cut, planAge, prevAge, resInHA) -> data.table(tsa, landBase, ageRef = c("plan","cut"), ageBin, area_ha)`; `tabulateHarvest` also returns `planRuleViolations_n`: cut pixels whose plan-year age (raw, not binned) is outside [100, 400] or whose land base is not THLB (args `minAge = 100`, `maxAge = 400`).
  - `planRow(fm, basenames, year) -> data.table(tsa, plannedVol_m3, plannedArea_ha)` on planning years: per basename `fm$compile_product(1L, "totvol", acode = "harvest", dtype_keys = fm$unmask(tuple(bn,"?","?","?")))` and `"1."` for area (check the reticulate call shape against `queryFmStats()`).
  - `closePlanPeriod(planDT, harvestDT_period, skippedVolPlanAge_m3) -> planDT` fills `cutArea_ha, cutVolPlanAge_m3, skippedVolPlanAge_m3, cutVolCutAge_m3` for the period just ended. The module accumulates per-period sums in `mod` each year (volume at plan age of cut pixels; skipped volume = planned pixels in this year's `projected_harvest_<year>.tif` minus applied ones, valued at plan age — read the projected raster with the same path helper as `computeMissedHarvest`).
  - Plan age (spec: "the age ws3 sees when it plans"): `mod$planAge` = the end-of-year snapshot from the year before the planning year (start year: `ageAtStart`). Pin in a test that a stand planned at age 400 and cut 9 years later at 409 is **not** a violation, and one planned at 99 is.
- [ ] **Step 1: Failing tests:** V1 identity on a fixture (3 reset cells, timing says applied 3 → `applied_ws3_ha == harvested_landscape_ha`); timing NULL → planned/applied/skipped NA, landscape side filled; plan-age violation cases above; non-THLB cut → violation 1; volume at pre-cut age; `closePlanPeriod` arithmetic (cut + skipped = planned on a consistent fixture); empty-harvest year → one zero row per TSA.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** in `R/tablesHarvest.R`.
- [ ] **Step 4: Run full suite, expect PASS.**
- [ ] **Step 5: Commit** `feat(ws3Verify_FRESH): harvest, harvest-age and plan tables`.

### Task 4: Fire tables — `fireDT`, `fireEventsDT` (V2 numerator side, B5, B6, B8)

**Files:**
- Create: `modules/ws3Verify_FRESH/R/tablesFire.R`
- Test: `modules/ws3Verify_FRESH/tests/testthat/test-tablesFire.R`

**Interfaces:**
- Consumes: Task 1.
- Produces:
  - `tabulateFire(pf, burnedCells, resInHA) -> data.table(tsa, landBase, ageBin, burned_ha, burnedVol_m3)`: burned cells in the pixel frame by tsa × landBase × pre-fire ageBin (age at `collectStats`, before reset); burned cells not in the frame → one row `tsa = NA, landBase = "outside forest", ageBin = NA`. Volume from `vol_m3ha`.
  - `fireEvents(burnSummary, year, cellTsa) -> data.table(PolyID, size_ha, tsa)` from `burnSummary[year == year]`, `tsa` of `igLoc` via `cellTsa` (int-indexed chr vector over cells).
- [ ] **Step 1: Failing tests:** burned cells split correctly across 2 TSAs and land bases; a burned cell outside the forest lands in `"outside forest"` and its area is in the table; `sum(burnedVol_m3)` equals `computeBurnVolume()` on the same fixture; no-fire year → zero-row-safe (returns 0-row table with right columns); `fireEvents` sizes equal `areaBurned`.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run full suite, expect PASS.**
- [ ] **Step 5: Commit** `feat(ws3Verify_FRESH): fire tables`.

### Task 5: Module wiring — events, snapshots, `ws3VerifyTables`, saving, B9 rasters

**Files:**
- Modify: `modules/ws3Verify_FRESH/ws3Verify_FRESH.R`
- Modify: `global.R`, `global_minimal.R` (pass `scenario`/`rep` only if set; defaults otherwise)
- Test: `modules/ws3Verify_FRESH/tests/testthat/test-eventOrder.R` (extend), `test-moduleWiring.R` (new, source checks as the existing tests do)

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces: `sim$ws3VerifyTables` = `list(ageDT, checkDT, harvestDT, harvestAgeDT, planDT, fireDT, fireEventsDT, scfmSummaryDT)`, each with run keys; `createsOutput("ws3VerifyTables", "list", …)` with every table's columns described; new params `scenario` ("default"), `rep` (1L), `oldForestAges` (c(140, 250)), `resetAgeMax` (2L), `mode` ("single"), `multiPaths` (NA). Maps saved at end: `burnCount`, `harvestCount`, `timeSinceDisturbance`, `lastDisturbance` (1 = harvest, 2 = fire) as `SpatRaster`s in `sim$ws3VerifyMaps`.
- Event changes:
  - `collectStats` (8): build the pixel frame once; keys from `runKeys(outputPath(sim), P$scenario, P$rep)` (computed here, not in Init — experiment2 changes `outputPath` after simInit); append to each table; on planning years `planRow()` (before its own snapshot) and close the previous period.
  - New `endOfYear` at priority 9.5 (after landrAge `adjustBurnedPixels`, 9): store `mod$prevAge` (age vector), `mod$burnedLast` (this year's burned forest cells), update `timeSinceDisturbance`/`lastDisturbance`/counts; if next year is a planning year, `mod$planAge <- mod$prevAge`.
  - New `collectScfm` at end(sim), priority `.last() + 1`: copy `sim$scfmSummaryDT` (if present) with keys and `tsa = NA`.
  - Saving: in Init, append `ws3VerifyTables` and `ws3VerifyMaps` to `outputs(sim)` at `end(sim)` with file names `ws3VerifyTables_<scenario>_rep<rep>.rds` under `outputPath(sim)` (use `SpaDES.core::outputs<-`; keys resolved at save time: if names must be fixed in Init, use the param/outputPath-derived keys there and document it).
- [ ] **Step 1: Failing tests:** event priorities (`endOfYear` > 9, `collectStats` 8); `createsOutput` lists `ws3VerifyTables` and `ws3VerifyMaps`; `outputs` registration present in Init source.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run full suite, expect PASS.**
- [ ] **Step 5: 10-year smoke** in a worktree (`git worktree add ../wt-plots fix/ws3verify-plot-sets`), tsa41, `global_minimal.R` with `harvestTiming = "annual"`. Expect exit 0, then in R on the saved tables: every year `checkDT$unexplainedAgeChange_n == 0`; `harvestDT$applied_ws3_ha == harvestDT$harvested_landscape_ha`; `planRuleViolations_n == 0`; `forest_ha` constant; `burnedLastYearReset_n / burnedLastYear_n == 1` for years ≥ 1. If `resetAgeMax = 2` is wrong for the real age after harvest/fire, fix the default from the observed values and note it in the commit.
- [ ] **Step 6: Commit** `feat(ws3Verify_FRESH): collect ws3VerifyTables each year; save tables and maps`.

### Task 6: Plot helpers — aggregation core, V1–V7, B1–B9

**Files:**
- Create: `modules/ws3Verify_FRESH/R/plotsCore.R` (aggregation, theme, palettes), `R/plotsVerification.R`, `R/plotsBiology.R`
- Modify: `modules/ws3Verify_FRESH/ws3Verify_FRESH.R` (`MakePlots` writes `figures/verification/V*.png`, `figures/biology/B*.png`); `R/makePlotsHelpers.R` (`plotAgeByLandBase` reads `ageDT` via a thin adapter; old signature kept)
- Test: `tests/testthat/test-plotsCore.R`, `test-plotsVerification.R`, `test-plotsBiology.R`

**Interfaces:**
- Consumes: table schemas from Tasks 2–5.
- Produces:
  - `selectTsa(dt, tsa = NULL)`: NULL → all TSAs; chr vector → those.
  - `sumOverTsa(dt, valueCols, by)`: within each run (`scenario, rep, year` + `by`) sum `valueCols` across the selected TSAs (unless faceting by tsa, then `by` includes `tsa`).
  - `summariseRuns(dt, valueCols, by) -> data.table(by…, variable, mean, lo, hi, nRuns)` with lo/hi = 5% / 95% quantiles over runs; `nRuns == 1` → lo = hi = mean.
  - `ratioPerRun(dt, num, den, by)`: ratio from summed numerator/denominator per run, then `summariseRuns` (spec: rates never averaged across TSAs/years).
  - Every plot function: `plotX(tables, tsa = NULL, facet = c("none", "tsa"), ...) -> ggplot`; single run → lines; several → mean line + 5–95% ribbon; distributions pooled (`facet = "tsa"` overlays per TSA). Names: `plotV1Harvest`, `plotV2FireReset`, `plotV3AgeBalance`, `plotV4HarvestRule`, `plotV5PlanVsCut`, `plotV6FireRegime` (thin wrapper over `scfmSummaryDT`; if scfmDiagnostics already writes the figure in single mode, V6 in single mode only adds the keyed table), `plotV7Conservation`, `plotB1AgeStructure`, `plotB2GrowingStock`, `plotB3WoodSupply`, `plotB4OldForest(thresholds)`, `plotB5Fire` (three panels: annual area, fire-size CCDF on log axes, fire cycle by land base over a 50-year moving window), `plotB6FireSelectivity`, `plotB7DisturbanceMix`, `plotB8BurnedVolume`, `mapB9(maps, runs)`.
  - Style as B1: `theme_minimal(12)`, one-hue ordinal blue ramp for age classes (validated: `#86b6ef,#3987e5,#256abf,#184f95,#0d366b`), harvest/fire colours fixed across figures, no dual axes, a legend for ≥ 2 series, subtitles that say what "pass" looks like for V plots and when evidence is not independent (V1 without `harvestTimingStats`).
- [ ] **Step 1: Failing tests:** `summariseRuns` with 1 run (lo = hi = mean) and 20 runs (known quantiles); `ratioPerRun` ≠ mean of per-TSA ratios on a fixture where they differ; each plot function builds (`ggplot_build`) for 1 run × 1 TSA, 3 runs × 2 TSAs, and `facet = "tsa"`; a TSA with no THLB rows renders without NaN shares; V1 with NA ws3 columns renders and its subtitle says the evidence is landscape-only.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run full suite, expect PASS.**
- [ ] **Step 5: Render all figures** from a synthetic 3-run × 2-TSA fixture to the scratchpad and look at every one (label collisions, empty panels); fix layout issues.
- [ ] **Step 6: Commit** `feat(ws3Verify_FRESH): verification and biological plot sets`.

### Task 7: Gather and multi mode

**Files:**
- Create: `modules/ws3Verify_FRESH/R/gather.R`
- Modify: `modules/ws3Verify_FRESH/ws3Verify_FRESH.R` (`mode = "multi"`: Init reads `multiPaths`, gathers, schedules one `makePlots`; no collection events)
- Test: `tests/testthat/test-gather.R`

**Interfaces:**
- Produces: `gatherWs3VerifyTables(x) -> list` of stacked tables; `x` = character vector of output folders (finds `ws3VerifyTables_*.rds` recursively) or a `simLists` object (each sim's `ws3VerifyTables`). Errors if two runs share `scenario` + `rep`. `gatherWs3VerifyMaps(x)` likewise → list of SpatRaster stacks per map.
- [ ] **Step 1: Failing tests:** gather two saved fixture files → stacked rows, keys intact; duplicate keys → error naming them; a fake `simLists`-like environment of two simList stubs (skip if SpaDES.experiment not installed — it is not today) gives the same result.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run full suite, expect PASS.**
- [ ] **Step 5: Commit** `feat(ws3Verify_FRESH): gather saved tables; multi mode`.

### Task 8: Test run, review, PR

- [ ] **Step 1:** Codex review of the branch (`delegate_task`, Codex provider, full brief: spec + plan paths, house rules, what to check). Fix findings; re-review only if a fix is non-trivial.
- [ ] **Step 2: Test run** in a worktree, two TSAs (`basenames = list("tsa41","tsa40")`), 100 years, `harvestTiming = "annual"`, `fireMultiplier` 1.5, `targetN` 1000, as two separate runs with `.rep` `"plots_rep1"` / `"plots_rep2"` and ws3Verify `scenario = "fm15"`, `rep` 1 / 2 (separate `global.R` runs; SpaDES.experiment is not replicate-safe yet). Expect exit 0 and all V invariants passing in both.
- [ ] **Step 3:** `mode = "multi"` over the two output folders → multi-run figures; look at every figure, single and multi, `tsa = NULL` and `facet = "tsa"`.
- [ ] **Step 4:** Push, open draft PR into `fix/ws3verify-age-by-landbase` (or `feature-verification_plots` if #7 is merged) with a "Behaviour changes" table; link it with the T3 link tool; report results with the figures to Allen.
