#' Daily met table from monthly climate
#'
#' Turns monthly climate, either normals (one row per month) or a series (one
#' row per year and month), into the daily met table. Every monthly source in
#' fieldtrial (WorldClim, and later CRU TS and AGCD) goes through this, so they
#' share one set of assumptions:
#'
#' * **Daily values** are interpolated linearly between mid-month values,
#'   wrapping December to January for normals. Precipitation and shortwave are
#'   then rescaled month by month so each month keeps its total exactly;
#'   temperatures, vapour pressure and wind keep their mid-month values but not
#'   exactly their monthly means.
#' * **The day's temperature** follows one cosine between `Tair_min` and
#'   `Tair_max`, peaking at `peak_hour`; `Tair_noon` is read from it.
#' * **VPD** through the day is `e_s(T(h)) - e_a`, with the actual vapour
#'   pressure `e_a` constant over the day; `VPD_noon` and `VPD_amp` are the
#'   least-squares cosine fit to it that tower records get, bounded the same
#'   way.
#' * **Noon shortwave** is the noon value of a clear-sky-shaped day holding the
#'   daily mean ([swdown_noon_from_mean()]).
#' * **Pressure** is from `elevation` by the standard atmosphere, if given.
#'
#' The columns estimated by an assumption rather than read from the source are
#' named in `attr(, "filled")`.
#'
#' @param monthly A data frame with `month` (1 to 12), optionally `year`, and
#'   any of `Tair_mean`, `Tair_max`, `Tair_min` (degC), `Precip_month` (mm per
#'   month), `SWdown_mean` (W m-2, 24-hour mean), `Wind` (m s-1, 24-hour mean)
#'   and `vapour_pressure` (kPa). Without `year`, it must be the 12 months of a
#'   climatology; with it, consecutive months.
#' @param latitude,longitude Site location, degrees.
#' @param elevation Site elevation, m, for `Psurf`; `NULL` leaves `Psurf` out.
#' @param peak_hour Local solar hour of the daily temperature and VPD peak.
#' @param max_amp,vpd_floor Bounds on the VPD amplitude and noon VPD (kPa), as
#'   in [met_daily_from_subdaily()].
#' @param source Recorded as `attr(, "source")`.
#' @return A daily met table (see [met_schema()]). Normals are dated in the
#'   non-leap year 2001 and carry `climatology_of` if `monthly` has that
#'   attribute.
#' @export
#' @examples
#' normals <- data.frame(month = 1:12,
#'   Tair_min = c(22, 21, 18, 13, 8, 5, 4, 6, 10, 15, 18, 21),
#'   Tair_max = c(36, 35, 32, 28, 23, 20, 19, 22, 27, 31, 34, 35),
#'   Precip_month = c(40, 45, 30, 15, 15, 12, 8, 7, 8, 20, 25, 40),
#'   SWdown_mean = c(310, 290, 255, 210, 170, 150, 165, 200, 245, 280, 300, 315),
#'   vapour_pressure = c(1.4, 1.5, 1.3, 1.0, 0.9, 0.8, 0.7, 0.7, 0.7, 0.9, 1.0, 1.2))
#' normals$Tair_mean <- (normals$Tair_min + normals$Tair_max) / 2
#' met <- met_from_monthly(normals, latitude = -22.28, longitude = 133.25, elevation = 600)
#' head(met)
met_from_monthly <- function(monthly, latitude, longitude = NA_real_,
                             elevation = NULL, peak_hour = 14.5,
                             max_amp = 0.99, vpd_floor = 0.01, source = NULL) {
  if (!is.data.frame(monthly) || !"month" %in% names(monthly)) {
    stop("`monthly` must be a data frame with a `month` column", call. = FALSE)
  }
  known <- c("year", "month", "Tair_mean", "Tair_max", "Tair_min", "Precip_month",
             "SWdown_mean", "Wind", "vapour_pressure")
  unknown <- setdiff(names(monthly), known)
  if (length(unknown) > 0L) {
    stop("Unknown monthly column(s): ", paste(unknown, collapse = ", "), call. = FALSE)
  }
  for (col in setdiff(names(monthly), c("year", "month"))) {
    if (!is.numeric(monthly[[col]]) || anyNA(monthly[[col]])) {
      stop(sprintf("`%s` must be numeric with no missing values", col), call. = FALSE)
    }
  }
  climatology <- !"year" %in% names(monthly)
  if (climatology) {
    if (!identical(as.integer(monthly$month), 1:12)) {
      stop("Monthly normals need the 12 months in order, 1 to 12", call. = FALSE)
    }
    year <- rep(2001L, 12)
  } else {
    year <- as.integer(monthly$year)
    index <- year * 12L + as.integer(monthly$month) - 1L
    if (any(diff(index) != 1L)) {
      stop("A monthly series needs consecutive months, in order", call. = FALSE)
    }
  }
  month <- as.integer(monthly$month)
  first <- as.Date(sprintf("%d-%02d-01", year[1], month[1]))
  last_start <- as.Date(sprintf("%d-%02d-01", year[length(year)], month[length(month)]))
  last <- seq(last_start, by = "month", length.out = 2)[2] - 1
  date <- seq(first, last, by = "day")
  ndays <- as.integer(format(seq(first, by = "month", length.out = length(month) + 1)[-1] - 1, "%d"))
  ## Day index (from the first date) of each month's middle.
  month_start <- cumsum(c(0, ndays[-length(ndays)]))
  mid <- month_start + (ndays + 1) / 2
  day <- seq_along(date)
  which_month <- findInterval(day - 1, month_start)

  daily <- function(v) {
    if (climatology) {
      x <- c(mid[12] - 365, mid, mid[1] + 365)
      y <- c(v[12], v, v[1])
    } else {
      x <- mid
      y <- v
    }
    stats::approx(x, y, xout = day, rule = 2)$y
  }
  ## Rescale a daily series so each month keeps its total.
  keep_monthly_total <- function(d, monthly_mean) {
    got <- tapply(d, which_month, mean)
    factor <- ifelse(got > 0, monthly_mean / got, 0)
    d * factor[as.character(which_month)]
  }

  out <- data.frame(date = date)
  t <- met_time(date, as.integer(format(date[1], "%Y")))
  filled <- character(0)
  has <- function(col) col %in% names(monthly)

  if (has("SWdown_mean")) {
    out$SWdown_mean <- unname(keep_monthly_total(daily(monthly$SWdown_mean), monthly$SWdown_mean))
    out$SWdown_noon <- swdown_noon_from_mean(out$SWdown_mean, t, latitude)
  }
  temps <- c("Tair_mean", "Tair_max", "Tair_min")
  if (all(vapply(temps, has, logical(1)))) {
    tmean <- daily(monthly$Tair_mean)
    tmax <- daily(monthly$Tair_max)
    tmin <- daily(monthly$Tair_min)
    half_range <- (tmax - tmin) / 2
    out$Tair_noon <- tmean + half_range * cos(2 * pi * (12 - peak_hour) / 24)
    out$Tair_mean <- tmean
    out$Tair_max <- tmax
    out$Tair_min <- tmin
    filled <- c(filled, "Tair_noon")
    if (has("vapour_pressure")) {
      e_a <- daily(monthly$vapour_pressure)
      hours <- seq(0.5, 23.5, by = 1)
      z <- cos(2 * pi * (hours - peak_hour) / 24)
      ## Hour by day: VPD over each day.
      T_h <- outer(z, half_range) + rep(tmean, each = length(hours))
      vpd_h <- saturation_vapour_pressure(T_h) - rep(e_a, each = length(hours))
      zc <- z - mean(z)
      slope <- colSums(zc * vpd_h) / sum(zc^2)
      c0 <- colMeans(vpd_h) - slope * mean(z)
      b <- bound_vpd(c0, ifelse(c0 > 0, slope / c0, NA_real_), peak_hour,
                     max_amp, vpd_floor)
      out$VPD_noon <- b$noon
      out$VPD_amp <- b$amp
      attr(out, "amp_clamped") <- b$amp_clamped
      attr(out, "vpd_floored") <- b$vpd_floored
      filled <- c(filled, "VPD_noon", "VPD_amp")
    }
  } else if (has("vapour_pressure")) {
    stop("VPD needs Tair_mean, Tair_max and Tair_min as well as vapour_pressure",
         call. = FALSE)
  }
  if (has("Precip_month")) {
    rate <- monthly$Precip_month / ndays
    out$Precip <- unname(keep_monthly_total(daily(rate), rate))
  }
  if (has("Wind")) {
    out$Wind <- daily(monthly$Wind)
    filled <- c(filled, "Wind")
  }
  if (!is.null(elevation)) {
    if (length(elevation) != 1L || !is.finite(elevation)) {
      stop("`elevation` must be one number of metres", call. = FALSE)
    }
    out$Psurf <- rep(pressure_from_elevation(elevation), nrow(out))
    filled <- c(filled, "Psurf")
  }

  attr(out, "latitude") <- latitude
  attr(out, "longitude") <- longitude
  attr(out, "vpd_peak_hour") <- peak_hour
  attr(out, "filled") <- filled
  attr(out, "source") <- source
  if (climatology) attr(out, "climatology_of") <- attr(monthly, "climatology_of")
  validate_met(out)
  out
}

## Surface pressure, kPa, at elevation z m in the standard atmosphere.
pressure_from_elevation <- function(z) {
  101.325 * (1 - 2.25577e-5 * z)^5.25588
}
