# ws3Verify_FRESH test runs

Scripts behind the two-TSA test of the verification and biological figure sets (PR #8, #9).
Run them from the repo root.

| Script | What it does | Memory |
|---|---|---|
| `run_replicate.R <rep>` | tsa41 + tsa40, 100 years, `fireMultiplier = 1.5`, through `global.R`. Writes `output/fixed_fm15_rep<rep>/`. About 50 minutes. | peaks ~52 GB |
| `run_multi.R [folders]` | `mode = "multi"` over saved replicates. Writes `output/fixed_fm15_multi/figures/`. | small |
| `render_figs.R ws3VerifyTables_year100.rds outDir [ws3VerifyMaps_year100.tif]` | Redraws the figures from saved tables, without SpaDES. | small |

- The host's memory is shared: check `free -g` first, and run replicates one after another.
- `global.R`'s `setupProject(useGit = "sub")` pulls the module remotes, so push module branches first.
- Replicates here are separate `.rep` runs, not SpaDES.experiment: spades_ws3 builds its forest model
  in Init and writes rasters under `inputPath`, so it isn't replicate-safe yet.
