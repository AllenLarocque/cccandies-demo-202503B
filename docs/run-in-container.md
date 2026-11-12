# Running the WS3_FRESH stack in the agent container

Smallest end-to-end run: one TSA (`tsa41`), years 0–10 (ws3 plans at 2020 and 2030, 10-year
periods), `optimize` mode, scfm fire (`fireMultiplier = 1.5`), ws3Verify_FRESH plots.
First completed 2026-11-10.

## Repeat it

```sh
cd /workspace/cccandies-demo-202503B
git submodule update --init modules/spades_ws3_dataInit modules/spades_ws3 \
    modules/spades_ws3_landrAge modules/scfm
# scfmutils fork that the pinned scfm commit was written against (fireMultiplier), once.
# The run used fa89390 (origin/feature-fireMultiplier, version 2.0.9.9004 on 2026-11-10).
[ -d /workspace/dev/scfmutils ] || \
    git clone https://github.com/AllenLarocque/scfmutils.git /workspace/dev/scfmutils
git -C /workspace/dev/scfmutils worktree add --detach \
    /workspace/dev/scfmutils-feature-fireMultiplier fa89390
SCFMUTILS_PATH=/workspace/dev/scfmutils-feature-fireMultiplier Rscript global_minimal.R
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
| scfm spread calibration (4 polygons, 4 threads) | ~9 min | cached |
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
- scfmutils: `global.R` loads the fork with `pkgload::load_all(SCFMUTILS_PATH)` over the installed
  upstream scfmutils, outside setupProject/Require (this pre-dates the container work). Plain
  `Rscript global.R` needs a checkout at `~/projects/scfmutils`. The parallel calibration workers
  load the installed upstream scfmutils, not the fork.
- The scfm pin `95e2fa6` is only reachable from the fork's `fix/nfdb-point-url` branch (it also
  keeps `b080d74` alive): don't delete that branch.
- `reticulate::install_python()` (pyenv source build) fails: `patch` is not in the image. The
  system Python lacks `python3-venv`. `global_minimal.R` passes uv's prebuilt CPython 3.12 to
  `spades_ws3_dataInit` (`pythonPath`).
- No Google Drive access is needed: `googledrive` is only in `spades_ws3_dataInit`'s
  `reqdPkgs`, never called.
- The first run writes a stand-alone `.Rprofile` (setupProject) that points `.libPaths()` at the
  project library; the bootstrap then installs Require/SpaDES.project there.
