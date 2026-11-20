# plotsBiology.R
# B1-B9: what the forest does under harvest and fire. Each takes ws3VerifyTables (one run or many
# stacked) and returns a ggplot (B5: a patchwork); mapB9 draws base-graphics maps.

.ageClass <- function(ageBin, breaks = c(0, 50, 100, 200, 300, Inf)) {
  lo <- head(breaks, -1); hi <- tail(breaks, -1)
  labs <- ifelse(is.finite(hi), paste0(lo, "-", hi - 1), paste0(lo, "+"))
  factor(as.character(cut(ageBin, breaks, right = FALSE, labels = labs)), levels = rev(labs))
}

#' B1. Share of each land base's forest by age class over time (mean over runs).
plotB1AgeStructure <- function(tables, tsa = NULL, facet = "none") {
  dt <- selectTsa(tables$ageDT, tsa)          # a copy
  dt[, ageClass := .ageClass(ageBin)]
  grp <- c("scenario", "rep", "year", "landBase", "ageClass", if (facet == "tsa") "tsa")
  a <- dt[, .(area_ha = sum(area_ha)), by = grp]
  tot <- c("scenario", "rep", "year", "landBase", if (facet == "tsa") "tsa")
  a[, share := {s <- sum(area_ha); if (s > 0) area_ha / s else 0}, by = tot]
  d <- a[, .(share = mean(share)), by = setdiff(grp, "rep")]
  d <- d[d[, .(any = sum(share) > 0), by = setdiff(tot, "rep")], on = setdiff(tot, "rep")][any == TRUE][, any := NULL]
  d[, landBase := factor(landBase, levels = c("THLB", "Non-THLB"))]
  labs <- rev(levels(d$ageClass))
  ggplot2::ggplot(d, ggplot2::aes(year, share, fill = ageClass)) +
    ggplot2::geom_area(colour = "white", linewidth = 0.2) +
    ggplot2::scale_fill_manual(values = stats::setNames(rev(wsAgeRamp), rev(labs)), breaks = labs) +
    ggplot2::scale_y_continuous(labels = function(x) paste0(round(100 * x), "%"), expand = c(0, 0)) +
    ggplot2::scale_x_continuous(expand = c(0, 0)) +
    facetGrid(d, rows = if (data.table::uniqueN(d$scenario) > 1 || facet == "tsa") NULL, cols = "landBase", facet = facet) +
    ggplot2::labs(x = "Year", y = "Share of land base", fill = "Stand age (years)",
                  title = "B1. Age structure by land base",
                  subtitle = paste("ws3 harvests only the THLB; elsewhere only fire resets age.", runsNote(dt))) + wsTheme()
}

#' B2. Growing stock (yield-curve volume at current age) every year, by land base.
plotB2GrowingStock <- function(tables, tsa = NULL, facet = "none") {
  dt <- selectTsa(tables$ageDT, tsa)
  s <- summariseRuns(sumOverTsa(dt, "vol_m3", by = "landBase", facet = facet), "vol_m3",
                     by = c("year", "landBase", if (facet == "tsa") "tsa"))
  ggplot2::ggplot(s, ggplot2::aes(year)) + runLayers(s, colour = "landBase") +
    ggplot2::scale_colour_manual(values = wsLandBase) + ggplot2::scale_fill_manual(values = wsLandBase) +
    ggplot2::scale_y_continuous(labels = function(x) format(x / 1e6, trim = TRUE)) + ggplot2::expand_limits(y = 0) +
    facetLayer(s, facet) +
    ggplot2::labs(x = "Year", y = "Growing stock (million m3)", colour = NULL, title = "B2. Growing stock by land base",
                  subtitle = paste("ws3 yield curves (totvol) at each pixel's age.", runsNote(dt))) + wsTheme()
}

