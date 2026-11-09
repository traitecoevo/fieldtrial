## Parameter sets: one YAML file per species x site, materialised into the
## four inputs plant::run_scm() takes. The file format is described in
## inst/sets/README.md; a set file is versioned by its `schema` key.

set_schema_version <- 1L

set_keys <- c("schema", "name", "description", "model",
              "plant_scientific_version", "site", "traits",
              "tradeoff_coefficients", "pars", "strategy", "environment",
              "drivers", "run", "control", "provenance")

## Strategy fields that are not parameters a set may set: plumbing, set by
## plant itself or by add_strategies().
strategy_plumbing <- c("pars", "control", "collect_all_auxiliary",
                       "birth_rate_x", "birth_rate_y", "is_variable_birth_rate")

soil_keys <- c("depth", "n_layers", "top", "theta", "soil_moist_sat", "K_sat",
               "a_psi", "n_psi")

## Run settings a set may give: fields of plant's Parameters that
## add_strategies() leaves alone (it rewrites the strategies and their node
## schedules), plus the strategy's birth rate.
run_keys <- c("max_patch_lifetime", "patch_area", "n_patches", "patch_type",
              "fitness_window_start", "fitness_window_end", "birth_rate")

driver_keys <- c("source", "file", "res", "repeat", "set", "rainfall", "leaf_temp")

