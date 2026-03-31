# makePlotsHelpers.R
# Pure helper functions for MakePlots event in ws3Verify_FRESH.

# ---------------------------------------------------------------------------
# Time series figures
# ---------------------------------------------------------------------------

plotHarvestArea <- function(dt) {
  ggplot2::ggplot(dt, ggplot2::aes(x = year, y = harvestArea_ha)) +
    ggplot2::geom_line(colour = "darkgreen", linewidth = 1) +
    ggplot2::labs(x = "Year", y = "Harvested area (ha)",
                  title = "Annual harvested area")
}

plotBurnArea <- function(dt) {
  ggplot2::ggplot(dt, ggplot2::aes(x = year, y = burnArea_ha)) +
    ggplot2::geom_line(colour = "firebrick", linewidth = 1) +
    ggplot2::labs(x = "Year", y = "Burned area (ha)",
                  title = "Annual burned area")
}

plotHarvestVol <- function(dt) {
  dtPlan <- dt[!is.na(harvestVol_m3)]
  ggplot2::ggplot(dtPlan, ggplot2::aes(x = year, y = harvestVol_m3)) +
    ggplot2::geom_col(fill = "darkgreen") +
    ggplot2::labs(x = "Year (planning periods only)", y = "Harvested volume (m3)",
                  title = "Harvested volume by planning period")
}

plotGrowingStock <- function(dt) {
  dtPlan <- dt[!is.na(growingStock_m3)]
  ggplot2::ggplot(dtPlan, ggplot2::aes(x = year, y = growingStock_m3)) +
    ggplot2::geom_line(colour = "steelblue", linewidth = 1) +
    ggplot2::geom_point(colour = "steelblue", size = 2) +
    ggplot2::labs(x = "Year (planning periods only)", y = "Growing stock (m3)",
                  title = "Growing stock over time")
}

plotBurnedBiomass <- function(dt) {
  ggplot2::ggplot(dt, ggplot2::aes(x = year, y = burnedBiomass_gm2)) +
    ggplot2::geom_line(colour = "orange", linewidth = 1) +
    ggplot2::labs(x = "Year", y = "Burned biomass (g/m2)",
                  title = "Annual burned biomass (proxy for burned volume)")
}

plotMissedHarvest <- function(dt) {
  dtMelt <- data.table::melt(
    dt[, .(year, actualHarvestArea_ha, missedDueToFire_ha)],
    id.vars      = "year",
    variable.name = "outcome",
    value.name   = "area_ha"
  )
  dtMelt[, outcome := factor(outcome,
                              levels = c("actualHarvestArea_ha", "missedDueToFire_ha"),
                              labels = c("Harvested", "Missed (burned)"))]
  ggplot2::ggplot(dtMelt, ggplot2::aes(x = year, y = area_ha, fill = outcome)) +
    ggplot2::geom_col() +
    ggplot2::scale_fill_manual(values = c("Harvested" = "darkgreen",
                                          "Missed (burned)" = "firebrick")) +
    ggplot2::labs(x = "Year", y = "Area (ha)", fill = NULL,
                  title = "Planned harvest: harvested vs missed due to fire")
}

# ---------------------------------------------------------------------------
# Map functions (produce base graphics via terra::plot)
# ---------------------------------------------------------------------------

#' Plot a stand age raster.
mapAge <- function(ageRaster, title = "Stand age (years)") {
  terra::plot(ageRaster, main = title,
              col = grDevices::hcl.colors(50, palette = "YlGn"))
}

#' Plot the cumulative burn map.
mapCumulativeBurn <- function(burnMap) {
  terra::plot(burnMap, main = "Cumulative burn map (times burned)",
              col = grDevices::hcl.colors(50, palette = "Reds"))
}

#' Plot the cumulative harvest map.
mapCumulativeHarvest <- function(cumulativeHarvestMap) {
  terra::plot(cumulativeHarvestMap, main = "Cumulative harvest map (times harvested)",
              col = grDevices::hcl.colors(50, palette = "Greens"))
}

#' Plot study area TSA boundaries (fmuid layer).
mapStudyArea <- function(landscape) {
  terra::plot(landscape[["fmuid"]], main = "Study area (TSA boundaries)",
              col = grDevices::hcl.colors(nrow(table(terra::values(landscape[["fmuid"]]))),
                                          palette = "Set2"))
}

#' Plot study area in country context using geodata world outline.
#' Falls back gracefully if geodata is unavailable.
mapStudyAreaContext <- function(studyArea) {
  tryCatch({
    world <- geodata::world(path = tempdir())
    terra::plot(world, col = "grey90", border = "grey60",
                main = "Study area in geographic context")
    terra::plot(terra::vect(studyArea), col = "firebrick",
                alpha = 0.6, add = TRUE)
  }, error = function(e) {
    message("mapStudyAreaContext: geodata unavailable, plotting studyArea only. ",
            conditionMessage(e))
    terra::plot(terra::vect(studyArea), main = "Study area")
  })
}

# ---------------------------------------------------------------------------
# saveMap: write a base-graphics map function to disk via png/pdf device
# ---------------------------------------------------------------------------

#' Save a base-graphics map function to disk.
#'
#' @param fn    A zero-argument function that produces a base graphics plot.
#' @param path  Output file path WITHOUT extension.
#' @param types Character vector of output types. Supported: "png", "pdf", "screen".
saveMap <- function(fn, path, types = "png") {
  for (type in types) {
    if (type == "png") {
      grDevices::png(paste0(path, ".png"), width = 800, height = 700)
      fn()
      grDevices::dev.off()
    } else if (type == "pdf") {
      grDevices::pdf(paste0(path, ".pdf"), width = 10, height = 9)
      fn()
      grDevices::dev.off()
    } else if (type == "screen") {
      fn()
    }
  }
  invisible(NULL)
}
