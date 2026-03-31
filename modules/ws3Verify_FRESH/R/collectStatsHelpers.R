# collectStatsHelpers.R
# Pure helper functions for the collectStats event in ws3Verify_FRESH.
# All functions are side-effect free (no sim access) for easy unit testing.

# ---------------------------------------------------------------------------
# DT initializers
# ---------------------------------------------------------------------------

initAnnualDT <- function() {
  data.table::data.table(
    year              = numeric(0),
    harvestArea_ha    = numeric(0),
    burnArea_ha       = numeric(0),
    burnedBiomass_gm2 = numeric(0),
    harvestVol_m3     = numeric(0),
    growingStock_m3   = numeric(0)
  )
}

initMissedHarvestDT <- function() {
  data.table::data.table(
    year                  = numeric(0),
    plannedHarvestArea_ha = numeric(0),
    actualHarvestArea_ha  = numeric(0),
    missedDueToFire_ha    = numeric(0)
  )
}

# ---------------------------------------------------------------------------
# Append helpers
# ---------------------------------------------------------------------------

appendAnnualRow <- function(dt, year, harvestArea_ha, burnArea_ha,
                             burnedBiomass_gm2,
                             harvestVol_m3 = NA_real_,
                             growingStock_m3 = NA_real_) {
  new_row <- data.table::data.table(
    year              = year,
    harvestArea_ha    = harvestArea_ha,
    burnArea_ha       = burnArea_ha,
    burnedBiomass_gm2 = burnedBiomass_gm2,
    harvestVol_m3     = harvestVol_m3,
    growingStock_m3   = growingStock_m3
  )
  data.table::rbindlist(list(dt, new_row), use.names = TRUE, fill = TRUE)
}

appendMissedHarvestRow <- function(dt, year, plannedHarvestArea_ha,
                                    actualHarvestArea_ha, missedDueToFire_ha) {
  new_row <- data.table::data.table(
    year                  = year,
    plannedHarvestArea_ha = plannedHarvestArea_ha,
    actualHarvestArea_ha  = actualHarvestArea_ha,
    missedDueToFire_ha    = missedDueToFire_ha
  )
  data.table::rbindlist(list(dt, new_row), use.names = TRUE, fill = TRUE)
}
