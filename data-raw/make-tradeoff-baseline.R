## Writes tests/testthat/fixtures/tradeoff-baseline.rds: plant's own trade-off
## output on a fixed trait grid, so fieldtrial's port can be checked against
## plant even after plant's copy changes or goes.
##
## Run from the package root, against the plant recorded in
## .plant-interface-version:
##   Rscript data-raw/make-tradeoff-baseline.R
##
## The strategy argument is a plain list holding the one strategy value the
## trade-offs read (FF16's k_I), and every trait is a column of the grid, so the
## baseline does not depend on plant's C++ defaults.
library(plant)

grids <- list(
  TF24 = as.matrix(expand.grid(
    lma = c(0.05, 0.1978791, 0.4), rho = c(300, 608, 1100),
    omega = c(1e-5, 3.8e-5), K_s = c(0.05, 0.33577377016801868, 2),
    vcmax_25 = c(40, 96), jmax_25 = c(80, 157.44))),
  FF16 = as.matrix(expand.grid(
    lma = c(0.08, 0.1978791, 0.3), rho = c(400, 608, 900),
    omega = 3.8e-5, narea = c(1e-3, 1.87e-3, 3e-3))))
strategy <- list(pars = list(k_I = 0.5))

baseline <- list(
  plant_ref = system("git -C ../plant rev-parse --short HEAD", intern = TRUE),
  plant_version = as.character(packageVersion("plant")),
  strategy = strategy,
  grids = grids,
  TF24 = plant::make_TF24_hyperpar()(grids$TF24, strategy, filter = FALSE),
  FF16 = plant::make_FF16_hyperpar()(grids$FF16, strategy, filter = FALSE),
  FF16_latitude_30 = plant::make_FF16_hyperpar(latitude = 30)(
    grids$FF16, strategy, filter = FALSE))
saveRDS(baseline, "tests/testthat/fixtures/tradeoff-baseline.rds", version = 3)