#' B3. Wood supply: area and volume cut per year, and mean age at cut.
plotB3WoodSupply <- function(tables, tsa = NULL, facet = "none") {
  dt <- data.table::copy(selectTsa(tables$harvestDT, tsa))
  dt[, ageArea := meanAgeAtCut * harvested_landscape_ha]
  by <- c("year", if (facet == "tsa") "tsa")
  sm <- sumOverTsa(dt, c("harvested_landscape_ha", "vol_m3", "ageArea"), facet = facet)
  sm[, `:=`(`Area cut (ha)` = harvested_landscape_ha, `Volume cut (thousand m3)` = vol_m3 / 1e3,
            `Mean age at cut (years)` = data.table::fifelse(harvested_landscape_ha > 0, ageArea / harvested_landscape_ha, NA_real_))]
  vars <- c("Area cut (ha)", "Volume cut (thousand m3)", "Mean age at cut (years)")
  s <- summariseRuns(sm, vars, by = by)
  s[, variable := factor(variable, levels = vars)]
  ggplot2::ggplot(s, ggplot2::aes(year)) + runLayers(s) +
    ggplot2::scale_colour_manual(values = stats::setNames(rep(wsColours[["harvest"]], 3), vars), guide = "none") +
    ggplot2::scale_fill_manual(values = stats::setNames(rep(wsColours[["harvest"]], 3), vars)) +
    facetGrid(s, rows = "variable", facet = facet, scales = "free_y") +
    ggplot2::labs(x = "Year", y = NULL, title = "B3. Wood supply",
                  subtitle = paste("Realised harvest: volume at the age when cut.", runsNote(dt))) + wsTheme()
}

#' Area at or above each age threshold, per run, year, TSA and land base.
oldForestArea <- function(ageDT, thresholds = c(140, 250)) {
  data.table::rbindlist(lapply(thresholds, function(th)
    ageDT[ageBin >= th, .(area_ha = sum(area_ha)), by = .(scenario, rep, tsa, year, landBase)][, threshold := th]))
}

#' B4. Old-forest area by land base, for each age threshold.
plotB4OldForest <- function(tables, tsa = NULL, facet = "none", thresholds = c(140, 250)) {
  dt <- oldForestArea(selectTsa(tables$ageDT, tsa), thresholds)
  dt[, threshold := factor(paste0(threshold, "+ years"), levels = paste0(thresholds, "+ years"))]
  s <- summariseRuns(sumOverTsa(dt, "area_ha", by = c("landBase", "threshold"), facet = facet), "area_ha",
                     by = c("year", "landBase", "threshold", if (facet == "tsa") "tsa"))
  ramp <- stats::setNames(wsAgeRamp[c(3, 5, 2, 4, 1)][seq_along(thresholds)], levels(dt$threshold))
  ggplot2::ggplot(s, ggplot2::aes(year)) + runLayers(s, colour = "threshold") +
    ggplot2::scale_colour_manual(values = ramp) + ggplot2::scale_fill_manual(values = ramp) +
    ggplot2::scale_y_continuous(labels = function(x) format(x / 1e3, trim = TRUE)) + ggplot2::expand_limits(y = 0) +
    (if (facet == "tsa") ggplot2::facet_grid(tsa ~ landBase) else ggplot2::facet_wrap(~landBase, nrow = 1)) +
    ggplot2::labs(x = "Year", y = "Area (thousand ha)", colour = "Stand age", title = "B4. Old forest by land base",
                  subtitle = runsNote(tables$ageDT)) + wsTheme()
}

#' Realised fire cycle per land base: forest area / mean annual burned area over a trailing window.
fireCycle <- function(tables, tsa = NULL, window = 50, facet = "none") {
  extra <- if (facet == "tsa") "tsa" else character(0)
  area <- sumOverTsa(selectTsa(tables$ageDT, tsa), "area_ha", by = "landBase", facet = facet)
  burn <- sumOverTsa(selectTsa(tables$fireDT, tsa)[landBase %in% c("THLB", "Non-THLB")], "burned_ha",
                     by = "landBase", facet = facet)
  d <- merge(area, burn, by = c("scenario", "rep", "year", "landBase", extra), all.x = TRUE)
  d[is.na(burned_ha), burned_ha := 0]
  data.table::setorderv(d, c("scenario", "rep", "landBase", extra, "year"))
  d[, burnRoll := data.table::frollmean(burned_ha, window, align = "right"), by = c("scenario", "rep", "landBase", extra)]
  d[, cycle := data.table::fifelse(burnRoll > 0, area_ha / burnRoll, NA_real_)]
  summariseRuns(d[!is.na(burnRoll)], "cycle", by = c("year", "landBase", extra))
}

