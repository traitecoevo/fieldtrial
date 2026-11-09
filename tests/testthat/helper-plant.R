## plant's frozen testing copy of a model's trade-offs, as a maker: ref() is
## the closure at plant's coefficients, ref(B_Hv2 = -0.3) with an override.
## Skips on a plant without default_hyperpar(); the committed baseline
## (test-tradeoff-baseline.R) still checks the port there.
plant_frozen <- function(model) {
  if (!exists("default_hyperpar", envir = asNamespace("plant"), inherits = FALSE)) {
    testthat::skip("plant has no default_hyperpar() to compare against")
  }
  function(...) plant::default_hyperpar(model, ...)
}

tf24_grid <- function() {
  as.matrix(expand.grid(
    lma = c(0.05, 0.1978791, 0.4), rho = c(300, 608, 1100),
    omega = c(1e-5, 3.8e-5), K_s = c(0.05, 0.33577377016801868, 2),
    vcmax_25 = c(40, 96), jmax_25 = c(80, 157.44)))
}

ff16_grid <- function() {
  as.matrix(expand.grid(
    lma = c(0.08, 0.1978791, 0.3), rho = c(400, 608, 900),
    omega = 3.8e-5, narea = c(1e-3, 1.87e-3, 3e-3)))
}
