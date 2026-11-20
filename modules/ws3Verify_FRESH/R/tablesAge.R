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

#' Age-accounting checks per TSA x land base.
#'
#' Between two end-of-year snapshots every pixel should age by exactly 1, unless harvest or fire
#' reset it (age now < previous age + 1, to at most resetAgeMax). Anything else is unexplained.
#'
#' @param pf          pixelFrame() of this year (at collectStats, before this year's burn resets).
#' @param prevAge     Age of every raster cell at the end of last year (NULL in the first year).
#' @param burnedLast  Cells burned inside the forest last year.
#' @param naAge       naAgeCounts() result, or NULL.
#' @return data.table(tsa, landBase, pixels, naAge_n, forest_ha, burnedLastYear_n,
#'   burnedLastYearReset_n, reset_n, unexplainedAgeChange_n, meanAgeChange, expectedMeanAgeChange)
checkAges <- function(pf, prevAge, burnedLast, resInHA, resetAgeMax = 2L, naAge = NULL) {
  d <- data.table::copy(pf)
  d[, burnedLast := cell %in% burnedLast]
  if (is.null(prevAge)) {
    d[, `:=`(change = NA_real_, reset = NA, unexplained = NA, expected = NA_real_)]
  } else {
    d[, change := age - prevAge[cell]]
    d[, reset := change < 1]
    d[, unexplained := !(change == 1 | (reset & age <= resetAgeMax))]
    d[, expected := data.table::fifelse(reset, change, 1)]
  }
  agg <- d[, .(pixels = .N,
               forest_ha = .N * resInHA,
               burnedLastYear_n = sum(burnedLast),
               burnedLastYearReset_n = sum(burnedLast & age <= resetAgeMax),
               reset_n = sum(reset),
               unexplainedAgeChange_n = sum(unexplained),
               meanAgeChange = mean(change),
               expectedMeanAgeChange = mean(expected)),
           by = .(tsa, landBase)]
  grid <- data.table::CJ(tsa = unique(c(pf$tsa, naAge$tsa)), landBase = .landBases, sorted = FALSE)
  out <- merge(grid, agg, by = c("tsa", "landBase"), all.x = TRUE, sort = FALSE)
  for (col in c("pixels", "burnedLastYear_n", "burnedLastYearReset_n"))
    data.table::set(out, which(is.na(out[[col]])), col, 0L)
  out[is.na(forest_ha), forest_ha := 0]
  if (!is.null(prevAge)) for (col in c("reset_n", "unexplainedAgeChange_n"))
    data.table::set(out, which(is.na(out[[col]])), col, 0L)
  out[, naAge_n := 0L]
  if (!is.null(naAge) && nrow(naAge))
    out[naAge, naAge_n := i.naAge_n, on = c("tsa", "landBase")]
  data.table::setcolorder(out, c("tsa", "landBase", "pixels", "naAge_n", "forest_ha"))
  data.table::setorder(out, tsa, landBase)
  out[]
}
