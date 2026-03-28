# This is a global setupProject to run a minimal demo of a working SpaDES model with harvesting (using ws3)
# This includes scfm in order to add stochastic fire
# Authors: Allen Larocque, Ian Eddy
# Date Created: October 31 2025
# Modified:

## Currently WIP global pending

# Bootstrap setup:
repos <- c("https://predictiveecology.r-universe.dev", getOption("repos"))     # Define a list of repos; add r-universe to the beginning of the repo list
source("https://raw.githubusercontent.com/PredictiveEcology/pemisc/refs/heads/development/R/getOrUpdatePkg.R")   # Source the getOrUpdatePkg function
getOrUpdatePkg(c("Require", "SpaDES.project","reticulate"),
               c("1.0.1.9003", "0.1.1.9037","1.43.0")) # This checks if the version is newer than the one defined in the list, and only installs/updates if it is not

# Install SpaDES.project if needed and related packages:
if (!require("SpaDES.project")){
  Require::Require(c("SpaDES.project", "SpaDES.core", "reproducible"),
                   repos = repos,
                   dependencies = TRUE)
}

Require::setLinuxBinaryRepo()  # Use pre-compiled binary packages for Linux instead of compiling from source. This should be faster, be more stable, and work better without root access.

pkgload::load_all("~/projects/scfmutils")
################################################################################

## TEMP: For single run testing, use this:
## Comment out for batch runs using experiment3 or experiment.R!
# From here:
#######

basenames = list("tsa41","tsa40")
base.year = 2020
horizon= 20
period_length=10
planning_period_freq = 10 # TEMP: Keep the same as period_length for now
scheduler.mode = "optimize"
times = list(start = 0, end = 200)
.rep = "1_optimize"
.cores = c("sbw")
n_ws3_workers=10L
fireMultiplier = 1.5


modules = c(
  "AllenLarocque/spades_ws3_dataInit@dev",
  "AllenLarocque/spades_ws3@dev",
  "AllenLarocque/spades_ws3_landrAge@PE",
  "AllenLarocque/scfm@development"                 # TEMP: this scfm branch contains 'fire multiplier' features
  #"AllenLarocque/spades_ws3_diag_FRESH@main",        # This module contains diagnostic plots for the WS3_FRESH module
  #"AllenLarocque/spades_ws3_scfm_diag_FRESH@main"    # This module contains diagnostic plots for the WS3_FRESH_scfm module
  #"PredictiveEcology/Biomass_borealDataPrep@development",
  #"PredictiveEcology/Biomass_core@development",
  #"PredictiveEcology/Biomass_regeneration@development",
  #"ianmseddy/LandR_reforestation@master"
)

#######
# To here


