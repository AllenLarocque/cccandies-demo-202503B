# tablesAge.R
# ageDT (area and volume by TSA x land base x age bin) and checkDT (age-accounting checks:
# V2 burned-then-reset, V3 age balance, V7 conservation). Pure functions.

.landBases <- c("THLB", "Non-THLB")

#' Forested area and volume by TSA x land base x 10-year age bin, full grid (zeros included).
tabulateAge <- function(pf, resInHA) {
  grid <- data.table::CJ(tsa = unique(pf$tsa), landBase = .landBases,
                         ageBin = seq(0L, 400L, by = 10L), sorted = FALSE)
  agg <- pf[, .(area_ha = .N * resInHA, vol_m3 = sum(vol_m3ha) * resInHA),
            by = .(tsa, landBase, ageBin = ageBin(age))]
  out <- merge(grid, agg, by = c("tsa", "landBase", "ageBin"), all.x = TRUE, sort = FALSE)
  out[is.na(area_ha), `:=`(area_ha = 0, vol_m3 = 0)]
  data.table::setorder(out, tsa, landBase, ageBin)
  out[]
}

#' Forest cells (with a TSA) that have no age, by TSA x land base.
naAgeCounts <- function(landscape, basenames) {
  tsa <- tsaFromFmuid(layerValues(landscape[["fmuid"]]), basenames)
  age <- layerValues(landscape[["age"]])
  thlb <- layerValues(landscape[["thlb"]])
  i <- which(!is.na(tsa) & is.na(age))
  data.table::data.table(tsa = tsa[i], landBase = ifelse(!is.na(thlb[i]) & thlb[i] > 0, "THLB", "Non-THLB"))[
    , .(naAge_n = .N), by = .(tsa, landBase)]
}

#' Age-accounting checks per TSA x land base (V3, V7).
#'
#' Between two end-of-year snapshots every pixel should age by exactly 1, unless harvest or fire
#' reset it (age now < previous age + 1, to at most resetAgeMax). Anything else is unexplained.
#' Pixels without a previous age are counted in naChange_n and left out of the comparison.
#'
#' @param pf          pixelFrame() of this year (at collectStats, before this year's burn resets).
#' @param prevAge     Age of every raster cell at the end of last year (NULL: no comparison).
#' @param naAge       naAgeCounts() result, or NULL.
#' @return data.table(tsa, landBase, pixels, naAge_n, forest_ha, reset_n, unexplainedAgeChange_n,
#'   naChange_n, meanAgeChange, expectedMeanAgeChange, burned_n, burnedReset_n). The last two (V2)
#'   are NA here; fireResetCounts() fills them after the burn resets.
checkAges <- function(pf, prevAge, resInHA, resetAgeMax = 2L, naAge = NULL) {
  d <- data.table::copy(pf)
  if (is.null(prevAge)) {
    d[, `:=`(change = NA_real_, reset = NA, unexplained = NA, expected = NA_real_)]
  } else {
    d[, change := age - prevAge[cell]]
    d[, reset := change < 1]
    d[, unexplained := !(change == 1 | (reset & age <= resetAgeMax))]
    d[, expected := data.table::fifelse(reset, change, 1)]
  }
  cmp <- !is.null(prevAge)
  agg <- d[, .(pixels = .N,
               forest_ha = .N * resInHA,
               reset_n = if (cmp) sum(reset, na.rm = TRUE) else NA_integer_,
               unexplainedAgeChange_n = if (cmp) sum(unexplained, na.rm = TRUE) else NA_integer_,
               naChange_n = if (cmp) sum(is.na(change)) else NA_integer_,
               meanAgeChange = if (cmp) mean(change, na.rm = TRUE) else NA_real_,
               expectedMeanAgeChange = if (cmp) mean(expected, na.rm = TRUE) else NA_real_),
           by = .(tsa, landBase)]
  grid <- data.table::CJ(tsa = unique(c(pf$tsa, naAge$tsa)), landBase = .landBases, sorted = FALSE)
  out <- merge(grid, agg, by = c("tsa", "landBase"), all.x = TRUE, sort = FALSE)
  out[is.na(pixels), `:=`(pixels = 0L, forest_ha = 0)]
  if (cmp) for (col in c("reset_n", "unexplainedAgeChange_n", "naChange_n"))
    data.table::set(out, which(is.na(out[[col]])), col, 0L)
  out[, naAge_n := 0L]
  if (!is.null(naAge) && nrow(naAge))
    out[naAge, naAge_n := i.naAge_n, on = c("tsa", "landBase")]
  out[, `:=`(burned_n = NA_integer_, burnedReset_n = NA_integer_)]
  data.table::setcolorder(out, c("tsa", "landBase", "pixels", "naAge_n", "forest_ha"))
  data.table::setorder(out, tsa, landBase)
  out[]
}

#' V2: of this year's burned forest cells (taken before landrAge's reset at priority 9), how many
#' are at age exactly 0 after it. Cells whose age became NA stay in the denominator.
#' @param burned data.table(cell, tsa, landBase) of burned forest cells at collectStats.
#' @param ageNow Age of every raster cell after the reset (endOfYear).
#' @return data.table(tsa, landBase, burned_n, burnedReset_n)
fireResetCounts <- function(burned, ageNow) {
  if (!nrow(burned)) return(data.table::data.table(tsa = character(), landBase = character(),
                                                   burned_n = integer(), burnedReset_n = integer()))
  burned[, .(burned_n = .N, burnedReset_n = sum(ageNow[cell] %in% 0)), by = .(tsa, landBase)]
}
