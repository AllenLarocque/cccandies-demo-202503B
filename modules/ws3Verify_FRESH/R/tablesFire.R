# tablesFire.R
# fireDT (B5, B6, B8; V2's burned side) and fireEventsDT (B5 fire sizes). Pure functions.

#' Burned area and merchantable volume this year by TSA x land base x pre-fire 10-year age bin.
#'
#' Ages are those at collectStats, before landrAge resets burned pixels (priority 9). Burned cells
#' that are not in ws3's forest are one row: tsa NA, landBase "outside forest", ageBin NA.
#' @param burnedCells Cell numbers burned this year (rstCurrentBurn > 0).
tabulateFire <- function(pf, burnedCells, resInHA) {
  inForest <- pf[cell %in% burnedCells,
                 .(burned_ha = .N * resInHA, burnedVol_m3 = sum(vol_m3ha) * resInHA),
                 by = .(tsa, landBase, ageBin = ageBin(age))]
  nOut <- sum(!burnedCells %in% pf$cell)
  outside <- if (nOut > 0) {
    data.table::data.table(tsa = NA_character_, landBase = "outside forest", ageBin = NA_integer_,
                           burned_ha = nOut * resInHA, burnedVol_m3 = 0)
  }
  out <- data.table::rbindlist(list(inForest, outside), use.names = TRUE)
  if (!nrow(out)) out <- data.table::data.table(tsa = character(), landBase = character(), ageBin = integer(),
                                                burned_ha = numeric(), burnedVol_m3 = numeric())
  data.table::setorder(out, tsa, landBase, ageBin, na.last = TRUE)
  out[]
}

#' One row per fire this year: fire-regime polygon, size, and TSA of the ignition cell.
#' @param burnSummary sim$burnSummary (scfmSpread): igLoc, year, areaBurned, PolyID, ...
#' @param cellTsa     TSA of every raster cell (NA outside ws3's forest).
fireEvents <- function(burnSummary, year, cellTsa) {
  yr <- year
  bs <- data.table::as.data.table(burnSummary)[year == yr]
  data.table::data.table(PolyID = as.integer(bs$PolyID), size_ha = as.numeric(bs$areaBurned),
                         tsa = cellTsa[bs$igLoc])
}
