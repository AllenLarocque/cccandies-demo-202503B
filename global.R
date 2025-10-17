# minimal demo of a working SpaDES model with harvesting (using ws3)
# minimal demo of a working SpaDES model with harvesting (using ws3)
repos <- c("https://predictiveecology.r-universe.dev", getOption("repos"))
source("https://raw.githubusercontent.com/PredictiveEcology/pemisc/refs/heads/development/R/getOrUpdatePkg.R")
getOrUpdatePkg(c("Require", "SpaDES.project"), c("1.0.1.9003", "0.1.1.9037")) # only install/update if required

# Require::Install("PredictiveEcology/Require@hasHEAD (>=0.1.1.9019)", install = "force")
# Require::Require("PredictiveEcology/reproducible@AI (HEAD)")

Require::setLinuxBinaryRepo()

#Sys.setenv(RETICULATE_PYTHON=".venv/bin/python")

################################################################################


################################################################################
# setwd("~/projects")
out <- SpaDES.project::setupProject(

  ### Define local variables (spades_ws3 module parameters)
  base.year = 2020,           # first year of harvest planning
  basenames = list("tsa41"),  # the 'basenames' to run the simulation
  horizon = 12,               # The number of planning periods.
  period_length = 10,         # The number of years between planning periods. Sept 2025: Greg says 'don't change this unless you know what you are doing'
  tif.path = "tif",           # do not modify (works with included dataset)
  scheduler.mode = "areacontrol", # currently 'areacontrol' and 'optimize' is implemented
  target.masks = list(c('? ? ? ?')), # do not modify. AL: I don't know what this is

  target.scalefactors = NULL, # AL: I don't know what this is
  # target.scalefactors <- py_dict(basenames, list(rep(1.0, times = length(basenames))))
  shp.path = "gis/shp",    # path to GIS shape files
  ###

  useGit = "eliotmcintire",
  paths = list(projectPath = "cccandies-demo-202503B",
               modulePath = 'modules',
               inputPath = 'input',
               outputPath = 'output',
               cachePath = 'cache'),
  modules = c(
    "UBC-FRESH/cccandies_demo_input@master", #add this as a submodule to ws3_dataInit
    "PredictiveEcology/spades_ws3_dataInit@main",
    "PredictiveEcology/spades_ws3@dev",
    "ianmseddy/spades_ws3_landrAge@master"
    # "PredictiveEcology/scfm@development",
    # "PredictiveEcology/Biomass_borealDataPrep@development",
    # "PredictiveEcology/Biomass_core@development",
    # "PredictiveEcology/Biomass_regeneration@development",
    # "ianmseddy/LandR_reforestation@master"
  ),

  times = list(start = 0, end = 99),                    # used in scfm and LandR
  options = list(spades.allowInitDuringSimInit = TRUE), # set to true to allow for the running of Init events during simInit
  # outputs = data.frame(objectName = "landscape"), # do not modify
  params = list(
    .globals = list(
      .plots = "png",          # write figures to disk
      basenames = basenames,   # for LandR_age + ws3
      tif.path = tif.path,     # for LandR_age + ws3
      base.year = base.year    # for LandR_age + ws3
    ),
    spades_ws3_dataInit = list(
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
               "reticulate", "httr", "RCurl", "XML",
               "PredictiveEcology/reproducible@AI (>= 2.1.2.9056)",
               "PredictiveEcology/SpaDES.core@box (>= 2.1.5.9005)"
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

# fix modules
# out$modules <- c(
#   grep("scfm", out$modules, invert = TRUE, value = TRUE),
#   "scfmDataPrep", "scfmDiagnostics",
#   "scfmIgnition", "scfmEscape", "scfmSpread"
#   )
out$modules <- out$modules[grep("cccandies_demo_input", out$modules, invert = TRUE)]   # Fix this

if (!dir.exists("modules/cccandies_demo_input/hdt")) {
  if (!length(list.files("modules/cccandies_demo_input/hdt")) > 0) {
    #the above could be repeated for tif, gis,
  system("cd modules/cccandies_demo_input && datalad get input . -r")
  }
}
out$paths$modulePath <- c("modules", "modules/scfm/modules")
out$loadOrder <- unlist(out$modules)

#TODO: discuss with Greg making candies_demo_ws3 a submodule of spades_ws3_dataPrep

# import pdb; pdb.set_trace() #put this chunk in to debug python
#to update ws3, pip install --upgrade ws3
#reticulate::import("ws3")$`__version__`

#TODO: make harvestStats a data.table not a data.frame


simOut <- do.call(SpaDES.core::simInitAndSpades, out)






# (Pdb) print(df_targets)
# vcut   abrn  cflw_acut_e  cgen_vcut_e  cgen_abrn_e
# tsa   year
# tsa08 2020  1600000  13000         0.05         0.01         0.01
# tsa16 2020  1800000   1262         0.05         0.01         0.01
# tsa24 2020  4000000    494         0.05         0.01         0.01
# tsa40 2020  2000000   1632         0.05         0.01         0.01
# tsa41 2020  1200000    336         0.05         0.01         0.01

# tsa   year  AAC     per-year    ha/burned/year



# cflw_acut_e  cgen_vcut_e
#these are the constraints around the annual area cut expressed as proportions and  +/- in m3/cut/year
#so cut 336 wit subsequent cuts +/- 5% (or 4 to 6% of that)
#cgen_abrn_e is a burn constraint


