# Running the WS3_FRESH stack in the agent container

Smallest end-to-end run: one TSA (`tsa41`), years 0–10 (ws3 plans at 2020 and 2030, 10-year
periods), `optimize` mode, scfm fire (`fireMultiplier = 1.5`), ws3Verify_FRESH plots.
First completed 2026-11-10.

## Repeat it

```sh
cd /workspace/cccandies-demo-202503B
git submodule update --init modules/spades_ws3_dataInit modules/spades_ws3 \
    modules/spades_ws3_landrAge modules/scfm
# scfmutils fork that the pinned scfm commit was written against (fireMultiplier)
git -C /workspace/dev/scfmutils worktree add --detach \
    /workspace/dev/scfmutils-feature-fireMultiplier origin/feature-fireMultiplier   # once
SCFMUTILS_PATH=/workspace/dev/scfmutils-feature-fireMultiplier Rscript global_minimal.R
```

`global_minimal.R` sets the run values and sources `global.R`, which now only sets values that
don't exist yet. Outputs: `output/minimal_tsa41/` (figures in `figures/`, maps in
`figures/maps/`, ws3 models in `fm_checkpoints/`). Expect a final "simList saved in
SpaDES.core:::savedSimEnv()$.sim" message and exit status 0.

## Timings (this container: 24 cores, ~3 MB/s downloads)

| Step | First run | Later runs |
|---|---|---|
| R packages into the project library (~125 pkgs, pak) | ~6 min | seconds |
| Python: uv CPython 3.12 + `r-reticulate` venv (ws3, datalad, git-annex, …) | ~2.5 min | ~20 s (`py_install` re-check) |
| datalad dataset `cccandies_demo_input` (all 29 annexed files, ~4 GB) | ~23 min | seconds |
| scfm inputs: 6 NTEMS land-cover rasters + FAO forest (~1.4 GB each), NFDB, ecodistricts | ~95 min | ~1 min (cached) |
| scfm spread calibration (4 polygons, 4 threads) | ~9 min | cached |
| 11 simulated years incl. two ws3 solves + SDA, plots | ~1.5 min | ~1.5 min |
| **Total** | **~2.3 h** | **~2.5 min** |

Not persistent across container re-creation: `~/.virtualenvs/r-reticulate`,
`~/.local/share/uv/python`, the project library in `~/.local/share/R/cccandies-demo-202503B/`.
The data (`modules/spades_ws3_dataInit/cccandies_demo_input`, `input/minimal_tsa41`, `cache/`)
is on `/workspace`. scfm inputs live in `input/<.rep>`, so a new `.rep` downloads them again.

## Container specifics

- `cran.r-project.org` is not on the allowlist. `Require::setLinuxBinaryRepo()` reads its
  mirror list from there; `global.R` wraps that call in `try()`, so repos stay at the image's
  Posit binary snapshot. Require also uses that host in `archivedOn()` (archived package versions).
- `reticulate::install_python()` (pyenv source build) fails: `patch` is not in the image. The
  system Python lacks `python3-venv`. `global_minimal.R` passes uv's prebuilt CPython 3.12 to
  `spades_ws3_dataInit` (`pythonPath`).
- No Google Drive access is needed: `googledrive` is only in `spades_ws3_dataInit`'s
  `reqdPkgs`, never called.
- The first run writes a stand-alone `.Rprofile` (setupProject) that points `.libPaths()` at the
  project library; the bootstrap then installs Require/SpaDES.project there.
