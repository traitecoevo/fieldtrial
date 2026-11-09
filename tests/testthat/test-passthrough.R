## Leaf parameters plant does not forward. None: every leaf trait and control
## is reachable or out of scope. A name appearing here is a plant fix to make.
known_gaps <- character(0)

test_that("every leaf trait and control is reachable, out of scope, or a known gap", {
  skip_if_not_installed("phylloptim")
  pt <- check_passthrough("TF24")
  expect_named(pt, c("name", "kind", "where"))
  gaps <- pt$name[is.na(pt$where)]
  expect_true(all(gaps %in% known_gaps), label = paste("new gaps:", paste(setdiff(gaps, known_gaps), collapse = ", ")))
  expect_identical(pt$where[pt$name == "vcmax_25"], "strategy pars")
  expect_identical(pt$where[pt$name == "CMax_a"], "out of scope")
  expect_identical(pt$where[pt$name == "integration_tol"], "out of scope")
  expect_identical(pt$where[pt$name == "GSS_tol_abs"], "Control")
})

test_that("check_passthrough is for the TF24 family", {
  expect_error(check_passthrough("FF16"), "TF24 family")
})