#' Parameter sets for species and sites
#'
#' A parameter set bundles everything one run of plant needs for a species at
#' a site: its traits and the trade-offs that derive its other parameters, any
#' parameters set directly, the soil, the climate drivers and the run's
#' settings, each scientific value with the source it came from. Sets live as
#' YAML files in the package (`list_sets()`) or anywhere on disk.
#'
#' `parameter_set()` reads a set and builds the four inputs of
#' `plant::run_scm()`: `p` (a `plant::Parameters` with one strategy), `env`
#' (a `plant::Environment` with its soil and drivers), `ctrl` (a
#' `plant::Control`) and `events` (rainfall pulses, or `NULL`). `run_set()`
#' runs them. Nothing a set names is dropped: a key that reaches none of these
#' inputs is refused.
#'
#' A set records the plant model version it was built against
#' (`plant_scientific_version`, e.g. `"TF24@v15"`). `check_set()` compares it
#' with the installed plant and refuses a mismatch, since the same numbers can
#' mean a different plant after a scientific change.
#'
#' @param set A set name from `list_sets()`, a path to a set file, or a
#'   `fieldtrial_set`.
#' @param check Whether to run `check_set()` on the result.
#' @param drivers Whether to build the set's drivers. `FALSE` builds
#'   everything else, leaving the environment's drivers at plant's values and
#'   `events` empty, so a set can be checked without its climate data.
#' @param driver_path Where downloaded climate data are kept, for sets whose
#'   drivers come from a gridded source.
#' @return `parameter_set()`: a list of class `fieldtrial_set` with `p`, `env`,
#'   `ctrl`, `events`, `tradeoffs` (the trade-off function used), `met` (the
#'   daily met table) and `meta` (the parsed file). `run_set()`: the result of
#'   `plant::run_scm()`. `check_set()`: `set`, invisibly. `list_sets()`: the
#'   names of the sets in the package.
#' @export
parameter_set <- function(set, check = TRUE, drivers = TRUE,
                          driver_path = fieldtrial_cache("worldclim")) {
  if (inherits(set, "fieldtrial_set")) return(set)
  path <- set_path(set)
  meta <- read_set_file(path)
  model <- meta$model

  ## Parameters: run settings, then direct pars and strategy fields on the
  ## default strategy, then the one strategy built through the trade-offs.
  p <- plant::scm_base_parameters(model)
  run <- meta$run %||% list()
  for (key in setdiff(names(run), "birth_rate")) {
    if (!key %in% run_keys || !key %in% names(p)) {
      refuse_key("run", key, paste("one of", paste(run_keys, collapse = ", ")))
    }
    p[[key]] <- match_type(run[[key]], p[[key]])
  }
  tf <- tradeoffs(model, values_of(meta$tradeoff_coefficients, "tradeoff_coefficients"))
  s <- p$strategy_default
  derived <- colnames(tf(matrix(numeric(0), 1, 0), s, filter = FALSE))
  traits <- values_of(meta$traits, "traits")
  pars <- values_of(meta$pars, "pars")
  readable <- c(names(s$pars), attr(tf, "input_traits"))
  for (key in names(traits)) {
    if (key %in% derived) refuse_key("traits", key, "a trait, not a parameter the trade-offs derive")
    if (!key %in% readable) refuse_key("traits", key, sprintf("a parameter of %s or an input of its trade-offs", model))
  }
  for (key in names(pars)) {
    if (key %in% derived) refuse_key("pars", key, "a parameter the trade-offs do not derive (it would be overwritten; set the trait it comes from)")
    if (key %in% names(traits)) refuse_key("pars", key, "listed once, under traits or pars, not both")
    if (!key %in% names(s$pars)) refuse_key("pars", key, sprintf("a parameter of %s", model))
    p$strategy_default$pars[[key]] <- pars[[key]]
  }
  fields <- values_of(meta$strategy, "strategy")
  for (key in names(fields)) {
    if (key %in% strategy_plumbing || !key %in% names(s) || !is.numeric(s[[key]])) {
      refuse_key("strategy", key, sprintf("a numeric field of %s_Strategy", model))
    }
    p$strategy_default[[key]] <- fields[[key]]
  }
  if (length(traits) == 0L) {
    stop("A set needs at least one trait, to build its strategy through the trade-offs",
         call. = FALSE)
  }
  m <- matrix(unlist(traits), nrow = 1, dimnames = list(NULL, names(traits)))
  p <- plant::add_strategies(p, m, tf, birth_rate = as.numeric(run$birth_rate %||% 1),
                             keep_existing = FALSE)
  ## plant's Parameters carry their trade-offs, so mutants, gradients and
  ## anything else built from p later use the set's, not plant's testing copy.
  if ("hyperpar" %in% names(p)) p$hyperpar <- tf

  ## Environment: soil, other fields, drivers.
  env <- plant::Environment(model)
  env_spec <- meta$environment %||% list()
  unknown <- setdiff(names(env_spec), c("soil", "fields"))
  if (length(unknown) > 0L) refuse_key("environment", unknown[1], "`soil` or `fields`")
  if (!is.null(env_spec$soil)) apply_soil(env, env_spec$soil)
  for (key in names(env_spec$fields)) {
    if (!has_field(env, key)) refuse_key("environment$fields", key, sprintf("a field of %s's environment", model))
    env[[key]] <- values_of(env_spec$fields[key], "environment$fields")[[key]]
  }
  built <- if (drivers) {
    build_drivers(meta, env, path, p$max_patch_lifetime, driver_path)
  } else {
    list(met = NULL, events = NULL)
  }

  ## Control.
  ctrl <- plant::control()
  for (key in names(meta$control)) {
    if (!key %in% names(ctrl)) refuse_key("control", key, "a field of plant's Control")
    ctrl[[key]] <- match_type(meta$control[[key]], ctrl[[key]])
  }

  set <- structure(list(p = p, env = env, ctrl = ctrl, events = built$events,
                        tradeoffs = tf, met = built$met, meta = meta),
                   class = "fieldtrial_set")
  if (check) check_set(set)
  set
}

#' @rdname parameter_set
#' @param allow_version_drift Accept a set built against another plant model
#'   version.
#' @export
check_set <- function(set, allow_version_drift = FALSE) {
  set <- parameter_set(set, check = FALSE)
  recorded <- set$meta$plant_scientific_version
  installed <- plant::model_id(set$meta$model)
  if (!identical(recorded, installed) && !allow_version_drift) {
    stop(sprintf(paste0("Set \"%s\" was built against %s, and the installed plant is %s. ",
                        "Its values may mean a different plant now; review the set and ",
                        "update plant_scientific_version, or pass allow_version_drift = TRUE"),
                 set$meta$name, recorded, installed), call. = FALSE)
  }
  invisible(set)
}

