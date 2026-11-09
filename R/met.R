## The canonical daily met table every source adapter produces and
## apply_drivers() reads. One row per day, consecutive days, no missing values.

met_columns <- data.frame(
  column = c("date", "SWdown_noon", "SWdown_mean", "VPD_noon", "VPD_amp",
             "Tair_mean", "Tair_max", "Tair_min", "Precip", "Wind", "Psurf",
             "CO2air"),
  units = c("date", "W m-2", "W m-2", "kPa", "1", "degC", "degC", "degC",
            "mm d-1", "m s-1", "kPa", "ppm"),
  lower = c(NA, 0, 0, 0, 0, -60, -60, -60, 0, 0, 40, 100),
  upper = c(NA, 1400, 600, 15, 1, 60, 60, 60, 1000, 60, 110, 2000),
  meaning = c("calendar day",
              "shortwave at solar noon, scaled so the rebuilt day holds the observed energy",
              "shortwave averaged over 24 hours",
              "vapour pressure deficit at solar noon",
              "relative amplitude of the daily VPD cosine, in [0, 1)",
              "mean air temperature", "maximum air temperature",
              "minimum air temperature", "precipitation total",
              "daytime mean wind speed", "surface air pressure",
              "atmospheric CO2"),
  stringsAsFactors = FALSE)

#' The daily met table
#'
#' Every climate source in fieldtrial produces the same daily table, and
#' [apply_drivers()] turns it into plant's drivers. `met_schema()` describes its
#' columns; `validate_met()` checks a table against it and returns it, or stops
#' saying what is wrong.
#'
#' The table holds **noon values**, not daytime means: plant's TF24 reads
#' `SWdown` and `atm_vpd` as their values at solar noon and rebuilds the day
#' from them, with a VPD amplitude and the latitude. Only `date` is required;
#' a source supplies the columns it can. Site metadata travel as attributes:
#' `latitude`, `longitude` and `vpd_peak_hour` (local solar time of the VPD
#' peak), and `filled`, naming the columns that were estimated rather than
#' observed.
#'
#' @param met A data frame.
#' @return `met_schema()`: a data frame of columns, units, bounds and
#'   meanings. `validate_met()`: `met`, invisibly.
#' @export
#' @examples
#' met_schema()
met_schema <- function() met_columns

#' @rdname met_schema
#' @export
validate_met <- function(met) {
  if (!is.data.frame(met)) stop("`met` must be a data frame", call. = FALSE)
  if (!"date" %in% names(met)) stop("`met` must have a `date` column", call. = FALSE)
  unknown <- setdiff(names(met), met_columns$column)
  if (length(unknown) > 0L) {
    stop("Unknown met column(s): ", paste(unknown, collapse = ", "),
         ". See met_schema().", call. = FALSE)
  }
  date <- met$date
  if (!inherits(date, "Date")) stop("`date` must be of class Date", call. = FALSE)
  if (nrow(met) < 2L) stop("`met` needs at least two days", call. = FALSE)
  if (anyNA(date) || any(diff(as.numeric(date)) != 1)) {
    stop("`date` must be consecutive days with none missing or repeated",
         call. = FALSE)
  }
  for (i in which(met_columns$column != "date" & met_columns$column %in% names(met))) {
    col <- met_columns$column[i]
    x <- met[[col]]
    if (!is.numeric(x)) stop(sprintf("`%s` must be numeric", col), call. = FALSE)
    if (anyNA(x)) {
      stop(sprintf("`%s` has %d missing value(s), the first on %s; fill or drop them before use",
                   col, sum(is.na(x)), format(date[which(is.na(x))[1]])),
           call. = FALSE)
    }
    out <- x < met_columns$lower[i] | x > met_columns$upper[i] |
      (col == "VPD_amp" & x >= 1)
    if (any(out)) {
      stop(sprintf("`%s` (%s) is outside [%g, %g] on %d day(s), the first %s with %g",
                   col, met_columns$units[i], met_columns$lower[i],
                   met_columns$upper[i], sum(out), format(date[which(out)[1]]),
                   x[which(out)[1]]), call. = FALSE)
    }
  }
  if (!is.null(attr(met, "latitude"))) solar_day(0, attr(met, "latitude"))
  invisible(met)
}

