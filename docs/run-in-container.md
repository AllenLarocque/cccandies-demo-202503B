# Running the WS3_FRESH stack in the agent container

Smallest end-to-end run: one TSA (`tsa41`), years 0–10 (ws3 plans at 2020 and 2030, 10-year
periods), `optimize` mode, scfm fire (`fireMultiplier = 1.5`), ws3Verify_FRESH plots.
First completed 2026-11-10.

## Repeat it

```sh
cd /workspace/cccandies-demo-202503B
git submodule update --init modules/spades_ws3_dataInit modules/spades_ws3 \
    modules/spades_ws3_landrAge modules/scfm
Rscript global_minimal.R
```

`global_minimal.R` puts the run values in a list `runOverrides`, which `global.R` applies over
its own values, then sources `global.R`. Outputs: `output/minimal_tsa41/` (figures in `figures/`, maps in
`figures/maps/`, ws3 models in `fm_checkpoints/`). Expect a final "simList saved in
SpaDES.core:::savedSimEnv()$.sim" message and exit status 0.

## Timings (this container: 24 cores, ~3 MB/s downloads)

| Step | First run | Later runs |
|---|---|---|
| R packages into the project library (~125 pkgs, pak) | ~6 min | seconds |
| Python: uv CPython 3.12 + `r-reticulate` venv (ws3, datalad, git-annex, …) | ~2.5 min | ~20 s (`py_install` re-check) |
| datalad dataset `cccandies_demo_input` (all 29 annexed files, ~4 GB) | ~23 min | seconds |
| scfm inputs: 6 NTEMS land-cover rasters + FAO forest (~1.4 GB each), NFDB, ecodistricts | ~95 min | ~1 min (cached) |
| scfm spread calibration (4 polygons, 4 threads) | ~9–12 min | cached (redone when scfm/scfmutils change) |
| 11 simulated years incl. two ws3 solves + SDA, plots | ~1.5 min | ~1.5 min |
| **Total** | **~2.3 h** | **~2.5 min** |

Not persistent across container re-creation: `~/.virtualenvs/r-reticulate`,
`~/.local/share/uv/python`, the project library in `~/.local/share/R/cccandies-demo-202503B/`.
The data (`modules/spades_ws3_dataInit/cccandies_demo_input`, `input/minimal_tsa41`, `cache/`)
is on `/workspace`. scfm inputs live in `input/<.rep>`, so a new `.rep` downloads them again.

## Container specifics

- `cran.r-project.org` was added to the allowlist on 2026-11-12. Before that,
  `Require::setLinuxBinaryRepo()` failed (it reads the mirror list from there), so `global.R` wraps
  it in `try()`. It now succeeds and puts Posit's `latest` Linux binaries ahead of the image's
  dated p3m snapshot, so package versions can differ from the first run (2026-11-10).
  On 2026-11-12 this updated RcppParallel 5.1 → 6.2 (new TBB), which broke the installed binaries
  of `qs2` and `stringfish` ("undefined symbol ... tbb"). Fixed with
  `Require::Install(c("qs2", "stringfish"), install = "force")` (one at a time if pak keeps one),
  then a fresh R session. Check other projects' libraries the same way.
- Our versions of scfm and scfmutils, until the PredictiveEcology PRs are merged:
  scfm `AllenLarocque/scfm@feature/fireMultiplier` (pinned `9213cb4`, = the `modules/scfm` gitlink);
  scfmutils `AllenLarocque/scfmutils@feature/ws3-fresh-integration` (pinned `3521c8e`; PRs #18 +
  #17 merged), installed by setupProject. The scfm modules' `reqdPkgs` name
  `PredictiveEcology/scfmutils@development (>= 2.0.9.9012)`, which that branch can't satisfy yet
  (Require warns); the installed fork satisfies the version. If setupProject stops after
  "Please restart R", rerun it.
- `reticulate::install_python()` (pyenv source build) fails: `patch` is not in the image. The
  system Python lacks `python3-venv`. `global_minimal.R` passes uv's prebuilt CPython 3.12 to
  `spades_ws3_dataInit` (`pythonPath`).
- No Google Drive access is needed: `googledrive` is only in `spades_ws3_dataInit`'s
  `reqdPkgs`, never called.
- The first run writes a stand-alone `.Rprofile` (setupProject) that points `.libPaths()` at the
  project library; the bootstrap then installs Require/SpaDES.project there.
