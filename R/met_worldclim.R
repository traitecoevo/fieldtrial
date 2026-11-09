#' Daily met table from WorldClim
#'
#' WorldClim 2.1 gives monthly climate normals for 1970-2000 on a global grid
#' (Fick and Hijmans 2017). `met_from_worldclim()` reads them at a site and
#' makes a daily mean year with [met_from_monthly()]; `worldclim_monthly()`
#' returns the monthly values themselves.
#'
#' The grids are downloaded once with the `geodata` package and kept in
#' `path`. A download is the whole globe for each of seven variables plus
#' elevation, so the resolution sets its size: about 200 MB at 10 arc-minutes
#' (the default, about 18 km), 700 MB at 5, 2.5 GB at 2.5. At 0.5 (30
#' arc-seconds, about 1 km) the 30-degree tile around the site is fetched
#' instead.
#'
#' What WorldClim gives and what is assumed: temperatures, precipitation,
#' shortwave (`srad`, converted from kJ m-2 d-1 to W m-2), wind (a 24-hour mean,
#' used where the table wants a daytime mean) and vapour pressure are read;
#' the noon temperature, noon VPD and its amplitude come from the daily cosine
#' assumptions in [met_from_monthly()]; surface pressure comes from elevation.
#' There is no CO2. The result is a mean year with no interannual variation, so
#' its rainfall belongs on a spline (`apply_drivers(rainfall = "spline")`).
#'
#' @param latitude,longitude Site location, degrees.
#' @param res Grid resolution in arc-minutes: 10, 5, 2.5 or 0.5.
#' @param path Folder to keep the downloads in.
#' @param ... Passed to [met_from_monthly()].
#' @return `met_from_worldclim()`: a daily met table for the year 2001, with
#'   `climatology_of = c(1970, 2000)`. `worldclim_monthly()`: a data frame of
#'   12 months in [met_from_monthly()]'s columns, with an `elevation`
#'   attribute.
#' @references Fick, S.E. and Hijmans, R.J. (2017) WorldClim 2: new 1-km
#'   spatial resolution climate surfaces for global land areas. International
#'   Journal of Climatology 37(12), 4302-4315.
#' @export
#' @examples
#' \dontrun{
#' met <- met_from_worldclim(-22.283, 133.249)  # Alice Springs Mulga
#' sum(met$Precip)                               # mean annual rainfall, mm
#' }
met_from_worldclim <- function(latitude, longitude, res = 10,
                               path = fieldtrial_cache("worldclim"), ...) {
  monthly <- worldclim_monthly(latitude, longitude, res = res, path = path)
  met_from_monthly(monthly, latitude, longitude,
                   elevation = attr(monthly, "elevation"),
                   source = sprintf("WorldClim 2.1, %s arc-minutes", format(res)),
                   ...)
}

#' @rdname met_from_worldclim
#' @export
worldclim_monthly <- function(latitude, longitude, res = 10,
                              path = fieldtrial_cache("worldclim")) {
  for (pkg in c("geodata", "terra")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop(sprintf("Reading WorldClim needs the %s package", pkg), call. = FALSE)
    }
  }
  if (length(res) != 1L || !res %in% c(10, 5, 2.5, 0.5)) {
    stop("`res` must be one of 10, 5, 2.5 or 0.5 arc-minutes", call. = FALSE)
  }
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
  fetch <- function(var) {
    if (res == 0.5) {
      geodata::worldclim_tile(var, lon = longitude, lat = latitude, path = path)
    } else {
      geodata::worldclim_global(var, res = res, path = path)
    }
  }
  vars <- c("tmin", "tmax", "tavg", "prec", "srad", "wind", "vapr")
  rasters <- lapply(vars, fetch)
  names(rasters) <- vars
  elevation <- if (res == 0.5) {
    geodata::elevation_3s(lon = longitude, lat = latitude, path = path)
  } else {
    geodata::elevation_global(res = res, path = path)
  }
  worldclim_extract(rasters, elevation, latitude, longitude)
}

## The monthly values of WorldClim's rasters at a site, in met_from_monthly()'s
## columns. Kept apart from the download so it can be tested on small rasters.
worldclim_extract <- function(rasters, elevation, latitude, longitude) {
  xy <- matrix(c(longitude, latitude), ncol = 2)
  at <- function(r) {
    v <- as.numeric(terra::extract(r, xy)[1, , drop = TRUE])
    ## terra may prepend an ID column; anything else is not a raster we know.
    if (length(v) == terra::nlyr(r) + 1L) v <- v[-1]
    if (length(v) != terra::nlyr(r)) {
      stop("Unexpected terra::extract() result: ", length(v), " values for ",
           terra::nlyr(r), " layers", call. = FALSE)
    }
    v
  }
  values <- lapply(rasters, at)
  if (any(vapply(values, function(v) length(v) != 12L, logical(1)))) {
    stop("Each WorldClim variable must have 12 monthly layers", call. = FALSE)
  }
  if (anyNA(unlist(values))) {
    stop(sprintf("WorldClim has no value at %g, %g (sea, or outside the tile)",
                 latitude, longitude), call. = FALSE)
  }
  z <- at(elevation)
  out <- data.frame(month = 1:12,
                    Tair_mean = values$tavg, Tair_max = values$tmax,
                    Tair_min = values$tmin,
                    Precip_month = values$prec,
                    ## kJ m-2 d-1 to W m-2.
                    SWdown_mean = values$srad * 1000 / 86400,
                    Wind = values$wind,
                    vapour_pressure = values$vapr)
  attr(out, "elevation") <- z[1]
  attr(out, "climatology_of") <- c(1970L, 2000L)
  out
}

## Where fieldtrial keeps downloaded data, by source.
fieldtrial_cache <- function(source) {
  file.path(tools::R_user_dir("fieldtrial", which = "cache"), source)
}
