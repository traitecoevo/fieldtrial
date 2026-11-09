## plant's own trade-off function of that name, or skip if plant no longer
## has it. The committed baseline (test-tradeoff-baseline.R) covers the port
## after that.
plant_reference <- function(name) {
  ns <- asNamespace("plant")
  if (!exists(name, envir = ns, inherits = FALSE)) {
    testthat::skip(sprintf("plant has no %s to compare against", name))
  }
  get(name, envir = ns)
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
