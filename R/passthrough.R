#' Which leaf parameters plant can set
#'
#' plant's TF24 family hands its leaf (phylloptim's `Leaf`) a set of traits
#' and numerical controls. A parameter set can only reach what plant exposes:
#' a strategy parameter, a strategy field, or a `Control` field. This lists
#' every trait in `phylloptim::leaf_traits()` and every control in
#' `phylloptim::leaf_control()` with where plant exposes it, so a new leaf
#' parameter that plant does not yet forward shows up as a gap to fix in
#' plant, not as a value a set silently cannot change.
#'
#' Two kinds of leaf parameter are listed as out of scope rather than gaps:
#' those of the leaf's other stomatal models (`JS22_gamma`, `CMax_a`,
#' `CMax_b`), which plant's TF24 does not select, and `integration_tol`, which
#' only sets the tolerance of a direct quadrature off the production path that
#' plant never calls. A plant field for either would be settable and reach
#' nothing.
#'
#' @param model A TF24-family model name.
#' @return A data frame with columns `name`, `kind` (`"trait"` or
#'   `"control"`) and `where` (`"strategy pars"`, `"strategy field"`,
#'   `"Control"`, `"out of scope"`, or `NA` for a gap).
#' @export
check_passthrough <- function(model = "TF24") {
  if (model_family(model) != "TF24") {
    stop("check_passthrough() is for the TF24 family, whose leaf is phylloptim's",
         call. = FALSE)
  }
  ## phylloptim is not declared as a dependency: plant links it, so it is
  ## installed wherever plant was built, and declaring it here would send
  ## dependency resolvers looking for it on CRAN, where it is not.
  pkg <- "phylloptim"
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop("check_passthrough() needs the phylloptim package plant links", call. = FALSE)
  }
  leaf_traits <- getExportedValue(pkg, "leaf_traits")
  leaf_control <- getExportedValue(pkg, "leaf_control")
  s <- get(paste0(model, "_Model"), envir = asNamespace("plant"))()
  ctrl <- plant::control()
  out_of_scope <- c("JS22_gamma", "CMax_a", "CMax_b", "integration_tol")
  ## The leaf's quadrature rule is plant's function_integration_rule.
  control_alias <- c(integration_rule = "function_integration_rule")

  where_trait <- function(n) {
    if (n %in% names(s$pars)) "strategy pars"
    else if (n %in% setdiff(names(s), strategy_plumbing)) "strategy field"
    else if (n %in% out_of_scope) "out of scope"
    else NA_character_
  }
  where_control <- function(n) {
    target <- if (n %in% names(control_alias)) control_alias[[n]] else n
    if (target %in% names(ctrl)) "Control"
    else if (n %in% out_of_scope) "out of scope"
    else NA_character_
  }
  traits <- names(leaf_traits())
  controls <- names(leaf_control())
  data.frame(name = c(traits, controls),
             kind = rep(c("trait", "control"), c(length(traits), length(controls))),
             where = c(vapply(traits, where_trait, character(1)),
                       vapply(controls, where_control, character(1))),
             row.names = NULL, stringsAsFactors = FALSE)
}
