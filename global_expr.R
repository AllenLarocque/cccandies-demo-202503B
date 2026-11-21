# This is a global setupProject to run a minimal demo of a working SpaDES model with harvesting (using ws3)
# This includes scfm in order to add stochastic fire
# Authors: Allen Larocque, Ian Eddy
# Date Created: October 31 2025
# Modified:


# install Require and SpaDES.project
repos <- c("https://predictiveecology.r-universe.dev", getOption("repos"))
source("https://raw.githubusercontent.com/PredictiveEcology/pemisc/refs/heads/development/R/getOrUpdatePkg.R")
getOrUpdatePkg(c("Require", "SpaDES.project"), c("1.0.1.9003", "0.1.1.9037")) # only install/update if required

#getOrUpdatePkg(c("Require", "SpaDES.project","reticulate"), c("1.0.1.9003", "0.1.1.9037","1.43.0")) # only install/update if required

#Require::Require("reticulate")   # AL: Necessary to run the optimizer logic below; better fix?
Require::setLinuxBinaryRepo()

# Generic absolute path for anybody; but individual can change
#projectDir <- "~/projects/WS3/cccandies-demo-202503B/"
#dir.create(projectDir, recursive = TRUE, showWarnings = FALSE)
#setwd(projectDir)


################################################################################

## Comment out for batch runs:
# From here:
#######
#
# basenames = list("tsa41","tsa40")
# base.year = 2020
# horizon= 10
# period_length=10
# planning_period_freq = 10
# scheduler.mode = "optimize"
# times = list(start = 0, end = 200)
# .rep = "1_optimize"
# .cores = c("sbw")
#
#
# modules = c(
#   "PredictiveEcology/spades_ws3_dataInit@dev",
#   "PredictiveEcology/spades_ws3@dev",
#   "AllenLarocque/spades_ws3_landrAge@PE",
#   "AllenLarocque/scfm@development",
#   "AllenLarocque/spades_ws3_diagnostics@main"
#   #"PredictiveEcology/Biomass_borealDataPrep@development",
#   #"PredictiveEcology/Biomass_core@development",
#   #"PredictiveEcology/Biomass_regeneration@development",
#   #"ianmseddy/LandR_reforestation@master"
# )

#######
# To here


