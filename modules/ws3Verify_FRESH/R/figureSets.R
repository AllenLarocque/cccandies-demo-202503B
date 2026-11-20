# figureSets.R
# Writes the verification (V1-V7) and biological (B1-B9) figure sets from ws3VerifyTables.

#' Figure specs: file name -> function(tables) returning a ggplot / patchwork.
figureSpecs <- function(oldForestAges = c(140, 250)) {
  list(
    verification = list(
      V1_harvest = plotV1Harvest, V2_fireReset = plotV2FireReset, V3_ageBalance = plotV3AgeBalance,
      V4_harvestRule = plotV4HarvestRule, V5_planVsCut = plotV5PlanVsCut, V6_fireRegime = plotV6FireRegime,
      V7_conservation = plotV7Conservation),
    biology = list(
      B1_ageStructure = plotB1AgeStructure, B2_growingStock = plotB2GrowingStock, B3_woodSupply = plotB3WoodSupply,
      B4_oldForest = function(tables, ...) plotB4OldForest(tables, thresholds = oldForestAges, ...),
      B5_fire = plotB5Fire, B6_fireSelectivity = plotB6FireSelectivity, B7_disturbanceMix = plotB7DisturbanceMix,
      B8_burnedVolume = plotB8BurnedVolume))
}

#' Write both figure sets under figDir/verification and figDir/biology.
#'
#' @param tables ws3VerifyTables (one run or several stacked).
#' @param maps   One run's ws3VerifyMaps, a list of several runs' maps, or NULL (no B9).
#' @param save   function(plot, fileWithoutExtension): SpaDES.core::Plots by default.
#' @param byTsa  Also write "<name>_byTSA" versions faceted by TSA (when there are several TSAs).
writeFigureSets <- function(tables, maps, figDir, types = "png", oldForestAges = c(140, 250),
                            save = function(p, file) SpaDES.core::Plots(data = p, types = types, filename = file),
                            byTsa = FALSE) {
  specs <- figureSpecs(oldForestAges)
  hasScfm <- !is.null(tables$scfmSummaryDT) && nrow(tables$scfmSummaryDT) > 0
  multiTsa <- data.table::uniqueN(stats::na.omit(tables$ageDT$tsa)) > 1
  for (set in names(specs)) {
    dir.create(file.path(figDir, set), showWarnings = FALSE, recursive = TRUE)
    for (nm in names(specs[[set]])) {
      if (nm == "V6_fireRegime" && !hasScfm) next
      fn <- specs[[set]][[nm]]
      save(fn(tables), file.path(figDir, set, nm))
      if (byTsa && multiTsa && nm != "V6_fireRegime")
        save(fn(tables, facet = "tsa"), file.path(figDir, set, paste0(nm, "_byTSA")))
    }
  }
  if (!is.null(maps))
    saveMap(fn = function() mapB9(maps), path = file.path(figDir, "biology", "B9_maps"), types = types)
  invisible(figDir)
}