#' B5. Fire: annual area burned, fire-size distribution, realised fire cycle by land base.
#' Annual burned area in the selected TSAs, zero-filled on every run x year, then across runs.
annualBurn <- function(tables, tsa = NULL, facet = "none") {
  extra <- if (facet == "tsa") "tsa" else character(0)
  g <- runGrid(tables, tsa, facet)
  b <- sumOverTsa(selectTsa(tables$fireDT, tsa), "burned_ha", facet = facet)
  d <- merge(g, b, by = c("scenario", "rep", "year", extra), all.x = TRUE)
  d[is.na(burned_ha), burned_ha := 0]
  summariseRuns(d, "burned_ha", by = c("year", extra))
}

#' B5. Fire: annual area burned, fire-size distribution, realised fire cycle by land base.
plotB5Fire <- function(tables, tsa = NULL, facet = "none", window = 50) {
  s1 <- annualBurn(tables, tsa, facet)
  p1 <- ggplot2::ggplot(s1, ggplot2::aes(year)) + runLayers(s1) +
    ggplot2::scale_colour_manual(values = wsColours[["fire"]], guide = "none") + ggplot2::scale_fill_manual(values = wsColours[["fire"]]) +
    facetLayer(s1, facet) + ggplot2::labs(x = "Year", y = "Burned (ha)", title = "Area burned per year") + wsTheme()
  ev <- selectTsa(tables$fireEventsDT, tsa)
  p2 <- if (is.null(ev) || !nrow(ev)) emptyPlot("Fire sizes", "No fires.") else {
    grp <- c("scenario", if (facet == "tsa") "tsa")
    ev <- ev[, {u <- sort(unique(size_ha)); .(size_ha = u, exceed = vapply(u, function(x) mean(size_ha >= x), 0))}, by = grp]
    ggplot2::ggplot(ev, ggplot2::aes(size_ha, exceed, group = scenario)) +
      ggplot2::geom_step(colour = wsColours[["fire"]], direction = "vh") +
      ggplot2::scale_x_log10() + ggplot2::scale_y_log10() + facetLayer(ev, facet) +
      ggplot2::labs(x = "Fire size (ha)", y = "Share >= size", title = "Fire sizes: share of fires this size or larger (all runs pooled)") + wsTheme()
  }
  window <- min(window, data.table::uniqueN(tables$ageDT$year))
  s3 <- if (is.null(tables$fireDT) || !nrow(tables$fireDT)) NULL else fireCycle(tables, tsa, window, facet)[is.finite(mean)]
  p3 <- if (is.null(s3) || !nrow(s3)) emptyPlot("Realised fire cycle", "No burns in ws3's forest.") else
    ggplot2::ggplot(s3, ggplot2::aes(year)) + runLayers(s3, colour = "landBase") +
      ggplot2::scale_colour_manual(values = wsLandBase) + ggplot2::scale_fill_manual(values = wsLandBase) +
      ggplot2::scale_y_log10() + facetLayer(s3, facet) +
      ggplot2::labs(x = "Year", y = "Years (log)", colour = NULL,
                    title = sprintf("Realised fire cycle (%d-year trailing window)", window)) + wsTheme()
  patchwork::wrap_plots(p1, p2, p3, ncol = 1) +
    patchwork::plot_annotation(title = "B5. Fire", subtitle = runsNote(tables$ageDT), theme = wsTheme())
}

#' Selectivity per run: share of burned area in each age class / that class's share of the forest,
#' both pooled over all years (and TSAs shown), then summarised across runs.
fireSelectivity <- function(tables, tsa = NULL, facet = "none") {
  extra <- if (facet == "tsa") "tsa" else character(0)
  grp <- c("scenario", "rep", "landBase", "ageClass", extra)
  a <- selectTsa(tables$ageDT, tsa)[, ageClass := .ageClass(ageBin)][, .(area = sum(area_ha)), by = grp]
  b <- selectTsa(tables$fireDT, tsa)[landBase %in% c("THLB", "Non-THLB")][, ageClass := .ageClass(ageBin)][
    , .(burn = sum(burned_ha)), by = grp]
  d <- merge(a, b, by = grp, all.x = TRUE)
  d[is.na(burn), burn := 0]
  tot <- c("scenario", "rep", "landBase", extra)
  d[, sel := {ba <- sum(burn); aa <- sum(area)
              data.table::fifelse(area > 0 & ba > 0, (burn / ba) / (area / aa), NA_real_)}, by = tot]
  summariseRuns(d[!is.na(sel)], "sel", by = c("landBase", "ageClass", extra))
}

