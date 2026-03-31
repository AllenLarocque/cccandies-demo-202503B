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
