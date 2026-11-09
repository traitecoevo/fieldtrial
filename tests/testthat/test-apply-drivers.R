met_two_years <- function() {
  date <- seq(as.Date("2010-01-01"), as.Date("2011-12-31"), by = "day")
  n <- length(date)
  k <- seq_len(n)
  met <- data.frame(date = date,
                    SWdown_noon = 800 + 150 * cos(2 * pi * k / 365),
                    VPD_noon = 1.2 + 0.6 * cos(2 * pi * k / 365),
                    VPD_amp = rep(0.4, n),
                    Tair_mean = 22 + 6 * cos(2 * pi * k / 365),
                    Precip = ifelse(k %% 9 == 0, 12, 0),
                    Wind = rep(2.5, n), Psurf = rep(95, n), CO2air = rep(415, n))
  attr(met, "latitude") <- -22.28
  met
}

test_that("each driver reads back the table's value at its day", {
  env <- plant::Environment("TF24")
  met <- met_two_years()
  res <- apply_drivers(env, met)
  t <- met_time(met$date, 2010)
  i <- c(1, 100, 400, 730)
  expect_equal(env$extrinsic_drivers_evaluate_range("SWdown", t[i]), met$SWdown_noon[i])
  ## The first and last days hold to the table's ends.
  expect_equal(env$extrinsic_drivers_evaluate_range("SWdown", c(0, 2)),
               met$SWdown_noon[c(1, nrow(met))])
  expect_equal(env$extrinsic_drivers_evaluate_range("atm_vpd", t[i]), met$VPD_noon[i])
  expect_equal(env$extrinsic_drivers_evaluate_range("atm_kpa", t[i]), met$Psurf[i])
  expect_equal(env$extrinsic_drivers_evaluate_range("wind_speed", t[i]), met$Wind[i])
  ## ppm to Pa at the site's pressure: 415 ppm at 95 kPa.
  expect_equal(env$extrinsic_drivers_evaluate_range("ca", t[i]), rep(415e-6 * 95e3, 4))
  ## leaf_temp is plant's unless asked for.
  expect_equal(env$extrinsic_drivers_evaluate_range("leaf_temp", t[i]), rep(25, 4))
  expect_true(all(c("SWdown", "atm_vpd", "ca", "rainfall") %in% res$drivers$driver))
})

test_that("rainfall becomes one pulse per wet day, and the driver goes to zero", {
  env <- plant::Environment("TF24")
  met <- met_two_years()
  expect_no_warning(res <- apply_drivers(env, met))
  wet <- met$Precip > 0
  expect_identical(length(res$events$time), sum(wet))
  expect_identical(unique(res$events$type), "resource_pulse")
  expect_equal(sum(unlist(res$events$params)), sum(met$Precip) / 1000)
  expect_equal(res$events$time, met_time(met$date[wet], 2010))
  expect_identical(env$extrinsic_drivers_evaluate("rainfall", 1), 0)
})

test_that("a spline rainfall carries each day's total as that day's rate", {
  env <- plant::Environment("TF24")
  met <- met_two_years()
  res <- apply_drivers(env, met, rainfall = "spline")
  expect_null(res$events)
  t <- met_time(met$date, 2010)
  expect_equal(env$extrinsic_drivers_evaluate_range("rainfall", t[c(9, 18)]),
               rep(12 / 1000 * 365, 2))
})

test_that("leaf temperature is set only when asked for, and VPD is checked against it", {
  env <- plant::Environment("TF24")
  met <- met_two_years()
  apply_drivers(env, met, drivers = c("leaf_temp", "atm_vpd"))
  t <- met_time(met$date, 2010)
  expect_equal(env$extrinsic_drivers_evaluate("leaf_temp", t[200]), met$Tair_mean[200])

  hot <- met
  hot$VPD_noon[50] <- 5  # e_s at 25 degC is about 3.17 kPa
  expect_error(apply_drivers(plant::Environment("TF24"), hot), "VPD_noon is outside.*2010-02-19")
  hot$VPD_noon[50] <- 0
  expect_error(apply_drivers(plant::Environment("TF24"), hot), "VPD_noon is outside")
})

test_that("absent columns leave plant's values and say so", {
  env <- plant::Environment("TF24")
  met <- met_two_years()[c("date", "SWdown_noon")]
  res <- apply_drivers(env, met)
  expect_identical(res$drivers$from[res$drivers$driver == "atm_vpd"],
                   "plant default (column absent)")
  expect_equal(env$extrinsic_drivers_evaluate("atm_vpd", 0.5), 1)
  expect_error(apply_drivers(env, met, drivers = "SWdownx"), "Unknown driver")
})

test_that("`until` keeps a pulse at that time and drops the next", {
  met <- met_two_years()
  t <- met_time(met$date, 2010)
  wet <- which(met$Precip > 0)
  cut <- t[wet[3]]
  res <- apply_drivers(plant::Environment("TF24"), met, until = cut)
  expect_identical(length(res$events$time), 3L)
  expect_identical(max(res$events$time), cut)
})

test_that("a table without site attributes, or without rainfall, still applies", {
  met <- met_two_years()
  attr(met, "latitude") <- NULL
  res <- apply_drivers(plant::Environment("TF24"), met, drivers = c("SWdown", "atm_vpd"))
  expect_null(res$events)
  expect_false(any(grepl("rainfall|latitude", res$drivers$driver)))
  expect_identical(res$drivers$driver, c("SWdown", "atm_vpd"))
})

test_that("a short TF24 stand runs on the drivers and pulses", {
  skip_on_cran()
  p <- plant::scm_base_parameters("TF24")
  p$max_patch_lifetime <- 1
  p <- plant::add_strategies(p, plant::trait_matrix(0.0825, "lma"),
                             tradeoffs("TF24"), birth_rate = 1,
                             keep_existing = FALSE)
  env <- plant::Environment("TF24")
  res <- apply_drivers(env, met_two_years(), until = p$max_patch_lifetime)
  expect_true(all(res$events$time <= 1))
  ev <- plant::events(plant::events_default(p), res$events)
  out <- plant::run_scm(p, res$env, plant::control(), events = ev)
  expect_true(all(is.finite(out$offspring_production)))
})