#' @rdname parameter_set
#' @param ... Passed to `plant::run_scm()`.
#' @export
run_set <- function(set, ...) {
  set <- parameter_set(set)
  events <- if (is.null(set$events)) NULL else
    plant::events(plant::events_default(set$p), set$events)
  plant::run_scm(set$p, set$env, set$ctrl, events = events, ...)
}

#' @rdname parameter_set
#' @export
list_sets <- function() {
  dir <- system.file("sets", package = "fieldtrial")
  sub("\\.yml$", "", list.files(dir, pattern = "\\.yml$"))
}

#' @export
print.fieldtrial_set <- function(x, ...) {
  m <- x$meta
  cat(sprintf("<fieldtrial_set> %s: %s at %s\n", m$name, m$model, m$site$name %||% "an unnamed site"))
  cat(sprintf("  built against %s; %d trait(s), %d direct par(s); drivers from %s\n",
              m$plant_scientific_version, length(m$traits), length(m$pars),
              m$drivers$source %||% "plant defaults"))
  invisible(x)
}

set_path <- function(set) {
  if (!is.character(set) || length(set) != 1L) {
    stop("`set` must be a set name, a path to a set file, or a fieldtrial_set",
         call. = FALSE)
  }
  if (file.exists(set)) return(set)
  path <- system.file("sets", paste0(set, ".yml"), package = "fieldtrial")
  if (!nzchar(path)) {
    stop(sprintf("No set \"%s\". Sets in the package: %s", set,
                 paste(list_sets(), collapse = ", ")), call. = FALSE)
  }
  path
}

read_set_file <- function(path) {
  meta <- yaml::read_yaml(path)
  unknown <- setdiff(names(meta), set_keys)
  if (length(unknown) > 0L) refuse_key("the set file", unknown[1], paste(set_keys, collapse = ", "))
  if (!identical(as.integer(meta$schema), set_schema_version)) {
    stop(sprintf("Set file %s has schema %s; this fieldtrial reads schema %d",
                 path, format(meta$schema %||% "none"), set_schema_version), call. = FALSE)
  }
  for (key in c("name", "model", "plant_scientific_version")) {
    if (!is.character(meta[[key]]) || length(meta[[key]]) != 1L) {
      stop(sprintf("Set file %s needs a `%s`", path, key), call. = FALSE)
    }
  }
  model_family(meta$model)
  meta
}

## A block of `name: {value: x, source: "..."}` entries as a named list of
## numbers. Every scientific value in a set carries its source.
values_of <- function(block, where) {
  if (is.null(block) || length(block) == 0L) return(list())
  out <- list()
  for (key in names(block)) {
    entry <- block[[key]]
    if (!is.list(entry) || !is.numeric(entry$value) || length(entry$value) != 1L ||
        !is.finite(entry$value)) {
      stop(sprintf("%s$%s must be {value: <number>, source: <text>}", where, key),
           call. = FALSE)
    }
    if (!is.character(entry$source) || length(entry$source) != 1L || !nzchar(entry$source)) {
      stop(sprintf("%s$%s has no source; every value in a set names where it came from",
                   where, key), call. = FALSE)
    }
    out[[key]] <- as.numeric(entry$value)
  }
  out
}

refuse_key <- function(where, key, expected) {
  stop(sprintf("Set key %s$%s is not %s", where, key, expected), call. = FALSE)
}

