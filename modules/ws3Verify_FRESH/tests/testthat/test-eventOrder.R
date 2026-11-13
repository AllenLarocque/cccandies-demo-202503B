library(testthat)

# Regression test: collectStats read burnSummary[year == t] before scfmSpread's "burn" event
# of year t had run, so burned area was always 0 and burned biomass lagged by one year.
# collectStats must be scheduled with a later (higher) eventPriority than that burn event.

scheduledPriorities <- function(file, eventType) {
  exprs <- parse(file, keep.source = FALSE)
  out <- numeric(0)
  walk <- function(e) {
    if (is.call(e)) {
      if (identical(e[[1]], as.name("scheduleEvent")) &&
          any(vapply(as.list(e), identical, logical(1), eventType))) {
        out <<- c(out, if (is.null(e$eventPriority)) 5 else eval(e$eventPriority))
      }
      for (a in as.list(e)[-1]) if (!missing(a)) walk(a)
    }
  }
  for (e in exprs) walk(e)
  out
}

moduleFile <- normalizePath(test_path("..", "..", "ws3Verify_FRESH.R"))
scfmSpreadFile <- file.path(dirname(moduleFile), "..", "scfm", "modules", "scfmSpread",
                            "scfmSpread.R")

test_that("collectStats is scheduled after scfmSpread's burn event", {
  collectPrio <- scheduledPriorities(moduleFile, "collectStats")
  expect_length(collectPrio, 2)   # init and the re-schedule
  burnPrio <- if (file.exists(scfmSpreadFile)) {
    scheduledPriorities(scfmSpreadFile, "burn")
  } else {
    7.5                            # scfmSpread's burn priority when this test was written
  }
  expect_true(length(burnPrio) > 0)
  expect_true(all(collectPrio > max(burnPrio)))
})

test_that("makePlots is scheduled after collectStats, so plots include the last year", {
  plotPrio <- scheduledPriorities(moduleFile, "makePlots")
  expect_length(plotPrio, 2)
  expect_true(all(plotPrio > max(scheduledPriorities(moduleFile, "collectStats"))))
})
