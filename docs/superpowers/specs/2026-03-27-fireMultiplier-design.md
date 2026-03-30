# fireMultiplier Feature — Design Spec

**Date:** 2026-03-27
**Author:** Allen Larocque
**Branch (scfmutils):** `feature-fireMultiplier`
**Project:** `cccandies-demo-202503B`

---

## Background

`fireMultiplier` is a scalar parameter that adjusts the empirical burn rate in scfm simulations. It was partially implemented but marked `# CURRENTLY BROKEN` in `global.R`. The `cursor` branch of `scfmutils` contained the implementation (`bb851b4`), which has now been cherry-picked onto `feature-fireMultiplier`.

---

## What Was Done

- Cherry-picked commit `bb851b4` from `cursor` → `feature-fireMultiplier` in `scfmutils`
- Resolved merge conflicts in:
  - `R/ratioPartitions.R` — took the complete `ratioPartition2` / `ratioPartition3` implementation
  - `R/utils_fireRegimePolys.R` — kept `subsetType` parameter (required by function body)
  - `R/utils_scfmRegime.R` — kept HEAD structure, added `fireMultiplier = NULL` parameter, used bb851b4 fireMultiplier logic with `ignitionRate` variable name corrected
- Removed `browser()` debug call from `ratioPartition()`

---

## How fireMultiplier Works

When `fireMultiplier` is set and `!= 1`, `calcZonalRegimePars()` derives a `targetBurnRate`:

```r
targetBurnRate <- empiricalBurnRate * fireMultiplier
```

This is then passed to `ratioPartition2()`, which distributes the scaling ratio across three fire
parameters: `pEscape`, `xBar`, and `ignitionRate`. The distribution is sequential and unequal —
`pEscape` and `xBar` are each adjusted twice before `ignitionRate`, with any final remainder
going entirely to `xBar`. This is intentional for the scale-up direction (`fireMultiplier > 1`)
but may not reflect the correct error structure for scale-down (`fireMultiplier < 1`);
`ratioPartition3()` (equal cube-root partition) exists as a cleaner alternative for that case.

Priority: explicit `targetBurnRate` > `fireMultiplier` > no adjustment (backwards compatible).
If `fireMultiplier` is `NULL` or `1`, no adjustment is applied.

---

## Smoke Test Plan

Three short runs in `cccandies-demo-202503B` with `times = list(start=0, end=5)`.

### How to run

For each run, edit the top of `global.R` to set:
- `times = list(start = 0, end = 5)` (temporarily overrides the default `end = 200`)
- The `fireMultiplier` value for that run
- The `.rep` value for that run (controls output directory: `output/<.rep>/`)

Then source `global.R` (or run `Rscript global.R` from the project directory).

### Runs

| Run | `fireMultiplier` | `.rep`     | Expected direction |
|-----|-----------------|------------|--------------------|
| 1   | 1.0             | `baseline` | Normal burn        |
| 2   | 1.5             | `fm_1.5`   | More burn area     |
| 3   | 0.5             | `fm_0.5`   | Less burn area     |

### Verification

Primary: compare `burnSummary` (produced by `scfmSpread`, always available) across the three
output directories. Confirm burn area is higher in Run 2 and lower in Run 3 relative to Run 1.

`scfmSummaryDT` (from `scfmDiagnostics`) can also be used if that module is active in the run.

---

## Known Issues (Pre-existing, Out of Scope)

- `targetMaxFireSize` override logic in `utils_scfmRegime.R` line ~176 uses `|| is.null` where
  `&& !is.null` is likely intended — could silently overwrite `emfs_ha` with NULL. Not related
  to `fireMultiplier`.

---

## Bugs Found During Integration (2026-03-30)

Two bugs prevented `fireMultiplier` from having any effect, even after the scfmutils implementation was complete:

1. **Wrong module in `global.R` params** — `fireMultiplier` was set under `scfmRegime = list(...)` but `scfmRegime` is not a child of `group_scfm` and never loads. `calcZonalRegimePars()` is called by `scfmDataPrep`. Fixed by moving the param to `scfmDataPrep`.

2. **`setupProject` strips post-hoc module params** — `scfmDataPrep` and other scfm modules are added to `simin$modules` *after* `setupProject()` runs (line ~181 of `global.R`). Any params set inside the `setupProject()` call for those modules are silently stripped. The existing code already worked around this for `targetN` and `.useParallelFireRegimePolys` via manual assignment (`simin$params$scfmDataPrep$... <- ...`). Fixed by adding `simin$params$scfmDataPrep$fireMultiplier <- fireMultiplier` to that block.

---

## End-of-Session Checklist

- [x] Verify `ratioPartition2` edge cases (`empiricalBurnRate=0`, `pEscape=0`, `fireMultiplier=1`)
- [x] Update `global.R` — remove `# CURRENTLY BROKEN` comment (~line 93)
- [x] Run three smoke test simulations (baseline / fm_1.5 / fm_0.5)
- [x] Compare `burnSummary` outputs across runs — confirm directional correctness
- [x] Commit `feature-fireMultiplier` and push to `AllenLarocque/scfmutils` (PR #1)
- [x] Review active branches in both `scfmutils` and `cccandies-demo-202503B`