inSim <- SpaDES.project::setupProject(
  require = c("reticulate",
              "PredictiveEcology/scfmutils@development (>= 2.0.9.9003)",
              "terra"),

  ### Define local variables (spades_ws3 module parameters)

  shp.path = "gis/shp",    # path to GIS shape files
  tif.path = "tif",           # path to tifs within the input directory
  target.masks = list(c('? ? ? ?')), # do not modify. AL: I don't know what this is



  # Modifiable via expr.R. Defaults are defined below:
  basenames=basenames,                        # A list of 'basenames' to use. Depends on the datalad datastructure prepared by Greg Paradis and the UBC FRESH lab.
  base.year=base.year,                        # first year of harvest planning
  horizon=horizon,                            # The number of planning periods to include in optimization
  period_length=period_length,                # The length of time that WS3 bins in the optimization algorithm
  planning_period_freq=planning_period_freq,  # The number of years between planning events.
  scheduler.mode=scheduler.mode,              # Change these to set scheduler mode between 'areacontrol' and 'optimize'
  times=times,                                # Used in scfm and LandR. This determines how long the simulation will run
  .rep=.rep,                                  # Number of replicates. Not currently implemented
  .cores=.cores,                              # Which computer core to use. Not currently implemented
  modules=modules,                            # Which modules to include?
  fireMultiplier = fireMultiplier,

  # Defaults
  defaultDots = list(basenames = list("tsa41","tsa40"),
                     base.year = 2020,
                     horizon= 10,
                     period_length=10,
                     planning_period_freq = 10,
                     scheduler.mode = "optimize",
                     times = list(start = 0, end = 10),
                     .rep = "1_optimize",
                     .cores = c("sbw"),
                     fireMultiplier = 1.0,
                     modules=c("PredictiveEcology/spades_ws3_dataInit@dev",
                               "PredictiveEcology/spades_ws3@dev",
                               "AllenLarocque/spades_ws3_landrAge@PE",
                               "AllenLarocque/spades_ws3_diag_FRESH@main",
                               "AllenLarocque/scfm@development",
                               "AllenLarocque/spades_ws3_scfm_diag_FRESH@main")
                     ),

  target.scalefactors={                # This is how much to 'scale back' harvest, by proportion. This logic is here since it must be different formats depending on scheduler.mode selection
    if (scheduler.mode == "optimize") {
      py_dict(basenames, as.list(rep(1.0, length(basenames))))
    } else if (scheduler.mode == "areacontrol") {
      NULL
    }
  },
  ###

  useGit = "eliotmcintire",
  paths = list(modulePath = file.path("modules"),
               outputPath = file.path('output',.rep),
               projectPath = file.path(getwd()),
               inputPath = file.path('input',.rep),
               cachePath = file.path('cache')
               ),

  #options = list(spades.allowInitDuringSimInit = TRUE), # set to true to allow for the running of Init events during simInit
  # outputs = data.frame(objectName = "landscape"), # do not modify (AL: I'm not sure what this is for)
  params = list(
    .globals = list(
      .plots = "png",          # write figures to disk
      basenames = basenames,   # for LandR_age + ws3
      tif.path = tif.path,     # for LandR_age + ws3
      base.year = base.year,    # for LandR_age + ws3
      planning_period_freq = planning_period_freq
    ),
    spades_ws3_dataInit = list(
      GithubURL="git@github.com:UBC-FRESH/cccandies_demo_input.git",
      .saveInitialTime = 0,
      .saveInterval = 1,
      .saveObjects = c("landscape"),
      .savePath = file.path(paths$outputPath, "landscape")),
    spades_ws3 = list(basenames = basenames,
                      horizon = horizon,
                      enable.debugpy = FALSE,
                      base.year = base.year,
                      scheduler.mode = scheduler.mode,
                      target.scalefactors = target.scalefactors),
    scfmDataPrep = list(.useParallelFireRegimePolys = TRUE, #use Greg's cores
                        targetN = 1000), #unserious fire param during testing
    fireHarvestPlots = list(resInHA = NULL), # NULL means calculate from rasterToMatch
    scfmRegime = list(fireMultiplier = fireMultiplier)  # Multiplier to scale fire at parameter estimation (1.0 = normal, 2.0 = double, 0.0 = no fire). Scales targetBurnRate relative to observed data.
  ),
  packages = c("gert", "PredictiveEcology/LandR@development",
               "reticulate", "httr", "RCurl", "XML","bcdata",
               "PredictiveEcology/reproducible@AI (>= 2.1.2.9070)",
               "PredictiveEcology/SpaDES.core@box (>= 2.1.8.9013)"
  ),
  sppEquiv = {
    spp <- LandR::sppEquivalencies_CA[LandR %in% c("Pinu_con", "Pinu_ban",
                                                   "Pice_gla", "Pice_mar",
                                                   "Pice_eng", "Abie_las",
                                                   "Popu_tre", "Betu_pap"),]
    spp <- spp[LANDIS_test != "",]
    spp #change
  }
)

### Modifications required by scfm:
# (Only run if a module with 'scfm' in the name is in the module list)
if (any(grepl("scfm", inSim$modules, ignore.case = TRUE))) {
  # Manually add scfm modules to modulePath and module list:
  inSim$paths$modulePath <- c("modules", "modules/scfm/modules")
  inSim$modules <- setdiff(c(inSim$modules,
                          c("scfmDataPrep","scfmDiagnostics", "scfmIgnition", "scfmEscape", "scfmSpread")),
                      "scfm")

  # Add scfm params manually since setupProject strips them out
  inSim$params$scfmDataPrep$targetN <- 1000 #quick calibration while testing (at least 2K for real)
  inSim$params$scfmDataPrep$.useParallelFireRegimePolys = TRUE
}

###

# Run init:
#outInit<-do.call(SpaDES.core::simInit,inSim)


# debug(SpaDES.core:::.runModuleInputObjects)
#readySim <- do.call(SpaDES.core::simInit, inSim)
#outSim<-spades(readySim)

outSim <- do.call(SpaDES.core::simInitAndSpades, inSim)








# Diagnostics:

# What kind of plots will I want?

# Time series of fire and harvest
# Maps of fire, maps of harvest
# Cumulative fire; cumulative harvest
# Harvest: number of first-time harvest, second growth harvest, n-growth harvest
# Maps of these
# Time series of 'planned harvest that has been missed due to fire'


#source("R/simplePlot.R")
#plotFireWithHarvest(simOut) # Only works with a single basename right now

#names(simOut)
#simOut$harvestStats
#simOut$scfmSummaryDT
#plot(simOut$burnMap)  # What is this a map of exactly?







#####
# Working project notes:

# import pdb; pdb.set_trace() #put this chunk in to debug python
#to update ws3, pip install --upgrade ws3

#TODO: make harvestStats a data.table not a data.frame






