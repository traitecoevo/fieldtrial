test_that("the package loads and plant is reachable", {
  expect_true(requireNamespace("plant", quietly = TRUE))
})
