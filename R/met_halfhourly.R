#' Daily met table from half-hourly or hourly records
#'
#' Aggregates a tower or reanalysis record to the daily met table, fitting the
#' noon values and VPD amplitude plant's TF24 rebuilds a day from:
#'
#' * `SWdown_noon` is the noon value of a clear-sky-shaped day holding the
#'   day's observed shortwave energy ([swdown_noon_from_mean()]), so the day
#'   plant rebuilds integrates to what was measured.
#' * `VPD_amp` and `VPD_noon` come from a least-squares fit of
#'   `VPD(h) = c0 * (1 + A * cos(2 * pi * (h - vpd_peak_hour) / 24))` to the
#'   day's record, in local solar time.
#' * `Tair_noon` comes from the same fit applied to air temperature (with no
#'   amplitude bound); the day's mean, maximum and minimum are kept too.
#' * Precipitation is the day's total; wind and CO2 their means while the sun
#'   is up; pressure its mean.
#'
#' Records are put into days by local solar time, worked out from the
#' timestamps' fixed offset from UTC, the longitude and the equation of time.
#' A day is kept only if it is complete (a solar day may hold one step more or
#' fewer than 24 clock hours), so the partial days at each end of a record are
#' dropped.
#'
#' Two corrections keep the table inside what plant accepts, and are counted in
#' the result's attributes: an amplitude outside `[0, max_amp]` (a day whose
#' VPD peaks at night, say) is clamped, and a noon VPD below `vpd_floor` is
#' raised to it, since the leaf refuses a saturated atmosphere.
#'
#' @param x A data frame with a `time` column (`POSIXct`, or anything
#'   `as.POSIXct()` reads, in local standard time) and any of `SWdown`
#'   (W m-2), `Tair` (degC), `VPD` (kPa), `Precip` (mm per step), `Wind`
#'   (m s-1), `Psurf` (kPa) and `CO2air` (ppm).
#' @param latitude,longitude Site location, degrees; south and west negative.
#' @param utc_offset Hours the timestamps are ahead of UTC (Alice Springs
#'   standard time: 9.5). Daylight saving is not followed.
#' @param timestamp Whether `time` marks the `"start"`, `"middle"` or `"end"`
#'   of each step. FLUXNET's `TIMESTAMP_START` is the start.
#' @param vpd_peak_hour Local solar hour of the daily VPD peak.
#' @param max_amp,vpd_floor Bounds applied to the VPD amplitude and the noon
#'   VPD (kPa).
#' @return A daily met table (see [met_schema()]) with attributes `latitude`,
#'   `longitude`, `vpd_peak_hour`, `filled` (empty: every column is from the
#'   record), `amp_clamped` and `vpd_floored` (the days corrected).
#' @export
met_daily_from_subdaily <- function(x, latitude, longitude, utc_offset,
                                    timestamp = c("start", "middle", "end"),
                                    vpd_peak_hour = 14.5, max_amp = 0.99,
                                    vpd_floor = 0.01) {
  timestamp <- match.arg(timestamp)
  if (!is.data.frame(x) || !"time" %in% names(x)) {
    stop("`x` must be a data frame with a `time` column", call. = FALSE)
  }
  for (a in c("latitude", "longitude", "utc_offset", "vpd_peak_hour")) {
    v <- get(a)
    if (length(v) != 1L || !is.finite(v)) stop(sprintf("`%s` must be one number", a), call. = FALSE)
  }
  ## The clock reading, whatever zone a POSIXct carries: local standard time.
  time <- if (inherits(x$time, "POSIXct")) {
    as.POSIXct(format(x$time, "%Y-%m-%d %H:%M:%S"), tz = "UTC")
  } else {
    as.POSIXct(x$time, tz = "UTC")
  }
  if (anyNA(time)) stop("`time` has missing or unreadable values", call. = FALSE)
  step <- unique(round(diff(as.numeric(time))))
  if (length(step) != 1L || !(step %in% c(1800, 3600))) {
    stop("`time` must be regular half-hourly or hourly steps", call. = FALSE)
  }
  offset_s <- c(start = 0.5, middle = 0, end = -0.5)[[timestamp]] * step
  ## Seconds of local solar time: to UTC, then by longitude and the equation
  ## of time.
  utc <- as.numeric(time) + offset_s - utc_offset * 3600
  doy <- as.integer(format(as.POSIXct(utc, origin = "1970-01-01", tz = "UTC"), "%j"))
  solar_s <- utc + longitude / 15 * 3600 + equation_of_time(doy) * 60
  solar <- as.POSIXct(solar_s, origin = "1970-01-01", tz = "UTC")
  date <- as.Date(format(solar, "%Y-%m-%d"))
  hour <- as.numeric(format(solar, "%H")) + as.numeric(format(solar, "%M")) / 60 +
    as.numeric(format(solar, "%S")) / 3600

  ## A solar day is not exactly 24 clock hours (the equation of time drifts),
  ## so a complete day can hold one step more or less than the clock count.
  per_day <- 86400 / step
  counts <- table(date)
  days <- as.Date(names(counts))[abs(as.integer(counts) - per_day) <= 1]
  if (length(days) == 0L) stop("no complete day in the record", call. = FALSE)
  keep <- date %in% days
  idx <- split(which(keep), date[keep])
  days <- as.Date(names(idx))

  t <- met_time(days, as.integer(format(days[1], "%Y")))
  geom <- solar_day(t, latitude)
  out <- data.frame(date = days)
  day_mean <- function(v, sel = NULL) {
    vapply(seq_along(idx), function(k) {
      i <- idx[[k]]
      if (!is.null(sel)) i <- i[sel[[k]]]
      mean(v[i])
    }, numeric(1))
  }
  sun_up <- lapply(seq_along(idx), function(k) {
    h <- hour[idx[[k]]]
    geom$a[k] + geom$b[k] * cos(pi * (h - 12) / 12) > 0
  })

  amp_clamped <- vpd_floored <- 0L
  if ("SWdown" %in% names(x)) {
    sw <- pmax(x$SWdown, 0)
    out$SWdown_mean <- day_mean(sw)
    out$SWdown_noon <- swdown_noon_from_mean(out$SWdown_mean, t, latitude)
  }
  if ("VPD" %in% names(x)) {
    fit <- t(vapply(idx, function(i) {
      fit_vpd_cosine(hour[i], x$VPD[i], vpd_peak_hour)
    }, numeric(2)))
    b <- bound_vpd(unname(fit[, 1]), unname(fit[, 2]), vpd_peak_hour,
                   max_amp, vpd_floor)
    out$VPD_noon <- b$noon
    out$VPD_amp <- b$amp
    amp_clamped <- b$amp_clamped
    vpd_floored <- b$vpd_floored
  }
  if ("Tair" %in% names(x)) {
    tfit <- t(vapply(idx, function(i) {
      z <- cos(2 * pi * (hour[i] - vpd_peak_hour) / 24)
      zc <- z - mean(z)
      slope <- sum(zc * (x$Tair[i] - mean(x$Tair[i]))) / sum(zc^2)
      c(mean(x$Tair[i]) - slope * mean(z), slope)
    }, numeric(2)))
    out$Tair_noon <- unname(tfit[, 1] + tfit[, 2] * cos(2 * pi * (12 - vpd_peak_hour) / 24))
    out$Tair_mean <- day_mean(x$Tair)
    out$Tair_max <- vapply(idx, function(i) max(x$Tair[i]), numeric(1), USE.NAMES = FALSE)
    out$Tair_min <- vapply(idx, function(i) min(x$Tair[i]), numeric(1), USE.NAMES = FALSE)
  }
  if ("Precip" %in% names(x)) {
    out$Precip <- vapply(idx, function(i) sum(pmax(x$Precip[i], 0)), numeric(1), USE.NAMES = FALSE)
  }
  if ("Wind" %in% names(x)) out$Wind <- day_mean(x$Wind, sun_up)
  if ("Psurf" %in% names(x)) out$Psurf <- day_mean(x$Psurf)
  if ("CO2air" %in% names(x)) out$CO2air <- day_mean(x$CO2air, sun_up)
  rownames(out) <- NULL

  attr(out, "latitude") <- latitude
  attr(out, "longitude") <- longitude
  attr(out, "vpd_peak_hour") <- vpd_peak_hour
  attr(out, "filled") <- character(0)
  attr(out, "amp_clamped") <- amp_clamped
  attr(out, "vpd_floored") <- vpd_floored
  out
}

