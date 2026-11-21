# fireMultiplier Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Verify the `fireMultiplier` parameter works end-to-end in the scfm/WS3 simulation, producing directionally correct burn rate scaling at 0.5x and 1.5x.

**Architecture:** The feature lives in `scfmutils` (`R/utils_scfmRegime.R`, `R/ratioPartitions.R`) and is wired into the scfm SpaDES modules (`scfmDataPrep`, `scfmRegime`) via the `calcZonalRegimePars()` function. The WS3 project (`cccandies-demo-202503B`) drives the simulations via `global.R`. Three short runs (baseline / scale-up / scale-down) will confirm correctness.

**Tech Stack:** R, SpaDES.core, scfmutils, pkgload (load_all), git

---

## Files

| File | Action | Purpose |
|------|--------|---------|
| `~/projects/scfmutils/R/utils_scfmRegime.R` | Verify | Contains `calcZonalRegimePars()` with `fireMultiplier` logic |
| `~/projects/scfmutils/R/ratioPartitions.R` | Verify | Contains `ratioPartition2()` used by `calcZonalRegimePars()` |
| `cccandies-demo-202503B/global.R` | Modify | Remove `# CURRENTLY BROKEN` comment; set test params |

---

## Task 1: Verify edge cases in ratioPartition2

**Files:**
- Read: `~/projects/scfmutils/R/ratioPartitions.R`
- Read: `~/projects/scfmutils/R/utils_scfmRegime.R`

- [ ] **Step 1: Check empiricalBurnRate = 0 guard**

Open `R/utils_scfmRegime.R`. Confirm that if `empiricalBurnRate` is 0, the `fireMultiplier` branch is not entered (since `targetBurnRate = 0 * fireMultiplier = 0`, which would be set, then `ratioPartition2` would divide by zero). Confirm `ratioPartition3` explicitly stops on this condition. No code change needed if guarded — just verify.

Expected: `empiricalBurnRate = 0` means `nFires = 0` → early return at line ~45, so this path is never reached.

- [ ] **Step 2: Check fireMultiplier = 1 no-op**

In `R/utils_scfmRegime.R`, confirm the guard:
```r
!is.null(fireMultiplier) && fireMultiplier != 1
```
means `fireMultiplier = 1` leaves `targetBurnRate` as NULL → no adjustment applied. Verify by reading the logic.

- [ ] **Step 3: Check pEscape = 0 path in ratioPartition2**

In `R/ratioPartitions.R`, trace through `ratioPartition2` with `pEscape = 0`:
- `step * 0 = 0` → pEscape stays 0 throughout
- The `pEscape > 1` guard at the end won't trigger
- Scaling flows through `xBar` and `rate` instead

Confirm this is acceptable behaviour (fire with zero escape probability stays at zero — fire is effectively suppressed regardless of multiplier).

- [ ] **Step 4: Commit scfmutils if any fixes were needed**

If no changes were needed, skip. If fixes were made:
```bash
cd ~/projects/scfmutils
git add R/ratioPartitions.R R/utils_scfmRegime.R
git commit -m "fix: edge case guards in ratioPartition2 / calcZonalRegimePars"
```

---

## Task 2: Update global.R

**Files:**
- Modify: `cccandies-demo-202503B/global.R` (~line 93)

- [ ] **Step 1: Remove CURRENTLY BROKEN comment**

In `global.R`, find line ~93:
```r
fireMultiplier = fireMultiplier,            # SCFM 'fire multiplier'. Make more stuff burn or less. CURRENTLY BROKEN
```
Change to:
```r
fireMultiplier = fireMultiplier,            # SCFM 'fire multiplier'. Scale fire up (>1) or down (<1) relative to empirical burn rate.
```

- [ ] **Step 2: Commit**

```bash
cd ~/projects/WS3/cccandies-demo-202503B
git add global.R
git commit -m "fix: remove CURRENTLY BROKEN label from fireMultiplier"
```

---

## Task 3: Run baseline simulation (fireMultiplier = 1.0)

**Files:**
- Modify (temporarily): `cccandies-demo-202503B/global.R`

- [ ] **Step 1: Set run parameters in global.R**

Edit the top of `global.R` to set:
```r
times = list(start = 0, end = 5)
fireMultiplier = 1.0
.rep = "baseline"
```

- [ ] **Step 2: Run the simulation**

From the project directory:
```bash
cd ~/projects/WS3/cccandies-demo-202503B
Rscript global.R
```

Expected: simulation completes without error. Output lands in `output/baseline/`.

- [ ] **Step 3: Note burn output for comparison**

Check `simout$burnSummary` (or inspect the saved outputs in `output/baseline/`). Record total burned area across the 5-year run.

---

## Task 4: Run scale-up simulation (fireMultiplier = 1.5)

**Files:**
- Modify (temporarily): `cccandies-demo-202503B/global.R`

- [ ] **Step 1: Set run parameters**

Edit `global.R`:
```r
times = list(start = 0, end = 5)
fireMultiplier = 1.5
.rep = "fm_1.5"
```

- [ ] **Step 2: Run the simulation**

```bash
Rscript global.R
```

Expected: simulation completes. Output in `output/fm_1.5/`.

- [ ] **Step 3: Compare to baseline**

Confirm total burned area in `output/fm_1.5/` is **greater** than in `output/baseline/`.

---

## Task 5: Run scale-down simulation (fireMultiplier = 0.5)

**Files:**
- Modify (temporarily): `cccandies-demo-202503B/global.R`

- [ ] **Step 1: Set run parameters**

Edit `global.R`:
```r
times = list(start = 0, end = 5)
fireMultiplier = 0.5
.rep = "fm_0.5"
```

- [ ] **Step 2: Run the simulation**

```bash
Rscript global.R
```

Expected: simulation completes. Output in `output/fm_0.5/`.

- [ ] **Step 3: Compare to baseline**

Confirm total burned area in `output/fm_0.5/` is **less** than in `output/baseline/`.

---

## Task 6: Restore global.R to default params and commit

**Files:**
- Modify: `cccandies-demo-202503B/global.R`

- [ ] **Step 1: Restore default values**

Reset `global.R` top-of-file variables to their working defaults:
```r
times = list(start = 0, end = 200)
fireMultiplier = 1.5
.rep = "1_optimize"
```

- [ ] **Step 2: Commit**

```bash
cd ~/projects/WS3/cccandies-demo-202503B
git add global.R
git commit -m "restore global.R to default params after smoke test"
```

---

## Task 7: Commit and push scfmutils feature branch

- [ ] **Step 1: Confirm branch state**

```bash
cd ~/projects/scfmutils
git status
git log --oneline -5
```

Expected: on `feature-fireMultiplier`, clean working tree.

- [ ] **Step 2: Push to fork**

```bash
git push origin feature-fireMultiplier
```

- [ ] **Step 3: Review active branches**

```bash
# scfmutils
cd ~/projects/scfmutils
git branch -a

# cccandies
cd ~/projects/WS3/cccandies-demo-202503B
git branch -a
git status
```

Confirm you are on the expected branches for ongoing work.
