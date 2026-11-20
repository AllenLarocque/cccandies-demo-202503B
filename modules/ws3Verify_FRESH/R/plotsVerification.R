# plotsVerification.R
# V1-V7: figures that check the code does what we intend. Each takes ws3VerifyTables (one run or
# many stacked) and returns a ggplot; the subtitle says what "pass" looks like and the result.

.vLab <- function(x) format(round(x, 1), big.mark = ",", trim = TRUE)

#' V1. Harvest per year: planned, applied (spades_ws3) and harvested (landscape), and skipped
#' because the stand burned since the plan.
plotV1Harvest <- function(tables, tsa = NULL, facet = "none") {
  dt <- selectTsa(tables$harvestDT, tsa)
  cols <- c("planned_raster_ha", "harvested_landscape_ha", "applied_ws3_ha", "skippedBurned_ws3_ha")
  ws3 <- !all(is.na(dt$applied_ws3_ha))
  if (!ws3) cols <- setdiff(cols, c("applied_ws3_ha", "skippedBurned_ws3_ha"))
  s <- summariseRuns(sumOverTsa(dt, cols, facet = facet), cols, by = c("year", if (facet == "tsa") "tsa"))
  labs <- c(planned_raster_ha = "Planned (projected-harvest raster)", harvested_landscape_ha = "Harvested (landscape ages)",
            applied_ws3_ha = "Applied (spades_ws3)", skippedBurned_ws3_ha = "Skipped: burned since plan (spades_ws3)")
  s[, variable := factor(labs[as.character(variable)], levels = labs)]
  pal <- stats::setNames(wsColours[c("plan", "harvest", "reference", "skipped")], labs)
  sub <- if (ws3) {
    gap <- max(abs(dt$applied_ws3_ha - dt$harvested_landscape_ha), na.rm = TRUE)
    sprintf("Pass: applied (spades_ws3) = harvested (landscape) every year. Largest gap: %s ha. %s", .vLab(gap), runsNote(dt))
  } else {
    paste("No harvestTimingStats (harvestTiming = 'period'): landscape evidence only.", runsNote(dt))
  }
  ggplot2::ggplot(s, ggplot2::aes(year)) + runLayers(s, dashed = labs[["applied_ws3_ha"]]) +
    ggplot2::scale_colour_manual(values = pal) + ggplot2::scale_fill_manual(values = pal) +
    facetLayer(s, facet) +
    ggplot2::labs(x = "Year", y = "Area (ha)", colour = NULL, title = "V1. Harvest: planned, applied and skipped",
                  subtitle = sub) + wsTheme() + ggplot2::guides(colour = ggplot2::guide_legend(nrow = 2))
}

#' V2. Share of last year's burned forest pixels that restarted (age reset) this year.
plotV2FireReset <- function(tables, tsa = NULL, facet = "none") {
  dt <- selectTsa(tables$checkDT, tsa)
  title <- "V2. Burned forest restarts after the fire"
  by <- c("year", if (facet == "tsa") "tsa")
  s <- ratioPerRun(dt, "burnedReset_n", "burned_n", by = by)[!is.na(mean)]
  if (!nrow(s)) return(emptyPlot(title, "No burns in ws3's forest: nothing to check."))
  # the worst single run-year, not a quantile: one failing replicate must show
  ry <- dt[, .(n = sum(burnedReset_n, na.rm = TRUE), d = sum(burned_n, na.rm = TRUE)), by = .(scenario, rep, year)][d > 0]
  worst <- min(ry$n / ry$d)
  fd <- tables$fireDT
  outShare <- if (is.null(fd) || !nrow(fd)) NA_real_ else sum(fd[landBase == "outside forest", burned_ha]) / sum(fd$burned_ha)
  ggplot2::ggplot(s, ggplot2::aes(year)) +
    ggplot2::geom_hline(yintercept = 1, colour = wsColours[["reference"]], linetype = 2) +
    runLayers(s) + ggplot2::scale_colour_manual(values = wsColours[["fire"]], guide = "none") +
    ggplot2::scale_fill_manual(values = wsColours[["fire"]]) +
    ggplot2::scale_y_continuous(labels = function(x) paste0(round(100 * x), "%"), limits = c(0, NA)) +
    facetLayer(s, facet) +
    ggplot2::labs(x = "Year", y = "Burned pixels at age 0 after the reset", title = title,
                  subtitle = sprintf("Pass: 100%% every year. Lowest run-year: %s%%. Burns outside ws3's forest (not counted): %s of burned area. %s",
                                     round(100 * worst, 1), if (is.na(outShare)) "n/a" else paste0(round(100 * outShare), "%"),
                                     runsNote(dt))) +
    wsTheme()
}

