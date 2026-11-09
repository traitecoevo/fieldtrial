## Coefficient files live in inst/tradeoffs/<family>.yml. Each coefficient's
## `value` is a quoted R numeric expression, evaluated here with R's parser:
## YAML's number parser does not always give the double R gives for the same
## digits, and these values must reproduce plant's to the bit.

## Model -> the coefficient family whose trade-offs it uses.
tradeoff_families <- c(FF16 = "FF16",
                       TF24 = "TF24", TF24f = "TF24", TF24t = "TF24",
                       TF24w = "TF24")

model_family <- function(model) {
  if (!is.character(model) || length(model) != 1L || is.na(model)) {
    stop("`model` must be a single model name, such as \"TF24\"", call. = FALSE)
  }
  family <- tradeoff_families[model]
  if (is.na(family)) {
    if (identical(model, "K93")) {
      stop("K93 has no trait trade-offs; traits are written straight to its ",
           "parameters (pass `hyperpar = NULL` to plant)", call. = FALSE)
    }
    stop(sprintf("No trade-offs for model \"%s\"; known models: %s", model,
                 paste(names(tradeoff_families), collapse = ", ")),
         call. = FALSE)
  }
  unname(family)
}

read_tradeoff_file <- function(family) {
  path <- system.file("tradeoffs", paste0(family, ".yml"),
                      package = "fieldtrial", mustWork = TRUE)
  yaml::read_yaml(path)
}

## Evaluate one coefficient's text. Only numeric literals and the arithmetic
## operators + - * / ^ and parentheses are accepted, so a coefficient file
## cannot run code.
eval_coefficient <- function(text, name) {
  if (!is.character(text) || length(text) != 1L) {
    stop(sprintf("Coefficient %s: `value` must be a quoted R numeric ", name),
         "expression, e.g. \"0.2\" or \"2.0 * 4012.0\"", call. = FALSE)
  }
  expr <- tryCatch(str2lang(text), error = function(e) {
    stop(sprintf("Coefficient %s: cannot parse \"%s\"", name, text),
         call. = FALSE)
  })
  arithmetic <- function(e) {
    if (is.numeric(e)) return(length(e) == 1L)
    if (!is.call(e)) return(FALSE)
    op <- e[[1L]]
    is.name(op) && as.character(op) %in% c("+", "-", "*", "/", "^", "(") &&
      all(vapply(as.list(e)[-1L], arithmetic, logical(1)))
  }
  if (!arithmetic(expr)) {
    stop(sprintf("Coefficient %s: \"%s\" is not plain arithmetic on numbers",
                 name, text), call. = FALSE)
  }
  value <- eval(expr, baseenv())
  if (!is.numeric(value) || length(value) != 1L || !is.finite(value)) {
    stop(sprintf("Coefficient %s: \"%s\" is not a finite number", name, text),
         call. = FALSE)
  }
  as.numeric(value)
}

#' Trade-off coefficients for a model
#'
#' The coefficients that parameterise a model's trait trade-offs, read from
#' the package's coefficient file for that model's family. TF24, TF24f, TF24t
#' and TF24w share one set.
#'
#' @param model A plant model name, such as `"TF24"` or `"FF16"`.
#' @return `tradeoff_coefficients()`: a named list of numbers.
#'   `tradeoff_table()`: a data frame with one row per coefficient and columns
#'   `name`, `value`, `units`, `description`, `source` and `reference`.
#' @export
#' @examples
#' tradeoff_coefficients("TF24")$B_Hv1
#' head(tradeoff_table("FF16"))
tradeoff_coefficients <- function(model) {
  info <- read_tradeoff_file(model_family(model))
  Map(eval_coefficient, lapply(info$coefficients, `[[`, "value"),
      names(info$coefficients))
}

#' @rdname tradeoff_coefficients
#' @export
tradeoff_table <- function(model) {
  info <- read_tradeoff_file(model_family(model))
  co <- info$coefficients
  field <- function(x) vapply(co, function(e) e[[x]] %||% "", character(1))
  data.frame(name = names(co),
             value = unlist(tradeoff_coefficients(model), use.names = FALSE),
             units = field("units"),
             description = field("description"),
             source = field("source"),
             reference = field("reference"),
             row.names = NULL, stringsAsFactors = FALSE)
}

`%||%` <- function(x, y) if (is.null(x)) y else x
