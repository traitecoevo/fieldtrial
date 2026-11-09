## The sets shipped in the package: each must load against the plant fieldtrial
## is pinned to, reach plant with every value it names, and say where each value
## came from. Drivers are left out here, since they need a download.

test_that("every packaged set loads without its drivers", {
  for (name in list_sets()) {
    expect_s3_class(parameter_set(name, drivers = FALSE), "fieldtrial_set")
  }
})

test_that("the Alice Springs mulga set carries its traits and its hydraulic proxy", {
  set <- parameter_set("mulga_alice_springs", drivers = FALSE)
  pars <- set$p$strategies[[1]]$pars
  expect_equal(pars$lma, 0.4579142)
  expect_equal(pars$rho, 950)
  expect_equal(pars$vcmax_25, 174)
  expect_equal(pars$theta, 1.57e-3)
  expect_equal(pars$hmat, 4.700879)
  ## The stem curve's P50 is the proxy, through the trade-off at the default
  ## K_s; the root curve's directly.
  expect_equal(pars$stem_P50, 6.7, tolerance = 1e-12)
  expect_equal(pars$root_P50, 6.7)
  expect_equal(sum(set$env$get_soil_layer_widths()), 1.0)
  expect_null(set$events)
  expect_match(set$meta$tradeoff_coefficients$B_Hv1$source, "^PROXY")
})
