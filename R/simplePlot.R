plotFireWithHarvest <- function(sim, resInHA = NULL) {
  if (is.null(resInHA)) {
    resInHA = as.integer(prod(res(sim$rasterToMatch))/1e4)
  }
  fire <- sim$burnSummary                                       # Bring in the fire data
  fireByYear <- fire[, .(area = sum(areaBurned)), .(year)]      # Aggregate by taking the sum for every year across the landscae
  fireByYear[, source := "fire"]                                # add a 'source' column

  harvest <- data.table::copy(as.data.table(sim$harvestStats))  # Bring in the harvest stats data
  harvest[, area := ws3_harvestArea_pixels * resInHA]           # Calculate the area harvested by multiplying the pixes by the res
  harvest[, source := "harvest"]                                # Add a 'source' column
  plotData <- rbind(harvest, fireByYear, fill = TRUE)           # Combine the two and make a new df.


  # Plot it:
  p1<-ggplot2::ggplot(plotData, ggplot2::aes(x = year, y = area, col = source)) +
    ggplot2::geom_line() +
    ggplot2::geom_smooth(method = "lm", se = FALSE) +
    ggplot2::scale_color_manual(values = c("red", "darkgreen")) +
    ggplot2::labs(
      y = "area disturbed (ha)",
      title = paste(
        "Basenames:",
        paste(unlist(sim@params$spades_ws3$basenames), collapse = ", "),
        "; planning_period_freq = ",
        sim@params$spades_ws3$planning_period_freq
      )
    )

SpaDES.core::Plots(data=p1,
                   types = c("png", "screen","object"),
                   filename="~/projects/WS3/cccandies-demo-202503B/output/figures/Fire_Harvest_TimeSeries",
                   )


}