#' V3. Age balance: unexplained age changes (should be 0) and mean age change vs expected.
plotV3AgeBalance <- function(tables, tsa = NULL, facet = "none") {
  dt <- selectTsa(tables$checkDT, tsa)[!is.na(unexplainedAgeChange_n)]
  by <- c("year", if (facet == "tsa") "tsa")
  u <- summariseRuns(sumOverTsa(dt, "unexplainedAgeChange_n", facet = facet), "unexplainedAgeChange_n", by = by)
  u[, panel := "Unexplained age changes (pixels)"]
  dt[, cmp := pixels - naChange_n]
  dt[, `:=`(obs = meanAgeChange * cmp, exp = expectedMeanAgeChange * cmp)]
  m <- sumOverTsa(dt, c("obs", "exp", "cmp"), facet = facet)[, `:=`(Observed = obs / cmp, Expected = exp / cmp)]
  m <- summariseRuns(m, c("Observed", "Expected"), by = by)[, panel := "Mean age change (years)"]
  s <- rbind(u[, variable := "Unexplained"], m)
  s[, panel := factor(panel, levels = c("Unexplained age changes (pixels)", "Mean age change (years)"))]
  total <- sum(dt$unexplainedAgeChange_n)
  pal <- c(Unexplained = wsColours[["fire"]], Observed = wsColours[["plan"]], Expected = wsColours[["reference"]])
  ggplot2::ggplot(s, ggplot2::aes(year)) + runLayers(s, dashed = "Expected") +
    ggplot2::scale_colour_manual(values = pal) + ggplot2::scale_fill_manual(values = pal) +
    facetGrid(s, rows = "panel", facet = facet, scales = "free_y") +
    ggplot2::labs(x = "Year", y = NULL, colour = NULL, title = "V3. Age balance",
                  subtitle = sprintf("Pass: every pixel ages 1 year unless harvest or fire reset it; 0 unexplained. Unexplained, all years and runs: %s. %s",
                                     format(total, big.mark = ","), runsNote(dt))) + wsTheme()
}