#' B6. Fire selectivity by age class (1 = burns in proportion to area).
plotB6FireSelectivity <- function(tables, tsa = NULL, facet = "none") {
  title <- "B6. Fire selectivity by age class"
  if (is.null(tables$fireDT) || !nrow(tables$fireDT)) return(emptyPlot(title, "No burns: nothing to compare."))
  s <- fireSelectivity(tables, tsa, facet)
  if (!nrow(s)) return(emptyPlot(title, "No burns in ws3's forest: nothing to compare."))
  s[, ageClass := factor(ageClass, levels = rev(levels(ageClass)))]
  ggplot2::ggplot(s, ggplot2::aes(ageClass, mean, fill = landBase)) +
    ggplot2::geom_hline(yintercept = 1, colour = wsColours[["reference"]], linetype = 2) +
    ggplot2::geom_col(position = ggplot2::position_dodge(width = 0.8), width = 0.7) +
    (if (any(s$nRuns > 1)) ggplot2::geom_errorbar(ggplot2::aes(ymin = lo, ymax = hi),
                                                  position = ggplot2::position_dodge(width = 0.8), width = 0.2)) +
    ggplot2::scale_fill_manual(values = wsLandBase) +
    facetGrid(s, facet = facet) +
    ggplot2::labs(x = "Stand age (years)", y = "Share burned / share of area", fill = NULL, title = title,
                  subtitle = paste("1 = burns in proportion to area; all years pooled.", runsNote(tables$ageDT))) + wsTheme()
}

#' B7. Harvest vs fire area per decade, by land base.
#' Per run: harvest and fire area (and burned volume) per decade x land base, zero-filled, then
#' mean and 5-95% band across each scenario's own runs. Harvest is placed in the land base where it
#' was observed (harvestAgeDT cut rows), so a non-THLB cut shows up there.
decadeTotals <- function(tables, tsa = NULL, facet = "none") {
  extra <- if (facet == "tsa") "tsa" else character(0)
  key <- c("scenario", "rep", "decade", "landBase", extra)
  ha <- selectTsa(tables$harvestAgeDT, tsa)
  h <- if (is.null(ha) || !nrow(ha)) NULL else
    ha[ageRef == "cut"][, decade := (year %/% 10L) * 10L][, .(area = sum(area_ha), vol = 0), by = key][, disturbance := "Harvest"]
  fd <- selectTsa(tables$fireDT, tsa)
  f <- if (is.null(fd) || !nrow(fd)) NULL else
    fd[landBase %in% c("THLB", "Non-THLB")][, decade := (year %/% 10L) * 10L][
      , .(area = sum(burned_ha), vol = sum(burnedVol_m3)), by = key][, disturbance := "Fire"]
  g <- runGrid(tables, tsa, facet)[, decade := (year %/% 10L) * 10L]
  g <- unique(g[, c("scenario", "rep", "decade", extra), with = FALSE])
  g <- g[, data.table::CJ(landBase = c("THLB", "Non-THLB"), disturbance = c("Harvest", "Fire")), by = names(g)]
  ev <- data.table::rbindlist(list(h, f), use.names = TRUE)
  if (!nrow(ev)) ev <- g[0][, `:=`(area = numeric(), vol = numeric())]
  d <- merge(g, ev, by = c(key, "disturbance"), all.x = TRUE)
  d[is.na(area), `:=`(area = 0, vol = 0)]
  summariseRuns(d, c("area", "vol"), by = c("decade", "landBase", "disturbance", extra))[
    , landBase := factor(landBase, levels = c("THLB", "Non-THLB"))]
}