apply_soil <- function(env, soil) {
  unknown <- setdiff(names(soil), soil_keys)
  if (length(unknown) > 0L) refuse_key("environment$soil", unknown[1], paste(soil_keys, collapse = ", "))
  v <- values_of(soil, "environment$soil")
  widths <- NULL
  if (!is.null(v$depth) || !is.null(v$n_layers) || !is.null(v$top)) {
    if (is.null(v$depth) || is.null(v$n_layers)) {
      stop("environment$soil needs both depth and n_layers to make a profile ",
           "(top only sets its surface layer)", call. = FALSE)
    }
    widths <- soil_widths_graded(v$depth, v$n_layers, v$top %||% 0.02)
  }
  ## plant takes the soil parameters one value per layer, and a set gives one
  ## for the column. Initial moisture (theta) plant itself spreads over the
  ## layers when given one value.
  n <- if (is.null(widths)) env$get_soil_number_of_depths() else length(widths)
  per_layer <- function(x) if (is.null(x)) NULL else rep(x, n)
  plant::set_tf24_soil(env, widths = widths, theta = v$theta,
                       soil_moist_sat = per_layer(v$soil_moist_sat),
                       K_sat = per_layer(v$K_sat), a_psi = per_layer(v$a_psi),
                       n_psi = per_layer(v$n_psi))
  invisible(env)
}

## The set's drivers: a daily met table from its source, repeated to cover the
## run, applied to the environment.
build_drivers <- function(meta, env, path, max_patch_lifetime, driver_path) {
  spec <- meta$drivers
  if (is.null(spec)) return(list(met = NULL, events = NULL))
  unknown <- setdiff(names(spec), driver_keys)
  if (length(unknown) > 0L) refuse_key("drivers", unknown[1], paste("one of", paste(driver_keys, collapse = ", ")))
  site <- meta$site %||% list()
  source <- spec$source %||% ""
  met <- switch(source,
    worldclim = met_from_worldclim(site$latitude, site$longitude,
                                   res = spec$res %||% 10, path = driver_path),
    met_file = read_met_file(file.path(dirname(path), spec$file), site),
    stop(sprintf("drivers$source must be \"worldclim\" or \"met_file\", not \"%s\"", source),
         call. = FALSE))
  n_years <- max(1L, as.integer(ceiling(max_patch_lifetime)))
  if (!is.null(attr(met, "climatology_of")) || isTRUE(spec[["repeat"]])) {
    met <- met_repeat(met, n_years)
  }
  ## A run starts at time 0, the start of 1 January of the table's first year,
  ## and must end inside the table.
  if (format(met$date[1], "%m-%d") != "01-01") {
    stop("The met table must start on 1 January: a run starts at time 0, ",
         "the start of its first year", call. = FALSE)
  }
  covered <- met_time(met$date[nrow(met)], as.integer(format(met$date[1], "%Y"))) +
    0.5 / (365 + is_leap(as.integer(format(met$date[nrow(met)], "%Y"))))
  if (covered < max_patch_lifetime) {
    stop(sprintf(paste0("The met table covers %.3g years and the run is %.3g; ",
                        "give a longer record or set drivers$repeat: true"),
                 covered, max_patch_lifetime), call. = FALSE)
  }
  drivers <- c(spec$set %||% c("SWdown", "atm_vpd", "atm_vpd_diurnal_amp", "atm_kpa",
                               "wind_speed", "ca", "rainfall"),
               if (isTRUE(spec$leaf_temp)) "leaf_temp")
  res <- apply_drivers(env, met, rainfall = spec$rainfall %||% "pulse",
                       drivers = drivers, until = max_patch_lifetime)
  list(met = met, events = res$events)
}

read_met_file <- function(file, site) {
  if (!file.exists(file)) stop(sprintf("Met file %s not found", file), call. = FALSE)
  met <- utils::read.csv(file, stringsAsFactors = FALSE)
  met$date <- as.Date(met$date)
  for (a in c("latitude", "longitude")) attr(met, a) <- site[[a]]
  validate_met(met)
}

## YAML reads 1 as an integer; plant's fields want the type they already have.
match_type <- function(value, like) {
  if (is.integer(like)) as.integer(value)
  else if (is.double(like)) as.numeric(value)
  else value
}