#' V4. Age and land base of harvested stands: at plan time (ws3's rule, 100-400, THLB) and at cut.
plotV4HarvestRule <- function(tables, tsa = NULL, facet = "none", minAge = 100, maxAge = 400, tolerance = 0) {
  dt <- selectTsa(tables$harvestAgeDT, tsa)
  if (is.null(dt) || !nrow(dt)) return(emptyPlot("V4. Harvested stands follow ws3's rule", "No harvest: nothing to check."))
  grp <- c("ageRef", "landBase", "ageBin", if (facet == "tsa") "tsa")
  nRuns <- runCount(tables$harvestDT)
  s <- dt[, .(area_ha = sum(area_ha) / nRuns), by = grp]
  s[, ageRef := factor(ifelse(ageRef == "plan", "Age when planned (rule checked here)", "Age when cut"),
                       levels = c("Age when planned (rule checked here)", "Age when cut"))]
  hv <- selectTsa(tables$harvestDT, tsa)
  viol <- sum(hv$planRuleViolations_n, na.rm = TRUE)
  tol <- if ("planRuleTolerated_n" %in% names(hv)) sum(hv$planRuleTolerated_n, na.rm = TRUE) else NA
  rule <- sprintf("Pass: all cut area THLB and aged %d-%d when planned (dark shade). Violations, all years and runs: %d.",
                  minAge, maxAge, viol)
  tolNote <- if (tolerance > 0 && !is.na(tol))
    sprintf(paste("Allowed within ws3's allocation tolerance (light shade, +/- %g years): %s pixels.",
                  "ws3's spatial allocation matches pixels within one period of the planned age, so a stand planned",
                  "at 100 years can be cut from one aged 90-99."), tolerance, format(tol, big.mark = ","))
  ggplot2::ggplot(s, ggplot2::aes(ageBin + 5, area_ha, fill = landBase)) +
    (if (tolerance > 0) ggplot2::annotate("rect", xmin = minAge - tolerance, xmax = maxAge + tolerance, ymin = -Inf, ymax = Inf,
                                          alpha = 0.06, fill = wsColours[["harvest"]])) +
    ggplot2::annotate("rect", xmin = minAge, xmax = maxAge, ymin = -Inf, ymax = Inf, alpha = 0.12, fill = wsColours[["harvest"]]) +
    ggplot2::geom_col(width = 9) +
    ggplot2::scale_fill_manual(values = wsLandBase) +
    (if (facet == "tsa") ggplot2::facet_grid(tsa ~ ageRef) else ggplot2::facet_wrap(~ageRef, nrow = 1)) +
    ggplot2::labs(x = "Stand age (10-year bins)", y = "Area cut (ha per run)", fill = NULL,
                  title = "V4. Harvested stands follow ws3's rule",
                  subtitle = paste(rule, tolNote, runsNote(tables$harvestDT))) + wsTheme()
}

#' V5. Each plan's period-1 volume vs what was cut (at plan-time age) plus what was skipped.
plotV5PlanVsCut <- function(tables, tsa = NULL, facet = "none") {
  dt <- selectTsa(tables$planDT, tsa)
  title <- "V5. Planned vs cut volume per planning period"
  len <- if ("periodLength" %in% names(dt)) dt$periodLength else max(dt$periodYears, na.rm = TRUE)
  dt <- dt[periodYears >= len & !is.na(cutVolPlanAge_m3)]
  if (!nrow(dt)) return(emptyPlot(title, "No complete planning period yet: nothing to compare."))
  if (!"missedUnexplainedVol_m3" %in% names(dt)) dt[, missedUnexplainedVol_m3 := NA_real_]
  cols <- c("plannedVol_m3", "cutVolPlanAge_m3", "skippedVolPlanAge_m3", "cutVolCutAge_m3", "missedUnexplainedVol_m3")
  sm <- sumOverTsa(dt, cols, facet = facet)
  sm[, cutPlusSkipped := cutVolPlanAge_m3 + skippedVolPlanAge_m3]
  s <- summariseRuns(sm, c("plannedVol_m3", "cutPlusSkipped", "cutVolCutAge_m3"), by = c("year", if (facet == "tsa") "tsa"))
  labs <- c(plannedVol_m3 = "Planned (ws3, period 1)", cutPlusSkipped = "Cut + skipped, at plan-time age",
            cutVolCutAge_m3 = "Cut, at cut-time age (realised)")
  s[, variable := factor(labs[as.character(variable)], levels = labs)]
  gapPct <- if (nrow(sm)) 100 * max(abs(sm$cutPlusSkipped / sm$plannedVol_m3 - 1), na.rm = TRUE) else NA
  pal <- stats::setNames(wsColours[c("plan", "harvest", "reference")], labs)
  ggplot2::ggplot(s, ggplot2::aes(year)) + runLayers(s) +
    ggplot2::scale_colour_manual(values = pal) + ggplot2::scale_fill_manual(values = pal) +
    ggplot2::scale_y_continuous(labels = function(x) format(x / 1e6, trim = TRUE)) +
    facetLayer(s, facet) +
    ggplot2::labs(x = "Planning year", y = "Volume (million m3 per period)", colour = NULL,
                  title = title,
                  subtitle = sprintf(paste("Pass: cut + skipped (planned stands that burned since the plan) = planned. Largest gap: %s%%.",
                                           "Planned stands neither cut nor burned: %s m3. Complete periods only. %s"),
                                     if (is.na(gapPct)) "n/a" else round(gapPct, 1),
                                     format(round(sum(sm$missedUnexplainedVol_m3, na.rm = TRUE)), big.mark = ","),
                                     runsNote(tables$planDT))) +
    wsTheme() + ggplot2::guides(colour = ggplot2::guide_legend(nrow = 2))
}

