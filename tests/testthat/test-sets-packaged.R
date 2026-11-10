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
  expect_equal(pars$hmat, 2.5)
  ## The stem curve's P50 is the proxy, through the trade-off at the default
  ## K_s; the root curve's directly.
  expect_equal(pars$stem_P50, 6.7, tolerance = 1e-12)
  expect_equal(pars$root_P50, 6.7)
  expect_equal(sum(set$env$get_soil_layer_widths()), 1.0)
  expect_null(set$events)
  expect_match(set$meta$tradeoff_coefficients$B_Hv1$source, "^PROXY")
})

test_that("mulga_delta shares mulga_alice_springs's species and differs in site", {
  delta <- parameter_set("mulga_delta", drivers = FALSE)
  alice <- parameter_set("mulga_alice_springs", drivers = FALSE)
  expect_identical(delta$p$strategies[[1]]$pars, alice$p$strategies[[1]]$pars)
  ## Values and their sources, not just the built parameters.
  for (block in c("traits", "pars", "tradeoff_coefficients")) {
    expect_identical(delta$meta[[block]], alice$meta[[block]], label = block)
  }
  ## The monitoring site's location is published to 0.1 degree only.
  for (x in c(delta$meta$site$latitude, delta$meta$site$longitude)) {
    expect_equal(x, round(x, 1))
  }
  ## No Alice Springs soil carried over: plant's default column.
  default <- plant::Environment("TF24")
  expect_identical(delta$env$get_soil_layer_widths(), default$get_soil_layer_widths())
  expect_identical(delta$env$get_soil_water_state(), default$get_soil_water_state())
  expect_null(delta$meta$environment)
})

test_that("the alpine ash set carries its site values and proxies", {
  set <- parameter_set("alpine_ash_tumbarumba", drivers = FALSE)
  pars <- set$p$strategies[[1]]$pars
  expect_equal(pars$lma, 1 / 4.85, tolerance = 1e-5)
  expect_equal(pars$vcmax_25, 81.5)
  expect_equal(pars$jmax_25, 194.6)
  ## E. regnans stem P50 scaled by the two species' leaf P50s.
  expect_equal(pars$stem_P50, 4.98 * 3.42 / 3.21, tolerance = 1e-5)
  expect_equal(pars$root_P50, 4.98 * 3.42 / 3.21, tolerance = 1e-5)
  expect_equal(pars$hmat, 23.51)
  ## The set's graded 2 m profile, not plant's default 1.5 m column.
  expect_identical(set$env$get_soil_layer_widths(), soil_widths_graded(2.0, 5, 0.02))
  expect_match(set$meta$tradeoff_coefficients$B_Hv1$source, "^DERIVED PROXY")
  expect_match(set$meta$pars$hmat$source, "^DERIVED")
})
