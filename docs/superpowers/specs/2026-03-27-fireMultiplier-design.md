# fireMultiplier Feature — Design Spec

**Date:** 2026-03-27
**Author:** Allen Larocque
**Branch (scfmutils):** `feature-fireMultiplier`
**Project:** `cccandies-demo-202503B`

---

## Background

`fireMultiplier` is a scalar parameter that adjusts the empirical burn rate in scfm simulations. It was partially implemented but marked `# CURRENTLY BROKEN`. The `cursor` branch of `scfmutils` contained the implementation (`bb851b4`), which has now been cherry-picked onto `feature-fireMultiplier`.

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

This is then passed to `ratioPartition2()`, which distributes the scaling ratio across three fire parameters: `pEscape`, `xBar`, and `ignitionRate`.

Priority: explicit `targetBurnRate` > `fireMultiplier` > no adjustment (backwards compatible).

---

## Smoke Test Plan

Three short runs (`times = list(start=0, end=5)`) in `cccandies-demo-202503B`:

| Run | `fireMultiplier` | `.rep`          | Expected |
|-----|-----------------|-----------------|----------|
| 1   | 1.0             | `baseline`      | Normal burn |
| 2   | 1.5             | `fm_1.5`        | ~50% more burn area |
| 3   | 0.5             | `fm_0.5`        | ~50% less burn area |

**Verification:** Compare `scfmSummaryDT` (or `burnSummary`) across runs. Confirm burn area scales in the expected direction.

---

## End-of-Session Checklist

- [ ] Verify `ratioPartition2` edge cases (`empiricalBurnRate=0`, `pEscape=0`, `fireMultiplier=1`)
- [ ] Update `global.R` — remove `# CURRENTLY BROKEN` comment
- [ ] Run three smoke test simulations
- [ ] Compare burn outputs across runs
- [ ] Commit `feature-fireMultiplier` and push to `AllenLarocque/scfmutils`
- [ ] Review active branches in both `scfmutils` and `cccandies-demo-202503B`
