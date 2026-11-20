# Shared fixtures for ws3Verify_FRESH tests (testthat sources helper-*.R before the tests).

.yieldFixture <- function() {
  # AU 11 -> curve 101: 0,10,20,30 -> 0,100,200,300 m3/ha; AU 12 -> curve 102: 0,10,20 -> 0,50,100
  list(auToCurve = c(`11` = 101, `12` = 102),
       points = list(`101` = data.table::data.table(x = c(0, 10, 20, 30), y = c(0, 100, 200, 300)),
                     `102` = data.table::data.table(x = c(0, 10, 20), y = c(0, 50, 100))))
}

# A landscape stack like spades_ws3_dataInit's: categorical fmuid and thlb, numeric au and age.
.landscapeFixture <- function(fmuid, thlb, au, age, nrows = 1) {
  ncols <- length(age) / nrows
  mk <- function(v) terra::rast(nrows = nrows, ncols = ncols, xmin = 0, xmax = ncols, ymin = 0, ymax = nrows, vals = v)
  f <- mk(match(fmuid, sort(unique(stats::na.omit(fmuid)))))
  levels(f) <- data.frame(value = seq_along(sort(unique(stats::na.omit(fmuid)))), fmuid = sort(unique(stats::na.omit(fmuid))))
  t <- mk(thlb + 1)
  levels(t) <- data.frame(value = 1:2, thlb = c(0, 1))
  s <- c(f, t, mk(au), mk(rep(1, length(age))), mk(age))
  names(s) <- c("fmuid", "thlb", "au", "blockid", "age")
  s
}
