# plotsCore.R
# Shared pieces of the ws3VerifyTables figures: TSA selection, aggregation over TSAs and runs,
# colours and theme. Tables are long, keyed by scenario, rep, tsa, year (see ws3VerifyTables).

wsColours <- c(harvest = "#1baf7a", fire = "#eb6834", plan = "#2a78d6", skipped = "#6250d6",
               reference = "grey45")
wsAgeRamp <- c("#86b6ef", "#3987e5", "#256abf", "#184f95", "#0d366b")   # young -> old, CVD-checked
wsLandBase <- c(THLB = "#2a78d6", `Non-THLB` = "#eda100", `outside forest` = "grey55")

wsTheme <- function() {
  ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(panel.grid.minor = ggplot2::element_blank(), plot.title.position = "plot",
                   legend.position = "bottom", panel.spacing = ggplot2::unit(1.2, "lines"),
                   plot.margin = ggplot2::margin(5.5, 16, 5.5, 5.5))
}

#' Rows of the chosen TSAs (NULL = all, including rows with tsa NA).
selectTsa <- function(dt, tsa = NULL) {
  # always a copy: plots add columns by reference and must not change the caller's tables
  if (is.null(tsa)) return(data.table::copy(dt))
  keep <- dt[["tsa"]] %in% tsa       # outside [ ]: inside, `tsa` would be the column
  dt[keep]
}

#' Sum value columns over TSAs within each run (and year and `by`); facet = "tsa" keeps TSAs apart.
sumOverTsa <- function(dt, valueCols, by = character(0), facet = "none") {
  grp <- intersect(c("scenario", "rep", "year", by, if (identical(facet, "tsa")) "tsa"), names(dt))
  dt[, lapply(.SD, function(v) sum(v, na.rm = !all(is.na(v)))), by = grp, .SDcols = valueCols]
}

#' Across runs of each scenario: mean and 5-95% band of each value column, by `by`.
#' @return data.table(scenario, by..., variable, mean, lo, hi, nRuns)
summariseRuns <- function(dt, valueCols, by = "year") {
  grp <- intersect(c("scenario", by), names(dt))
  long <- data.table::melt(dt, id.vars = intersect(c("scenario", "rep", by), names(dt)),
                           measure.vars = valueCols, variable.name = "variable", value.name = "v")
  long[, .(mean = mean(v, na.rm = TRUE),
           lo = stats::quantile(v, 0.05, na.rm = TRUE, names = FALSE, type = 7),
           hi = stats::quantile(v, 0.95, na.rm = TRUE, names = FALSE, type = 7),
           nRuns = data.table::uniqueN(rep)),
       by = c(grp, "variable")]
}

#' A ratio per run from numerator and denominator summed over TSAs (and anything not in `by`),
#' then summarised across runs. Rates are never averaged across TSAs or years.
ratioPerRun <- function(dt, num, den, by = "year") {
  grp <- intersect(c("scenario", "rep", by), names(dt))
  numCol <- num; denCol <- den       # column names may shadow the arguments inside [ ]
  r <- dt[, .(n = sum(.SD[[1]], na.rm = TRUE), d = sum(.SD[[2]], na.rm = TRUE)), by = grp, .SDcols = c(numCol, denCol)]
  r[, ratio := data.table::fifelse(d > 0, n / d, NA_real_)]
  summariseRuns(r, "ratio", by = by)
}

#' Largest number of runs in any scenario.
runCount <- function(dt) {
  max(dt[, .(n = data.table::uniqueN(rep)), by = scenario]$n)
}

#' Mean line, plus a 5-95% band when there are several runs.
runLayers <- function(s, colour = "variable", fill = colour, dashed = character(0)) {
  # with one run lo = hi, so the band has no width. `dashed`: series drawn dashed on top, for
  # pairs that should coincide (a check passes when the lines overlap)
  s <- s[!is.na(mean)]                # e.g. mean age at cut in a year without harvest
  top <- s[[colour]] %in% dashed
  list(
    ggplot2::geom_ribbon(ggplot2::aes(ymin = lo, ymax = hi, fill = .data[[fill]]), data = s,
                         alpha = 0.2, colour = NA, show.legend = FALSE),
    ggplot2::geom_line(ggplot2::aes(y = mean, colour = .data[[colour]]), data = s[!top], linewidth = 0.9),
    if (any(top)) ggplot2::geom_line(ggplot2::aes(y = mean, colour = .data[[colour]]), data = s[top],
                                     linewidth = 0.9, linetype = "22"),
    if (data.table::uniqueN(s$year) <= 15) ggplot2::geom_point(ggplot2::aes(y = mean, colour = .data[[colour]]), data = s, size = 1.6),
    ggplot2::scale_x_continuous(breaks = function(l) unique(round(pretty(l))))
  )
}

#' Facets for scenarios and (optionally) TSAs.
facetLayer <- function(dt, facet = "none", scales = "fixed") {
  multiScen <- data.table::uniqueN(dt$scenario) > 1
  byTsa <- identical(facet, "tsa") && "tsa" %in% names(dt)
  if (byTsa && multiScen) ggplot2::facet_grid(scenario ~ tsa, scales = scales)
  else if (byTsa) ggplot2::facet_wrap(~tsa, scales = scales)
  else if (multiScen) ggplot2::facet_wrap(~scenario, scales = scales)
  else NULL
}

#' Subtitle suffix describing the runs shown.
runsNote <- function(dt) {
  n <- runCount(dt)
  if (n > 1) sprintf("Mean of %d runs; band = 5-95%% across runs.", n) else "One run."
}

#' A placeholder figure saying why there is nothing to draw (e.g. a run without fire).
emptyPlot <- function(title, why) {
  ggplot2::ggplot() + ggplot2::theme_void() +
    ggplot2::annotate("text", x = 0, y = 0, label = why, size = 4.5, colour = "grey35") +
    ggplot2::labs(title = title, subtitle = why) + ggplot2::theme(plot.title.position = "plot")
}

#' Every run x year (x TSA when faceting) of the selected TSAs, from ageDT: the grid on which
#' event-based measures (burns, cuts) are zero-filled before averaging across runs.
runGrid <- function(tables, tsa = NULL, facet = "none") {
  g <- selectTsa(tables$ageDT, tsa)
  unique(g[, c("scenario", "rep", "year", if (identical(facet, "tsa")) "tsa"), with = FALSE])
}

#' Facet rows x columns with scenario (when several) and TSA (when faceting) added to the columns.
facetGrid <- function(dt, rows = NULL, cols = NULL, facet = "none", scales = "fixed") {
  cols <- c(cols, if (data.table::uniqueN(dt$scenario) > 1) "scenario", if (identical(facet, "tsa")) "tsa")
  if (is.null(rows) && is.null(cols)) return(NULL)
  f <- stats::as.formula(paste(if (is.null(rows)) "." else paste(rows, collapse = "+"), "~",
                               if (is.null(cols)) "." else paste(cols, collapse = "+")))
  ggplot2::facet_grid(f, scales = scales)
}
