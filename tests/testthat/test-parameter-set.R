test_that("a set builds all four of run_scm's inputs from its file", {
  set <- parameter_set(test_set())
  expect_s3_class(set, "fieldtrial_set")
  expect_length(set$p$strategies, 1L)
  pars <- set$p$strategies[[1]]$pars
  ## Traits and the parameters their trade-offs derive.
  expect_identical(pars$lma, 0.0825)
  expect_identical(pars$rho, 700)
  derived <- tradeoffs("TF24")(cbind(lma = 0.0825, rho = 700), set$p$strategy_default,
                               filter = FALSE)
  expect_identical(pars$k_l, unname(derived[1, "k_l"]))
  expect_identical(pars$r_s, unname(derived[1, "r_s"]))
  ## A parameter set directly.
  expect_identical(pars$hmat, 8)
  ## The set's trade-offs travel with its Parameters.
  if ("hyperpar" %in% names(set$p)) {
    expect_identical(plant::param_hyperpar(set$p)(cbind(lma = 0.1), set$p$strategy_default),
                     set$tradeoffs(cbind(lma = 0.1), set$p$strategy_default))
  }
  expect_identical(set$p$max_patch_lifetime, 1)
  expect_identical(set$p$strategies[[1]]$birth_rate_y, 2)
  ## Soil, environment field, drivers, control.
  expect_identical(set$env$get_soil_number_of_depths(), 4L)
  expect_equal(sum(set$env$get_soil_layer_widths()), 1.5)
  expect_identical(set$env$f_PAR, 0.48)
  expect_equal(set$env$extrinsic_drivers_evaluate("SWdown", 0.5),
               set$met$SWdown_noon[set$met$date == as.Date("2001-07-02")], tolerance = 1e-6)
  expect_identical(set$ctrl$GSS_tol_abs, 0.002)
  ## Pulses within the run only.
  expect_true(all(set$events$time <= 1))
  expect_length(set$events$time, 36L)
})

test_that("a set runs", {
  skip_on_cran()
  out <- run_set(parameter_set(test_set()))
  expect_true(all(is.finite(out$offspring_production)))
})

test_that("a set built against another plant model version is refused", {
  path <- test_set(function(x) sub("TF24@v[0-9.]+", "TF24@v1", x))
  expect_error(parameter_set(path), "built against TF24@v1")
  expect_s3_class(parameter_set(path, check = FALSE), "fieldtrial_set")
  expect_s3_class(check_set(parameter_set(path, check = FALSE), allow_version_drift = TRUE),
                  "fieldtrial_set")
})

test_that("keys that reach nothing are refused, not dropped", {
  refuse <- function(from, to, msg) {
    path <- test_set(function(x) sub(from, to, x, fixed = TRUE))
    expect_error(parameter_set(path), msg)
  }
  ## A trait the trade-offs derive, an unknown trait, a derived parameter set
  ## directly, a value with no source.
  refuse("  rho: {value: 700", "  k_l: {value: 700", "not a trait, not a parameter the trade-offs derive")
  refuse("  rho: {value: 700", "  rhoo: {value: 700", "rhoo is not a parameter of TF24")
  refuse("  hmat: {value: 8", "  r_l: {value: 8", "would be overwritten")
  refuse("  hmat: {value: 8, source: \"test fixture\"}", "  hmat: {value: 8}", "hmat has no source")
  ## Unknown keys elsewhere.
  refuse("run: {max_patch_lifetime: 1", "run: {max_patch_life: 1", "max_patch_life is not one of")
  refuse("control: {GSS_tol_abs", "control: {GSS_tolerance", "GSS_tolerance is not a field of plant's Control")
  refuse("    f_PAR: {value", "    fPAR: {value", "fPAR is not a field of TF24's environment")
  refuse("    theta: {value", "    thetas: {value", "thetas is not depth, n_layers")
  refuse("provenance:", "provenanse:", "provenanse is not schema")
  refuse("schema: 1", "schema: 2", "has schema 2")
  ## Values add_strategies() would overwrite, a driver option nobody reads, a
  ## surface-layer width with no profile.
  refuse("run: {max_patch_lifetime: 1", "run: {node_schedule_times: 1, max_patch_lifetime: 1",
         "node_schedule_times is not one of")
  refuse("  repeat: true", "  repeat: true\n  repaet: true", "repaet is not one of")
  refuse("    depth: {value: 1.5, source: \"test fixture\"}",
         "    top: {value: 0.01, source: \"test fixture\"}", "needs both depth and n_layers")
  refuse("  source: met_file", "  source: silo", "must be \"worldclim\" or \"met_file\"")
})

test_that("a met record must start on 1 January and cover the run", {
  path <- test_set(function(x) sub("  repeat: true", "  repeat: false", x, fixed = TRUE))
  long <- sub("max_patch_lifetime: 1,", "max_patch_lifetime: 3,", readLines(path), fixed = TRUE)
  writeLines(long, path)
  expect_error(parameter_set(path), "covers 1 years and the run is 3")
  met <- utils::read.csv(file.path(dirname(path), "test_met.csv"))
  utils::write.csv(met[-1, ], file.path(dirname(path), "test_met.csv"), row.names = FALSE)
  writeLines(sub("max_patch_lifetime: 3,", "max_patch_lifetime: 0.5,", long, fixed = TRUE), path)
  expect_error(parameter_set(path), "must start on 1 January")
})

test_that("TF24t's thermal fields are set through the strategy block", {
  path <- test_set(function(x) {
    x <- sub("model: TF24$", "model: TF24t", x)
    c(x, "strategy:", "  k_mat: {value: 0.005, source: \"test fixture\"}")
  }, model = "TF24t")
  set <- parameter_set(path)
  expect_identical(set$p$strategies[[1]]$k_mat, 0.005)
  bad <- test_set(function(x) c(x, "strategy:", "  control: {value: 1, source: \"x\"}"))
  expect_error(parameter_set(bad), "not a numeric field of TF24_Strategy")
})

test_that("sets are found by name or path", {
  expect_type(list_sets(), "character")
  expect_error(parameter_set("no_such_set"), "No set \"no_such_set\"")
})

test_that("a set's soil parameters reach plant once per layer", {
  ## plant keeps per-layer soil parameters with no getter, so the call is
  ## checked on its way in, then made.
  real <- plant::set_tf24_soil
  seen <- NULL
  local_mocked_bindings(
    set_tf24_soil = function(env, ...) { seen <<- list(...); real(env, ...) },
    .package = "plant")
  parameter_set(test_set(), drivers = FALSE)
  expect_identical(seen$soil_moist_sat, rep(0.4, 4))
  expect_length(seen$widths, 4L)
  expect_identical(seen$theta, 0.3)
  expect_null(seen$K_sat)

  ## Every soil parameter, given once for the column, reaches plant per layer.
  seen <- NULL
  env <- plant::Environment("TF24")
  apply_soil(env, list(
    depth = list(value = 1.2, source = "x"), n_layers = list(value = 3, source = "x"),
    K_sat = list(value = 50, source = "x"), a_psi = list(value = 2e-3, source = "x"),
    n_psi = list(value = 5, source = "x"), soil_moist_sat = list(value = 0.38, source = "x"),
    theta = list(value = 0.2, source = "x")))
  expect_identical(seen$K_sat, rep(50, 3))
  expect_identical(seen$a_psi, rep(2e-3, 3))
  expect_identical(seen$n_psi, rep(5, 3))
  expect_identical(seen$soil_moist_sat, rep(0.38, 3))
  expect_identical(seen$theta, 0.2)
})
