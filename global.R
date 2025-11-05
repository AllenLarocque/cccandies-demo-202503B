# This is a global setupProject to run a minimal demo of a working SpaDES model with harvesting (using ws3)
# This includes scfm in order to add stochastic fire
# Authors: Allen Larocque, Ian Eddy
# Date Created: October 31 2025
# Modified:

repos <- c("https://predictiveecology.r-universe.dev", getOption("repos"))
source("https://raw.githubusercontent.com/PredictiveEcology/pemisc/refs/heads/development/R/getOrUpdatePkg.R")
getOrUpdatePkg(c("Require", "SpaDES.project","reticulate"), c("1.0.1.9003", "0.1.1.9037","1.43.0")) # only install/update if required

# Require::Install("PredictiveEcology/Require@hasHEAD (>=0.1.1.9019)", install = "force")
# Require::Require("PredictiveEcology/rep4roducible@AI (HEAD)")
Require::Require("reticulate")   # AL: Necessary to run the optimizer logic below; better fix?
Require::setLinuxBinaryRepo()

################################################################################



out <- SpaDES.project::setupProject(

  ### Define local variables (spades_ws3 module parameters)
  basenames = list("tsa41","tsa40"),  # This can be a list of basenames backed by G. Paradis' datalad repo. Implemented in Oct 2025: TSA41,40,24,16 and 08. More than one can be run at once.
  scheduler.mode = "optimize", # Change these to set scheduler mode between 'areacontrol' and 'optimize'
  #scheduler.mode<- "areacontrol",
  target.scalefactors={                # these are different depending on scheduler.mode selection
  if (scheduler.mode == "optimize") {
    py_dict(basenames, as.list(rep(1.0, length(basenames))))
  } else if (scheduler.mode == "areacontrol") {
    NULL
  }
  },

  base.year = 2020,           # first year of harvest planning
  horizon = 10,               # The number of planning periods to include in optimization.
  period_length = 10,         # The number of years between planning periods. Sept 2025: Greg says 'don't change this unless you know what you are doing'
  times = list(start = 0, end = 99),                    # used in scfm and LandR. This determines how long the simulation will run

  shp.path = "gis/shp",    # path to GIS shape files
  tif.path = "tif",           # path to tifs within the input directory
  target.masks = list(c('? ? ? ?')), # do not modify. AL: I don't know what this is

  ###

  useGit = "eliotmcintire",
  paths = list(projectPath = file.path(getwd()),
               modulePath = file.path("modules"),
               inputPath = file.path('input'),
               outputPath = file.path('output'),
               cachePath = file.path('cache')),
  modules = c(
    "PredictiveEcology/spades_ws3_dataInit@dev",
    "PredictiveEcology/spades_ws3@dev",
    "AllenLarocque/spades_ws3_landrAge@PE",
    "AllenLarocque/scfm@development"
    #"PredictiveEcology/Biomass_borealDataPrep@development",
    #"PredictiveEcology/Biomass_core@development",
    #"PredictiveEcology/Biomass_regeneration@development",
    #"ianmseddy/LandR_reforestation@master"
  ),


  #options = list(spades.allowInitDuringSimInit = TRUE), # set to true to allow for the running of Init events during simInit
  # outputs = data.frame(objectName = "landscape"), # do not modify (AL: I'm not sure what this is for)
  params = list(
    .globals = list(
      .plots = "png",          # write figures to disk
      basenames = basenames,   # for LandR_age + ws3
      tif.path = tif.path,     # for LandR_age + ws3
      base.year = base.year    # for LandR_age + ws3
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
                        targetN = 1000) #unserious fire param during testing
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
# Manually add scfm modules to modulePath and module list:
 out$paths$modulePath <- c("modules", "modules/scfm/modules")
 out$modules <- setdiff(c(out$modules,
                        c("scfmDataPrep","scfmDiagnostics", "scfmIgnition", "scfmEscape", "scfmSpread")),
                    "scfm")
#
# # Add scfm params manually since setupProject stips them out
 out$params$scfmDataPrep$targetN <- 1000 #quick calibration while testing (at least 2K for real)
 out$params$scfmDataPrep$.useParallelFireRegimePolys = TRUE

###

#simInit<-do.call(SpaDES.core::simInit,out)

# debug(SpaDES.core:::.runModuleInputObjects)
simOut <- do.call(SpaDES.core::simInitAndSpades, out)


# Diagnostics:
source("R/simplePlot.R")
plotFireWithHarvest(simOut)

simOut$harvestStats

simOut
#####
# Working project notes:

# import pdb; pdb.set_trace() #put this chunk in to debug python
#to update ws3, pip install --upgrade ws3

#TODO: make harvestStats a data.table not a data.frame




