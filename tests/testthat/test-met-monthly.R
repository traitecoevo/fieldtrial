normals_example <- function() {
  n <- data.frame(month = 1:12,
    Tair_min = c(22, 21, 18, 13, 8, 5, 4, 6, 10, 15, 18, 21),
    Tair_max = c(36, 35, 32, 28, 23, 20, 19, 22, 27, 31, 34, 35),
    Precip_month = c(40, 45, 30, 15, 15, 12, 8, 7, 8, 20, 25, 40),
    SWdown_mean = c(310, 290, 255, 210, 170, 150, 165, 200, 245, 280, 300, 315),
    Wind = rep(3, 12),
    vapour_pressure = c(1.4, 1.5, 1.3, 1.0, 0.9, 0.8, 0.7, 0.7, 0.7, 0.9, 1.0, 1.2))
  n$Tair_mean <- (n$Tair_min + n$Tair_max) / 2
  n
}

test_that("normals become a valid mean year that keeps rainfall and radiation totals", {
  n <- normals_example()
  met <- met_from_monthly(n, latitude = -22.28, longitude = 133.25, elevation = 600)
  expect_silent(validate_met(met))
  expect_identical(nrow(met), 365L)
  expect_equal(met$date[c(1, 365)], as.Date(c("2001-01-01", "2001-12-31")))
  m <- as.integer(format(met$date, "%m"))
  expect_equal(as.numeric(tapply(met$Precip, m, sum)), n$Precip_month)
  expect_equal(as.numeric(tapply(met$SWdown_mean, m, mean)), n$SWdown_mean)
  expect_true(all(met$Tair_min <= met$Tair_mean & met$Tair_mean <= met$Tair_max))
  expect_equal(met$Psurf[1], 101.325 * (1 - 2.25577e-5 * 600)^5.25588)
  expect_setequal(attr(met, "filled"), c("Tair_noon", "VPD_noon", "VPD_amp", "Wind", "Psurf"))
})

test_that("noon temperature and VPD follow the day's cosine", {
  n <- normals_example()
  met <- met_from_monthly(n, latitude = -22.28)
  k <- 15  # mid-January: the month's own values
  expect_equal(met$Tair_mean[k], n$Tair_mean[1], tolerance = 0.05)
  half <- (met$Tair_max[k] - met$Tair_min[k]) / 2
  expect_equal(met$Tair_noon[k], met$Tair_mean[k] + half * cos(2 * pi * (12 - 14.5) / 24))
  ## VPD through the day rebuilt from the fitted noon value and amplitude
  ## stays close to e_s(T(h)) - e_a: one harmonic of a convex function.
  h <- seq(0.5, 23.5, by = 1)
  T_h <- met$Tair_mean[k] + half * cos(2 * pi * (h - 14.5) / 24)
  ## Day 15 lies between December's middle (day 350, wrapped to -15) and
  ## January's (day 16).
  e_a <- stats::approx(c(350 - 365, 16), c(1.2, 1.4), xout = 15)$y
  truth <- saturation_vapour_pressure(T_h) - e_a
  shape <- (1 + met$VPD_amp[k] * cos(2 * pi * (h - 14.5) / 24)) /
    (1 + met$VPD_amp[k] * cos(2 * pi * (12 - 14.5) / 24))
  expect_equal(met$VPD_noon[k] * shape, truth, tolerance = 0.05)
  ## The noon VPD is one the leaf accepts at the noon temperature.
  expect_true(all(met$VPD_noon < saturation_vapour_pressure(met$Tair_noon)))
})

test_that("a monthly series spans its months and years", {
  n <- normals_example()
  s <- rbind(cbind(year = 2010L, n), cbind(year = 2011L, n))
  met <- met_from_monthly(s, latitude = -22.28)
  expect_equal(met$date[c(1, nrow(met))], as.Date(c("2010-01-01", "2011-12-31")))
  expect_null(attr(met, "climatology_of"))
  expect_error(met_from_monthly(s[-5, ], latitude = 0), "consecutive months")
})

test_that("malformed monthly input is refused", {
  n <- normals_example()
  expect_error(met_from_monthly(n[-3, ], latitude = 0), "12 months")
  expect_error(met_from_monthly(cbind(n, rain = 1), latitude = 0), "Unknown monthly")
  bad <- n; bad$Wind[2] <- NA
  expect_error(met_from_monthly(bad, latitude = 0), "no missing")
  expect_error(met_from_monthly(n[c("month", "vapour_pressure")], latitude = 0),
               "needs Tair_mean")
})

test_that("a pulsed climatology warns, a splined one does not", {
  met <- met_from_monthly(normals_example(), latitude = -22.28)
  attr(met, "climatology_of") <- c(1970L, 2000L)
  expect_warning(apply_drivers(plant::Environment("TF24"), met,
                               drivers = c("SWdown", "rainfall")), "climatology")
  expect_no_warning(apply_drivers(plant::Environment("TF24"), met, rainfall = "spline",
                                  drivers = c("SWdown", "rainfall")))
})
