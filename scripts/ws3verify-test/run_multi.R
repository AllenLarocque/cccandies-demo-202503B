## ws3Verify_FRESH in mode = "multi" over saved replicates (post-processing only, light on memory).
## Usage, from the repo root:  Rscript scripts/ws3verify-test/run_multi.R [runFolder ...]
## Default runs: output/fixed_fm15_rep1 and _rep2. Writes output/fixed_fm15_multi/figures/.
suppressMessages(library(SpaDES.core))
runs <- commandArgs(TRUE)
if (!length(runs)) runs <- c("output/fixed_fm15_rep1", "output/fixed_fm15_rep2")
out <- "output/fixed_fm15_multi"
s <- simInit(times = list(start = 0, end = 0),
             modules = "ws3Verify_FRESH",
             params = list(ws3Verify_FRESH = list(mode = "multi", .plots = "png", multiPaths = runs)),
             paths = list(modulePath = "modules", outputPath = out, inputPath = tempdir()))
s <- spades(s)
tb <- s$ws3VerifyTables
cat("MULTI runs:", nrow(unique(tb$ageDT[, .(scenario, rep)])), " tables:", paste(names(tb), collapse = " "), "\n")
print(list.files(file.path(out, "figures"), recursive = TRUE))