#' V6. Simulated fire regime vs scfm calibration targets, per fire-regime polygon (scfmDiagnostics).
plotV6FireRegime <- function(tables, tsa = NULL, facet = "none") {
  dt <- tables$scfmSummaryDT
  if (is.null(dt) || !nrow(dt)) {
    return(ggplot2::ggplot() + ggplot2::theme_void() +
             ggplot2::labs(title = "V6. Fire regime vs targets: no scfm summary gathered",
                           subtitle = "scfmDiagnostics writes it at the end of a run; draw V6 in multi mode."))
  }
  m <- list(FRI = c("achievedFRI", "targetFRI", "Fire return interval (years)"),
            IGN = c("achievedIgnitions", "targetIgnitions", "Ignitions per year"),
            ESC = c("achievedEscapes", "targetEscapes", "Escapes per year"),
            MFS = c("modMeanSize", "histMeanSize", "Mean fire size (ha)"))
  long <- data.table::rbindlist(lapply(m, function(v) dt[, .(scenario, rep, PolyID, metric = v[3],
                                                             simulated = get(v[1]), target = get(v[2]))]))
  tg <- unique(long[, .(scenario, PolyID, metric, target)])
  ggplot2::ggplot(long, ggplot2::aes(factor(PolyID))) +
    ggplot2::geom_point(ggplot2::aes(y = target), data = tg, shape = 95, size = 9, colour = wsColours[["reference"]]) +
    ggplot2::geom_point(ggplot2::aes(y = simulated), colour = wsColours[["fire"]], size = 2,
                        position = ggplot2::position_jitter(width = 0.15, height = 0, seed = 1)) +
    ggplot2::scale_y_log10() +
    ggplot2::facet_wrap(~metric, scales = "free_y") +
    ggplot2::labs(x = "Fire-regime polygon", y = NULL, title = "V6. Simulated fire regime vs scfm targets",
                  subtitle = sprintf("Pass: simulated (orange, one point per run; %d runs) near the target (grey bar). Log scale.",
                                     runCount(dt))) +
    wsTheme()
}

#' V7. Conservation: forest area by TSA x land base stays constant; no NA ages.
plotV7Conservation <- function(tables, tsa = NULL, facet = "none") {
  dt <- selectTsa(tables$checkDT, tsa)
  by <- c("year", "landBase", if (facet == "tsa") "tsa")
  s <- summariseRuns(sumOverTsa(dt, "forest_ha", by = "landBase", facet = facet), "forest_ha", by = by)
  drift <- dt[, .(r = diff(range(forest_ha))), by = .(scenario, rep, tsa, landBase)]$r
  ggplot2::ggplot(s, ggplot2::aes(year)) + runLayers(s, colour = "landBase") +
    ggplot2::scale_colour_manual(values = wsLandBase) + ggplot2::scale_fill_manual(values = wsLandBase) +
    ggplot2::expand_limits(y = 0) + facetLayer(s, facet) +
    ggplot2::labs(x = "Year", y = "Forest area (ha)", colour = NULL, title = "V7. Forest area is conserved",
                  subtitle = sprintf("Pass: flat lines, no NA ages. Largest change in a land base: %s ha. NA-age pixels, all years and runs: %s. %s",
                                     .vLab(max(drift)), format(sum(dt$naAge_n), big.mark = ","), runsNote(dt))) + wsTheme()
}