#' Mean year and repeated years
#'
#' `met_climatology()` collapses a record to its mean year: each column
#' averaged by day of year over the complete years, with 29 February dropped,
#' dated in the non-leap year 2001. `met_repeat()` repeats whole years of a
#' table end to end to cover a longer run, since plant's drivers cannot be
#' evaluated outside the times they were given.
#'
#' A mean year's rainfall falls a little on every day. Deliver it as a spline
#' (`apply_drivers(rainfall = "spline")`), or draw pulses from the record with
#' [pulse_series_fit()] instead.
#'
#' @param met A daily met table.
#' @param n_years How many years the result spans.
#' @return A daily met table carrying `met`'s site attributes (`latitude`,
#'   `longitude`, `vpd_peak_hour`, `filled`, `source`, `climatology_of`).
#'   `met_climatology()` sets `climatology_of` to the first and last years
#'   averaged.
#' @export
#' @examples
#' met <- data.frame(date = seq(as.Date("2001-01-01"), as.Date("2003-12-31"), by = "day"))
#' met$Tair_mean <- 20 + 8 * cos(2 * pi * seq_len(nrow(met)) / 365)
#' nrow(met_climatology(met))
#' nrow(met_repeat(met_climatology(met), 10))
met_climatology <- function(met) {
  validate_met(met)
  year <- as.integer(format(met$date, "%Y"))
  md <- format(met$date, "%m-%d")
  ## Days are consecutive (validate_met), so a year is complete when it has all
  ## of its days.
  counts <- table(year)
  years <- as.integer(names(counts))
  complete <- years[as.integer(counts) == 365 + is_leap(years)]
  if (length(complete) == 0L) stop("the record has no complete year", call. = FALSE)
  keep <- year %in% complete & md != "02-29"
  days <- seq(as.Date("2001-01-01"), as.Date("2001-12-31"), by = "day")
  out <- data.frame(date = days)
  for (col in setdiff(names(met), "date")) {
    out[[col]] <- as.numeric(tapply(met[[col]][keep], md[keep], mean)[format(days, "%m-%d")])
  }
  copy_met_attributes(out, met, climatology_of = range(complete))
}

#' @rdname met_climatology
#' @export
met_repeat <- function(met, n_years) {
  validate_met(met)
  if (length(n_years) != 1L || n_years < 1 || n_years != round(n_years)) {
    stop("`n_years` must be one whole number of years", call. = FALSE)
  }
  first <- as.integer(format(met$date[1], "%Y"))
  if (format(met$date[1], "%m-%d") != "01-01" ||
      format(met$date[nrow(met)], "%m-%d") != "12-31") {
    stop("met_repeat() needs whole years, from 1 January to 31 December",
         call. = FALSE)
  }
  span <- as.integer(format(met$date[nrow(met)], "%Y")) - first + 1L
  n_copies <- ceiling(n_years / span)
  md <- format(met$date, "%m-%d")
  out <- NULL
  for (k in seq_len(n_copies) - 1L) {
    years <- first + k * span + (as.integer(format(met$date, "%Y")) - first)
    piece <- met
    piece$date <- as.Date(paste0(years, "-", md), format = "%Y-%m-%d")
    ## A record's 29 February has no day in a non-leap target year, and a
    ## non-leap record leaves a leap year's 29 February empty: take the 28th.
    piece <- piece[!is.na(piece$date), , drop = FALSE]
    out <- rbind(out, piece)
  }
  all_days <- seq(as.Date(paste0(first, "-01-01")),
                  as.Date(paste0(first + n_years - 1L, "-12-31")), by = "day")
  idx <- match(all_days, out$date)
  if (anyNA(idx)) {
    feb29 <- which(is.na(idx))
    idx[feb29] <- match(all_days[feb29] - 1, out$date)
  }
  res <- out[idx, , drop = FALSE]
  res$date <- all_days
  rownames(res) <- NULL
  copy_met_attributes(res, met)
}

copy_met_attributes <- function(to, from, ...) {
  for (a in c("latitude", "longitude", "vpd_peak_hour", "filled", "source",
              "climatology_of")) {
    attr(to, a) <- attr(from, a)
  }
  extra <- list(...)
  for (a in names(extra)) attr(to, a) <- extra[[a]]
  to
}

is_leap <- function(year) year %% 4 == 0 & (year %% 100 != 0 | year %% 400 == 0)
