test_that("declination follows the seasons", {
  ## Day of year d sits at time (d - 0.5) / 365.
  expect_equal(solar_declination((172 - 0.5) / 365) * 180 / pi, 23.44, tolerance = 0.01)
  expect_equal(solar_declination((355 - 0.5) / 365) * 180 / pi, -23.44, tolerance = 0.01)
  expect_lt(abs(solar_declination((80 - 0.5) / 365)), 0.01)
  expect_equal(solar_declination(0.3), solar_declination(5.3), tolerance = 1e-14)
})

test_that("days are twelve hours at the equator and refused at the poles", {
  expect_equal(solar_day(c(0.1, 0.6), 0)$daylength, c(12, 12), tolerance = 1e-12)
  d <- solar_day(c(0, 0.5), -22.28)
  expect_gt(d$daylength[1], 13)
  expect_lt(d$daylength[2], 11)
  expect_error(solar_day(0.47, 80), "polar day or night")
  expect_error(solar_day(0, c(10, 20)), "one finite number")
})

test_that("noon and daily-mean shortwave convert exactly, both ways", {
  t <- c(0.02, 0.3, 0.55, 0.9)
  for (lat in c(-35, -22.28, 0, 45)) {
    ## The day's shape integrated numerically from sunrise to sunset, in hours.
    d <- solar_day(t, lat)
    hours <- vapply(seq_along(t), function(k) {
      f <- function(h) (d$a[k] + d$b[k] * cos(pi * (h - 12) / 12)) / (d$a[k] + d$b[k])
      stats::integrate(f, 12 - d$daylength[k] / 2, 12 + d$daylength[k] / 2,
                       rel.tol = 1e-12)$value
    }, numeric(1))
    expect_equal(noon_equivalent_hours(t, lat), hours, tolerance = 1e-10)
    expect_equal(swdown_mean_from_noon(swdown_noon_from_mean(200, t, lat), t, lat),
                 rep(200, length(t)))
  }
})

test_that("clear-sky shortwave is zero at night and peaks in local summer", {
  expect_identical(swdown_clear_sky(0.3, -22.28, hour = 0), 0)
  noon <- swdown_clear_sky(c(0.02, 0.5), -22.28)
  expect_gt(noon[1], noon[2])
  expect_lt(max(noon), 1360)
  expect_error(swdown_clear_sky(0, 0, transmissivity = 1.5), "transmissivity")
})

test_that("calendar dates map to plant's time at the middle of each day", {
  d <- as.Date(c("2010-01-01", "2010-12-31", "2011-01-01", "2012-12-31"))
  expect_equal(met_time(d, 2010), c(0.5 / 365, 364.5 / 365, 1 + 0.5 / 365, 2 + 365.5 / 366))
  expect_error(met_time(d, 2010.5), "whole year")
})
