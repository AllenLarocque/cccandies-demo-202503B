# Larocque 2025
# This is a working script to run SpaDES experiments

# For now this is a very simple file
# Just cut and paste these into the terminal to modify the global.R:


# With fire:
R -e 'basenames <- list("tsa41","tsa40");
                   base.year <- 2020;
                   horizon <- 10;
                   period_length <- 10;
                   planning_period_freq <- 10;
                   scheduler.mode <- "optimize";
                   times <- list(start = 0, end = 5);
                   .rep <- "1_optimize";
                   .cores <- c("sbw");
                   fireMultiplier <- 1;
                   modules <- c("PredictiveEcology/spades_ws3_dataInit@dev",
                                "PredictiveEcology/spades_ws3@dev",
                                "AllenLarocque/spades_ws3_landrAge@PE",
                                "AllenLarocque/scfm@development",
                                "AllenLarocque/spades_ws3_diag_FRESH@main",
                                "AllenLarocque/spades_ws3_scfm_diag_FRESH@main");
                   source("global_expr.R")'

# Without fire:
R -e 'basenames <- list("tsa41","tsa40");
                   base.year <- 2020;
                   horizon <- 10;
                   period_length <- 10;
                   planning_period_freq <- 10;
                   scheduler.mode <- "optimize";
                   times <- list(start = 0, end = 10);
                   .rep <- "2_optimize";
                   .cores <- c("sbw");
                   modules <- c("PredictiveEcology/spades_ws3_dataInit@dev",
                                "PredictiveEcology/spades_ws3@dev",
                                "AllenLarocque/spades_ws3_landrAge@PE",
                                "AllenLarocque/spades_ws3_diag_FRESH@main",
                                );
                   source("global_expr.R")'



