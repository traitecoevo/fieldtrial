#' Trait trade-offs for a plant model
#'
#' Builds the function plant uses to derive model parameters from traits: it
#' takes a trait matrix `m` (one row per strategy, named columns) and a
#' strategy `s`, and returns `m` with the derived parameters appended. Pass it
#' to `plant::add_strategies()`, `plant::generate_strategy()` or
#' `plant::stand_gradient()` as `hyperpar`.
#'
#' A trait missing from `m` takes the strategy's value. With `filter = TRUE`,
#' a derived column equal to the strategy's own value in every row is left out,
#' so the strategy keeps its default.
#'
#' These are the recommended trade-offs. plant keeps its own frozen copy for
#' testing; on any one platform the two give identical numbers.
#'
#' @param model A plant model name: `"FF16"`, `"TF24"`, `"TF24f"`, `"TF24t"` or
#'   `"TF24w"`. The TF24 variants share one set of trade-offs.
#' @param coefficients A named list of coefficients that replace the defaults
#'   in [tradeoff_coefficients()]. Unknown names are refused.
#' @return A function `f(m, s, filter = TRUE)`. FF16's carries
#'   `attr(f, "input_traits")`, naming the traits it reads that are not
#'   parameters of the model.
#' @export
#' @examples
#' f <- tradeoffs("TF24", coefficients = list(B_Hv2 = -0.25))
#' attr(f, "coefficients")$B_Hv2
tradeoffs <- function(model, coefficients = list()) {
  family <- model_family(model)
  co <- merge_coefficients(tradeoff_coefficients(model), coefficients, model)
  f <- switch(family,
              FF16 = ff16_tradeoffs(co),
              TF24 = tf24_tradeoffs(co))
  attr(f, "model") <- model
  attr(f, "coefficients") <- co
  f
}

merge_coefficients <- function(defaults, overrides, model) {
  if (!is.list(overrides) || (length(overrides) > 0L && is.null(names(overrides)))) {
    stop("`coefficients` must be a named list", call. = FALSE)
  }
  unknown <- setdiff(names(overrides), names(defaults))
  if (length(unknown) > 0L) {
    stop(sprintf("Unknown %s trade-off coefficient%s: %s", model,
                 if (length(unknown) > 1L) "s" else "",
                 paste(unknown, collapse = ", ")), call. = FALSE)
  }
  for (name in names(overrides)) {
    x <- overrides[[name]]
    if (!is.numeric(x) || length(x) != 1L || is.na(x)) {
      stop(sprintf("Coefficient %s must be a single number", name),
           call. = FALSE)
    }
    defaults[[name]] <- as.numeric(x)
  }
  defaults
}

## A trait's values for every row of `m`, or the strategy's value where `m`
## has no such column.
trait_values <- function(m, s, name, default_value = s$pars[[name]]) {
  rep_len(if (name %in% colnames(m)) m[, name] else default_value, nrow(m))
}

## The checks and filtering every model's trade-offs share, then the append.
append_derived <- function(m, extra, s, filter) {
  overlap <- intersect(colnames(m), colnames(extra))
  if (length(overlap) > 0L) {
    stop("Attempt to overwrite generated parameters: ",
         paste(overlap, collapse = ", "))
  }
  if (any(is.infinite(extra))) {
    stop("Attempt to use infinite value in derived parameters: ",
         paste(colnames(extra)[is.infinite(extra)], collapse = ", "))
  }
  ## Leave out a column that equals the strategy's own value in every row, so
  ## the strategy keeps its default rather than a copy that may differ in the
  ## last bits.
  if (filter) {
    if (nrow(extra) == 0L) {
      extra <- NULL
    } else {
      pos <- diff(apply(extra, 2, range)) == 0
      if (any(pos)) {
        eps <- sqrt(.Machine$double.eps)
        x1 <- extra[1, pos]
        x2 <- unlist(s$pars[names(x1)])
        drop <- abs(x1 - x2) < eps & abs(1 - x1 / x2) < eps
        if (any(drop)) {
          keep <- setdiff(colnames(extra), names(drop)[drop])
          extra <- extra[, keep, drop = FALSE]
        }
      }
    }
  }
  if (!is.null(extra)) {
    m <- cbind(m, extra)
  }
  m
}