simin <- SpaDES.project::setupProject(
  require = c("reticulate",
              "PredictiveEcology/scfmutils@development (>= 2.0.9.9003)",
              "terra"),

  # Paths:
  #useGit = "eliotmcintire",
  useGit = "allenlarocque",
  paths = list(modulePath = file.path("modules"),
               outputPath = file.path('output',.rep),
               projectPath = file.path(getwd()),
               inputPath = file.path('input',.rep),
               cachePath = file.path('cache')
  ),

  ### Define local variables (spades_ws3 module parameters)
  shp.path = "gis/shp",    # path to GIS shape files, relative to the input directory
  tif.path = "tif",           # path to tifs, relative to the input directory
  target.masks = list(c('? ? ? ?')), # do not modify. AL: I don't know what this is

  # The below are modifiable in expr.R. Defaults are defined in defaultDots below:
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
  fireMultiplier = fireMultiplier,            # SCFM 'fire multiplier'. Scale fire up (>1) or down (<1) relative to empirical burn rate.
  n_ws3_workers=n_ws3_workers,                # The number of workers for WS3. Pass as an integer

  # Defaults
  defaultDots = list(basenames = list("tsa41","tsa40"),
                     base.year = 2020,
                     horizon= 10,
                     period_length=10,
                     planning_period_freq = 10,
                     scheduler.mode = "optimize",
                     times = list(start = 0, end = 100),
                     .rep = "1_optimize",
                     .cores = c("sbw"),
                     fireMultiplier = 1.0,
                     n_ws3_workers=1L,
                     modules=c("PredictiveEcology/spades_ws3_dataInit@dev",
                               "PredictiveEcology/spades_ws3@dev",
                               "AllenLarocque/spades_ws3_landrAge@PE",
                               "AllenLarocque/scfm@master")
                               #"AllenLarocque/spades_ws3_diag_FRESH@main",
                               #"AllenLarocque/spades_ws3_scfm_diag_FRESH@main")
  ),
  target.scalefactors={                # This is how much to 'scale back' harvest, by proportion. The 'if' logic is here since it must be different formats depending on scheduler.mode selection
    if (scheduler.mode == "optimize") {
      py_dict(basenames, as.list(rep(1.0, length(basenames))))
    } else if (scheduler.mode == "areacontrol") {
      NULL
    }
  },

  # Params:
  params = list(
    .globals = list(.plots = "png",           # write figures to disk
                    basenames = basenames,    # for LandR_age + ws3
                    tif.path = tif.path,      # for LandR_age + ws3
                    base.year = base.year,    # for LandR_age + ws3
                    planning_period_freq = planning_period_freq,
                    saveFM = TRUE,                      # Enable saving of ws3 forestmodel (fm) objects
                    saveFM.path = "fm_checkpoints"      # path to save fm objects
    ),
    spades_ws3_dataInit = list(GithubURL="git@github.com:UBC-FRESH/cccandies_demo_input.git",
                               .saveInitialTime = 0,
                               .saveInterval = 1,
                               .saveObjects = c("landscape"),
                               .savePath = file.path(paths$outputPath, "landscape"),
                               merge.approach = c("mosaic")),   # What terra function to use for merging landscape rasters? Use terra:mosaic if neighbouring cells blend incorrectly; terra:merge may be faster. Mosaic is default.
    spades_ws3 = list(basenames = basenames,
                      horizon = horizon,
                      enable.debugpy = FALSE,
                      base.year = base.year,
                      scheduler.mode = scheduler.mode,
                      target.scalefactors = target.scalefactors,
                      workers=n_ws3_workers,
                      saveFM = TRUE,                    # Enable saving of fm objects
                      saveFM.path = "fm_checkpoints"),
    spades_ws3_diag_FRESH = list(.plotInitialTime = 0,
                                 .plotInterval = 1),
    scfmDataPrep = list(.useParallelFireRegimePolys = TRUE, #use Greg's cores
                        targetN = 1000), #unserious fire param during testing
    fireHarvestPlots = list(resInHA = NULL), # NULL means calculate from rasterToMatch
    scfmRegime = list(fireMultiplier = fireMultiplier)  # Multiplier to scale fire at parameter estimation (1.0 = normal, 2.0 = double, 0.0 = no fire). Scales targetBurnRate relative to observed data.
  ),
  packages = c("gert", "PredictiveEcology/LandR@development",
               "reticulate", "httr", "RCurl", "XML","bcdata",
               "PredictiveEcology/SpaDES.core@development (>= 3.0.3.9003)",
               "PredictiveEcology/reproducible (>= 3.0.0)"
               #,"AllenLarocque/scfmutils@cursor"
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
if (any(grepl("scfm", simin$modules, ignore.case = TRUE))) {
  # Manually add scfm modules to modulePath and module list:
  simin$paths$modulePath <- c("modules", "modules/scfm/modules")
  simin$modules <- setdiff(c(simin$modules,
                             c("scfmDataPrep","scfmDiagnostics", "scfmIgnition", "scfmEscape", "scfmSpread")),
                           "scfm")

  # Add scfm params manually since setupProject strips them out
  simin$params$scfmDataPrep$targetN <- 1000 #quick calibration while testing (at least 2K for real)
  simin$params$scfmDataPrep$.useParallelFireRegimePolys = TRUE
}

###

# Run init:
#outInit<-do.call(SpaDES.core::simInit,simin)

# debug(SpaDES.core:::.runModuleInputObjects)
#readySim <- do.call(SpaDES.core::simInit, simin)
#sim<-spades(readySim)

simout <- do.call(SpaDES.core::simInitAndSpades, simin)





# Caution, this takes abotu a half hour:
#SpaDES.core::saveSimList(outSim, file = "outSim.rds",files=F)

# To see what's in the ython environment namespace, use:
#reticulate::py$`__dict__`

# Q: save outputs from every forestmodel instance?
# This way I can query how the plan at time x diverges from what happens


# py$fm is the forestmodel instance
#py$fm
## Can access it with functions like this:
##py$fm$inventory(period=5)
#py$fm$operable_area(period=5,acode=10)

#py$fm$nthemes()
#py$fm$tree

##landscape_data<-values(outSim$landscape)
#print(landscape_data)



# Prepare plotting data
#outSim$harvestStats
#outSim$burnSummary





# WS3_plots
# Harvested area
# Harvested volume
# Growing stock
# Age class

# WS3_scfm plots
# Burned area
# Burned volume
# Growing stock
# Age classes




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

#TODO: make harvestStats a data.table not a data.frame






