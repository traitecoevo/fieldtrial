## Which met column feeds which TF24 driver, and how it is converted.
driver_map <- data.frame(
  driver = c("SWdown", "atm_vpd", "atm_vpd_diurnal_amp", "atm_kpa",
             "wind_speed", "ca", "leaf_temp"),
  column = c("SWdown_noon", "VPD_noon", "VPD_amp", "Psurf", "Wind", "CO2air",
             "Tair_noon"),
  stringsAsFactors = FALSE)

#' Set a plant environment's drivers from a daily met table
#'
#' Writes the daily met table's columns into a TF24 environment's drivers, one
#' knot per day at its middle, and turns its precipitation into rainfall:
#'
#' | met column | driver | conversion |
#' |---|---|---|
#' | `SWdown_noon` | `SWdown` | none, W m-2 |
#' | `VPD_noon` | `atm_vpd` | none, kPa |
#' | `VPD_amp` | `atm_vpd_diurnal_amp` | only where the environment has it |
#' | `Psurf` | `atm_kpa` | none, kPa |
#' | `Wind` | `wind_speed` | none, m s-1 |
#' | `CO2air` | `ca` | ppm to Pa at `Psurf`, or at the environment's `atm_kpa` |
#' | `Tair_noon` | `leaf_temp` | only if `"leaf_temp"` is in `drivers` |
#' | `Precip` | rainfall | see `rainfall` |
#'
#' `leaf_temp` is left at plant's value unless asked for, because plant's TF24
#' runs its leaf at that temperature with the energy balance off, and a site's
#' air temperature changes every temperature response at once. When asked for,
#' it is the noon temperature, like every other driver here: the daily mean
#' would pair a noon VPD with a cooler, less saturable air.
#'
#' Rainfall is delivered as **pulses** by default: each wet day's total, in
#' metres, at the middle of the day, as rows from `plant::rainfall_pulse()`, and
#' the continuous `rainfall` driver is set to zero so the water is not counted
#' twice. Pass the returned `events` to `plant::run_scm()` with
#' `plant::events()`. A daily total is a sum of discrete events; interpolating
#' it spreads each one over its neighbours. `rainfall = "spline"` sets the
#' continuous driver instead (m yr-1), which suits a mean year.
#'
#' Before setting anything, the noon VPD is checked against the leaf's limit,
#' `0 < VPD < e_s(T)` at the leaf temperature it will meet (Tetens, as plant's
#' leaf computes it): plant refuses outside it, and it is cheaper to say so
#' here, with the dates.
#'
#' Times are plant's: years from 1 January of `start_year`. plant's TF24 reads
#' the day of year from the fractional part of time, so `start_year` must be
#' the first calendar year of the run. Each day's value is a knot at the middle
#' of the day, and the first and last days hold to the start of the first and
#' the end of the last, so the drivers cover the table's whole days; a run must
#' not go past them.
#'
#' @param env A TF24-family `plant::Environment`, changed in place.
#' @param met A daily met table (see [met_schema()]).
#' @param start_year The calendar year at time 0. Defaults to the table's
#'   first year.
#' @param rainfall `"pulse"` or `"spline"`.
#' @param drivers The drivers to set, from those above; `"rainfall"` stands for
#'   precipitation. Defaults to all but `leaf_temp`. A driver whose column is
#'   absent is left at plant's value and reported.
#' @param until Drop rainfall pulses after this time: plant refuses an event
#'   past the run's `max_patch_lifetime`, so pass that. `NULL` keeps them all.
#' @return A list: `env`; `events`, the rainfall pulses (or `NULL`); and
#'   `drivers`, a data frame saying, for each driver, whether it was set from
#'   the table or left at plant's value.
#' @export
apply_drivers <- function(env, met, start_year = NULL,
                          rainfall = c("pulse", "spline"),
                          drivers = c("SWdown", "atm_vpd", "atm_vpd_diurnal_amp",
                                      "atm_kpa", "wind_speed", "ca", "rainfall"),
                          until = NULL) {
  rainfall <- match.arg(rainfall)
  validate_met(met)
  if (rainfall == "pulse" && "rainfall" %in% drivers && "Precip" %in% names(met) &&
      !is.null(attr(met, "climatology_of"))) {
    warning("This table is a climatology, whose rain falls a little on every ",
            "day; as pulses that is a daily drizzle. Use rainfall = \"spline\", ",
            "or draw pulses from a record with pulse_series_fit().", call. = FALSE)
  }
  known <- c(driver_map$driver, "rainfall")
  if (length(setdiff(drivers, known)) > 0L) {
    stop("Unknown driver(s): ", paste(setdiff(drivers, known), collapse = ", "),
         call. = FALSE)
  }
  env_drivers <- tryCatch(env$extrinsic_drivers_get_names(), error = function(e) {
    stop("`env` must be a plant environment with settable drivers (TF24 family)",
         call. = FALSE)
  })
  if (is.null(start_year)) start_year <- as.integer(format(met$date[1], "%Y"))
  t <- met_time(met$date, start_year)
  ## Knots sit at the middle of each day; the first and last days' values are
  ## also pinned to the start of the first day and the end of the last, so the
  ## drivers cover every whole day of the table (a run starts at time 0, the
  ## start of 1 January, and plant refuses to evaluate outside the knots).
  year_first <- as.integer(format(met$date[1], "%Y"))
  year_last <- as.integer(format(met$date[nrow(met)], "%Y"))
  t_knots <- c(t[1] - 0.5 / (365 + is_leap(year_first)), t,
               t[length(t)] + 0.5 / (365 + is_leap(year_last)))
  pad <- function(y) c(y[1], y, y[length(y)])
  status <- data.frame(driver = character(0), from = character(0),
                       stringsAsFactors = FALSE)
  record <- function(driver, from) {
    status[nrow(status) + 1L, ] <<- list(driver, from)
  }

  ## Leaf temperature the VPD will meet, then the VPD check, before anything is
  ## changed.
  if ("leaf_temp" %in% drivers && "Tair_noon" %in% names(met)) {
    leaf_temp <- met$Tair_noon
  } else {
    leaf_temp <- env$extrinsic_drivers_evaluate_range("leaf_temp", t)
  }
  if ("atm_vpd" %in% drivers && "VPD_noon" %in% names(met)) {
    e_s <- saturation_vapour_pressure(leaf_temp)
    bad <- !(met$VPD_noon > 0 & met$VPD_noon < e_s)
    if (any(bad)) {
      i <- which(bad)[1]
      stop(sprintf(paste0("VPD_noon is outside (0, e_s) at the leaf temperature on %d day(s), ",
                          "the first %s: %.3g kPa against e_s = %.3g kPa at %.3g degC. plant's leaf ",
                          "refuses these; set leaf_temp from the site (drivers = c(..., \"leaf_temp\")) ",
                          "or correct the table"),
                   sum(bad), format(met$date[i]), met$VPD_noon[i], e_s[i], leaf_temp[i]),
           call. = FALSE)
    }
  }

  for (k in seq_len(nrow(driver_map))) {
    driver <- driver_map$driver[k]
    column <- driver_map$column[k]
    if (!driver %in% drivers) next
    if (!driver %in% env_drivers) {
      if (column %in% names(met)) record(driver, "not in this plant version")
      next
    }
    if (!column %in% names(met)) {
      record(driver, "plant default (column absent)")
      next
    }
    y <- met[[column]]
    if (driver == "ca") {
      kpa <- if ("Psurf" %in% names(met)) met$Psurf else
        env$extrinsic_drivers_evaluate_range("atm_kpa", t)
      y <- y * 1e-6 * kpa * 1000
    }
    env$extrinsic_drivers_set_variable(driver, t_knots, pad(y))
    record(driver, column)
  }

  ## Site fields of the environment, each independently: plant versions
  ## before the diurnal integral have neither.
  for (field in c("latitude", "vpd_peak_hour")) {
    value <- attr(met, field)
    if (!is.null(value) && has_field(env, field)) {
      env[[field]] <- value
      record(paste0(field, " (field)"), sprintf("attr(met, \"%s\")", field))
    }
  }

  events <- NULL
  if ("rainfall" %in% drivers) {
    if (!"Precip" %in% names(met)) {
      record("rainfall", "plant default (column absent)")
    } else if (rainfall == "pulse") {
      env$extrinsic_drivers_set_constant("rainfall", 0)
      wet <- met$Precip > 0
      if (!is.null(until)) wet <- wet & t <= until
      events <- plant::rainfall_pulse(t[wet], met$Precip[wet] / 1000, env = env)
      record("rainfall", "Precip, as pulses (continuous driver set to 0)")
    } else {
      ## Each knot carries its day's total as a rate over that day's share of
      ## its year, so a year's rainfall is conserved, leap or not.
      year <- as.integer(format(met$date, "%Y"))
      env$extrinsic_drivers_set_variable("rainfall", t_knots,
                                         pad(met$Precip / 1000 * (365 + is_leap(year))))
      record("rainfall", "Precip, as a spline")
    }
  }
  list(env = env, events = events, drivers = status)
}

## Saturation vapour pressure, kPa, at temp degC: the Tetens form and constants
## of plant's leaf (phylloptim Leaf::saturation_vapour_pressure), so a VPD
## accepted here is one the leaf accepts.
saturation_vapour_pressure <- function(temp) {
  0.6108 * exp(17.27 * temp / (temp + 237.3))
}

## Whether an RcppR6 environment has a field of this name (fields added by
## later plant versions, such as latitude, are absent from earlier ones).
has_field <- function(obj, name) {
  !is.null(tryCatch(obj[[name]], error = function(e) NULL))
}