## Least-squares fit of VPD(h) = c0 * (1 + A * cos(2 pi (h - peak) / 24)):
## returns c(c0, A). NA when the day has a missing value.
fit_vpd_cosine <- function(hour, vpd, peak) {
  if (anyNA(vpd)) return(c(NA_real_, NA_real_))
  z <- cos(2 * pi * (hour - peak) / 24)
  zc <- z - mean(z)
  slope <- sum(zc * (vpd - mean(vpd))) / sum(zc^2)
  c0 <- mean(vpd) - slope * mean(z)
  c(c0, if (c0 > 0) slope / c0 else NA_real_)
}

## Keep a fitted VPD cosine inside what plant accepts: amplitude in
## [0, max_amp], noon value at least vpd_floor. Returns the noon value, the
## amplitude, and how many days each correction touched.
bound_vpd <- function(c0, amp, peak, max_amp, vpd_floor) {
  clamp <- !is.na(amp) & (amp < 0 | amp > max_amp)
  amp <- pmin(pmax(amp, 0), max_amp)
  noon <- c0 * (1 + amp * cos(2 * pi * (12 - peak) / 24))
  floor_it <- !is.na(noon) & noon < vpd_floor
  list(noon = pmax(noon, vpd_floor), amp = amp,
       amp_clamped = sum(clamp), vpd_floored = sum(floor_it))
}

## Equation of time, minutes (Spencer 1971 form): apparent minus mean solar
## time, within about a quarter of an hour over the year.
equation_of_time <- function(doy) {
  B <- 2 * pi * (doy - 1) / 365
  229.18 * (0.000075 + 0.001868 * cos(B) - 0.032077 * sin(B) -
              0.014615 * cos(2 * B) - 0.040849 * sin(2 * B))
}
