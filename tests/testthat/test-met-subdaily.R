## A half-hourly record made from the model the fit assumes, stamped in local
## standard time: each step's solar hour is worked out as the fit does, and the
## record evaluated there.
synthetic_subdaily <- function(lat, lon, utc_offset, days = 40, noon_sw = 950,
                               c0 = 2, amp = 0.5, peak = 14.5) {
  start <- as.POSIXct("2015-01-01 00:00:00", tz = "UTC")
  time <- start + seq(0, by = 1800, length.out = days * 48)
  utc <- as.numeric(time) + 900 - utc_offset * 3600
  doy <- as.integer(format(as.POSIXct(utc, origin = "1970-01-01", tz = "UTC"), "%j"))
  solar <- as.POSIXct(utc + lon / 15 * 3600 + equation_of_time(doy) * 60,
                      origin = "1970-01-01", tz = "UTC")
  date <- as.Date(format(solar, "%Y-%m-%d"))
  hour <- as.numeric(format(solar, "%H")) + as.numeric(format(solar, "%M")) / 60
  d <- solar_day(met_time(date, 2015), lat)
  shape <- pmax(d$a + d$b * cos(pi * (hour - 12) / 12), 0) / (d$a + d$b)
  data.frame(time = time,
             SWdown = noon_sw * shape,
             VPD = c0 * (1 + amp * cos(2 * pi * (hour - peak) / 24)),
             Tair = 25 + 5 * cos(2 * pi * (hour - 15) / 24),
             Precip = ifelse(format(solar, "%H") == "06", 0.5, 0),
             Wind = 3, Psurf = 94, CO2air = 410)
}

test_that("the fit recovers the noon values a day was built from", {
  x <- synthetic_subdaily(lat = -22.28, lon = 133.25, utc_offset = 9.5)
  met <- met_daily_from_subdaily(x, -22.28, 133.25, utc_offset = 9.5)
  expect_silent(validate_met(met))
  ## Partial days at either end of the record are dropped.
  expect_gte(nrow(met), 38L)
  ## Half-hourly sampling of the day's shape: the noon value is recovered to
  ## the error of a midpoint sum over the photoperiod.
  expect_equal(met$SWdown_noon, rep(950, nrow(met)), tolerance = 2e-3)
  ## A solar day holding 49 half-hours samples one hour twice, which biases
  ## the least-squares cosine slightly.
  expect_equal(met$VPD_amp, rep(0.5, nrow(met)), tolerance = 1e-3)
  expect_equal(met$VPD_noon, rep(2 * (1 + 0.5 * cos(2 * pi * (12 - 14.5) / 24)), nrow(met)),
               tolerance = 1e-3)
  expect_equal(met$Tair_max, rep(30, nrow(met)), tolerance = 1e-3)
  expect_equal(met$Precip, rep(1, nrow(met)))
  expect_equal(met$Psurf, rep(94, nrow(met)))
  expect_identical(attr(met, "latitude"), -22.28)
  expect_identical(attr(met, "amp_clamped"), 0L)
})

test_that("out-of-range amplitudes and saturated noons are corrected and counted", {
  x <- synthetic_subdaily(lat = 10, lon = 0, utc_offset = 0, days = 5, amp = 0.5)
  ## Night-peaking VPD: a negative amplitude.
  x$VPD <- 2 * (1 - 0.3 * cos(2 * pi * (as.numeric(format(x$time, "%H")) - 14.5) / 24))
  met <- met_daily_from_subdaily(x, 10, 0, utc_offset = 0)
  expect_true(all(met$VPD_amp == 0))
  expect_gt(attr(met, "amp_clamped"), 0L)
  x$VPD <- 0.001
  met <- met_daily_from_subdaily(x, 10, 0, utc_offset = 0)
  expect_true(all(met$VPD_noon == 0.01))
  expect_gt(attr(met, "vpd_floored"), 0L)
})

test_that("irregular records are refused", {
  x <- synthetic_subdaily(lat = 10, lon = 0, utc_offset = 0, days = 3)
  expect_error(met_daily_from_subdaily(x[-5, ], 10, 0, 0), "regular")
  expect_error(met_daily_from_subdaily(x["SWdown"], 10, 0, 0), "`time` column")
})