#' B7. Harvest vs fire area per decade, by land base.
plotB7DisturbanceMix <- function(tables, tsa = NULL, facet = "none") {
  s <- decadeTotals(tables, tsa, facet)[variable == "area"]
  ggplot2::ggplot(s, ggplot2::aes(decade + 5, mean, fill = disturbance)) +
    ggplot2::geom_col(position = ggplot2::position_dodge(width = 9), width = 8.5) +
    (if (any(s$nRuns > 1)) ggplot2::geom_errorbar(ggplot2::aes(ymin = lo, ymax = hi),
                                                  position = ggplot2::position_dodge(width = 9), width = 3)) +
    ggplot2::scale_fill_manual(values = c(Harvest = wsColours[["harvest"]], Fire = wsColours[["fire"]])) +
    ggplot2::scale_y_continuous(labels = function(x) format(x / 1e3, trim = TRUE)) +
    facetGrid(s, cols = "landBase", facet = facet) +
    ggplot2::labs(x = "Decade", y = "Area per decade (thousand ha)", fill = NULL,
                  title = "B7. Disturbance mix: harvest vs fire", subtitle = runsNote(tables$ageDT)) + wsTheme()
}

#' B8. Merchantable volume burned per decade, by land base.
plotB8BurnedVolume <- function(tables, tsa = NULL, facet = "none") {
  s <- decadeTotals(tables, tsa, facet)[variable == "vol" & disturbance == "Fire"]
  ggplot2::ggplot(s, ggplot2::aes(decade + 5, mean, fill = landBase)) +
    ggplot2::geom_col(position = ggplot2::position_dodge(width = 9), width = 8.5) +
    (if (any(s$nRuns > 1)) ggplot2::geom_errorbar(ggplot2::aes(ymin = lo, ymax = hi),
                                                  position = ggplot2::position_dodge(width = 9), width = 3)) +
    ggplot2::scale_fill_manual(values = wsLandBase) +
    ggplot2::scale_y_continuous(labels = function(x) format(x / 1e6, trim = TRUE)) +
    facetGrid(s, facet = facet) +
    ggplot2::labs(x = "Decade", y = "Volume burned (million m3 per decade)", fill = NULL,
                  title = "B8. Merchantable volume burned",
                  subtitle = paste("ws3 yield curves at the pre-fire age.", runsNote(tables$ageDT))) + wsTheme()
}

#' B9. End-of-run maps. One run (SpatRaster with burnCount, harvestCount, timeSinceDisturbance,
#' lastDisturbance): all four. Several runs (list of those): mean burn and harvest counts per pixel.
mapB9 <- function(maps) {
  if (inherits(maps, "SpatRaster")) {
    titles <- c(burnCount = "Times burned", harvestCount = "Times harvested",
                timeSinceDisturbance = "Years since last disturbance", lastDisturbance = "Last disturbance")
    pals <- list(burnCount = grDevices::hcl.colors(20, "Oranges", rev = TRUE),
                 harvestCount = grDevices::hcl.colors(20, "Greens", rev = TRUE),
                 timeSinceDisturbance = grDevices::hcl.colors(20, "Blues"))
    op <- graphics::par(mfrow = c(2, 2)); on.exit(graphics::par(op))
    for (nm in names(titles)) {
      if (nm == "lastDisturbance") {
        terra::plot(maps[[nm]], main = titles[[nm]], type = "classes", levels = c("Harvest", "Fire"),
                    col = unname(wsColours[c("harvest", "fire")]), all_levels = TRUE)
      } else {
        terra::plot(maps[[nm]], main = titles[[nm]], col = pals[[nm]])
      }
    }
  } else {
    # runs can cover different TSAs (grids): average within each group of identical geometry
    geom <- vapply(maps, function(r) paste(c(as.vector(terra::ext(r)), terra::res(r), dim(r)[1:2]), collapse = "_"), "")
    groups <- split(maps, factor(geom, levels = unique(geom)))
    op <- graphics::par(mfrow = c(length(groups), 2)); on.exit(graphics::par(op))
    for (g in groups) {
      burn <- terra::app(terra::rast(lapply(g, function(r) r[["burnCount"]])), mean, na.rm = TRUE)
      harv <- terra::app(terra::rast(lapply(g, function(r) r[["harvestCount"]])), mean, na.rm = TRUE)
      terra::plot(burn, main = sprintf("Mean times burned (%d runs)", length(g)),
                  col = grDevices::hcl.colors(20, "Oranges", rev = TRUE))
      terra::plot(harv, main = sprintf("Mean times harvested (%d runs)", length(g)),
                  col = grDevices::hcl.colors(20, "Greens", rev = TRUE))
    }
  }
  invisible(NULL)
}
