## Solar geometry for daily drivers, matching the day plant's TF24 rebuilds
## from noon values (plant branch experiment/618-daily-integral,
## inst/include/plant/models/tf24_diurnal.h). Time is plant's: years from
## 1 January of the run's first year, with the day of year 365 * frac(time).
## Hours are local solar time, so noon is 12.

#' Solar geometry of a day
#'
#' `solar_declination()` gives the sun's declination, and `solar_day()` the
#' terms of the sun's elevation through a day at a latitude: sin(elevation) at
#' solar hour `h` is `a + b * cos(pi * (h - 12) / 12)`, and the photoperiod is
#' where that is positive. These are the forms plant's TF24 uses when it
#' rebuilds a day from noon values, so drivers made here and the day plant
#' integrates share one sun.
#'
#' The declination is `asin(0.39785 * sin(...))`. plant's older R solar model
#' (kept for FF16's trade-offs) uses the inner expression as the angle itself,
#' which is about 0.6 degrees low at the solstices.
#'
#' @param time Time in years from 1 January, as plant counts it: the day of
#'   year is `365 * (time - floor(time))`.
#' @param latitude Latitude in degrees, south negative.
#' @return `solar_declination()`: radians. `solar_day()`: a data frame with
#'   columns `a`, `b` and `daylength` (hours), one row per `time`. A day with
#'   no sunrise or no sunset (polar day or night) is refused.
#' @export
#' @examples
#' solar_day(c(0, 0.5), latitude = -22.28)  # midsummer and midwinter at Alice Springs
solar_declination <- function(time) {
  x <- 2 * pi * (time - floor(time))
  asin(0.39785 * sin(4.869 + x + 0.03345 * sin(6.224 + x)))
}

#' @rdname solar_declination
#' @export
solar_day <- function(time, latitude) {
  if (length(latitude) != 1L || !is.finite(latitude) || abs(latitude) > 90) {
    stop("`latitude` must be one finite number of degrees in [-90, 90]",
         call. = FALSE)
  }
  phi <- latitude * pi / 180
  delta <- solar_declination(time)
  a <- sin(phi) * sin(delta)
  b <- cos(phi) * cos(delta)
  cos_sunrise <- -a / b
  polar <- !(cos_sunrise > -1 & cos_sunrise < 1)
  if (any(polar)) {
    stop(sprintf("No sunrise or no sunset at latitude %g on %d day(s), the first at time %g (polar day or night)",
                 latitude, sum(polar), time[which(polar)[1]]), call. = FALSE)
  }
  data.frame(a = a, b = b, daylength = 24 / pi * acos(cos_sunrise))
}

## The day's shortwave, relative to noon's, integrated over the photoperiod, in
## hours: the integral of sin(elevation(h)) / sin(elevation(12)) from sunrise
## to sunset. A noon value times this is the day's total in W m-2 h.
noon_equivalent_hours <- function(time, latitude) {
  d <- solar_day(time, latitude)
  half <- pi * d$daylength / 24
  (24 / pi) * (d$a * half + d$b * sin(half)) / (d$a + d$b)
}

#' Shortwave at solar noon from a daily mean, and back
#'
#' A day's shortwave follows the sun's elevation, scaled so that its noon value
#' is `SWdown_noon`; plant's TF24 rebuilds the day this way. These convert
#' between that noon value and the 24-hour mean the same day carries, so a day
#' rebuilt from `SWdown_noon` holds exactly the observed energy.
#'
#' @inheritParams solar_declination
#' @param SWdown_mean Shortwave averaged over 24 hours, W m-2.
#' @param SWdown_noon Shortwave at solar noon, W m-2.
#' @return The other quantity, W m-2.
#' @export
#' @examples
#' swdown_noon_from_mean(250, time = 0.05, latitude = -22.28)
swdown_noon_from_mean <- function(SWdown_mean, time, latitude) {
  SWdown_mean * 24 / noon_equivalent_hours(time, latitude)
}

#' @rdname swdown_noon_from_mean
#' @export
swdown_mean_from_noon <- function(SWdown_noon, time, latitude) {
  SWdown_noon * noon_equivalent_hours(time, latitude) / 24
}

#' Clear-sky shortwave
#'
#' Shortwave on a horizontal surface under a clear sky at a solar hour, for a
#' location- and season-dependent light driver where radiation was not
#' observed (traitecoevo/plant#701). The beam is `S0 * transmissivity^m` at air
#' mass `m = 1 / sin(elevation)`, projected onto the horizontal.
#'
#' This is an estimate of an upper bound, not of a real day: it has no clouds,
#' no diffuse light and no aerosol. Where a gridded product gives daily
#' radiation, use that through [swdown_noon_from_mean()] instead.
#'
#' @inheritParams solar_declination
#' @param hour Local solar hour; 12 is noon.
#' @param transmissivity Fraction of the beam that crosses one air mass,
#'   about 0.7 to 0.8 under clear skies.
#' @param S0 Shortwave outside the atmosphere, W m-2.
#' @return W m-2, zero when the sun is down.
#' @export
#' @examples
#' t <- (seq_len(365) - 0.5) / 365
#' plot(t, swdown_clear_sky(t, latitude = -22.28), type = "l")
swdown_clear_sky <- function(time, latitude, hour = 12, transmissivity = 0.75,
                             S0 = 1360) {
  if (length(transmissivity) != 1L || !(transmissivity > 0 && transmissivity <= 1)) {
    stop("`transmissivity` must be one number in (0, 1]", call. = FALSE)
  }
  d <- solar_day(time, latitude)
  sin_beta <- d$a + d$b * cos(pi * (hour - 12) / 12)
  ifelse(sin_beta > 0, S0 * transmissivity^(1 / pmax(sin_beta, 1e-12)) * sin_beta, 0)
}

#' Time in plant's convention for calendar dates
#'
#' Years from 1 January of `start_year`, placed at the middle of each day.
#' plant's TF24 reads the day of year as `365 * (time - floor(time))`, so
#' `start_year` must be the run's first calendar year for the seasons to line
#' up.
#'
#' @param date Dates, as `Date`.
#' @param start_year The calendar year at time 0.
#' @return Numeric times, in years.
#' @export
#' @examples
#' met_time(as.Date(c("2010-01-01", "2010-07-02", "2011-01-01")), 2010)
met_time <- function(date, start_year) {
  date <- as.Date(date)
  if (length(start_year) != 1L || !is.finite(start_year) ||
      start_year != round(start_year)) {
    stop("`start_year` must be one whole year", call. = FALSE)
  }
  year <- as.integer(format(date, "%Y"))
  yday <- as.integer(format(date, "%j"))
  (year - start_year) + (yday - 0.5) / (365 + is_leap(year))
}
