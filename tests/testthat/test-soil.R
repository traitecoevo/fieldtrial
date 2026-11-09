test_that("graded widths thicken with depth and sum to the column exactly", {
  w <- soil_widths_graded(depth = 1.5, n = 5, top = 0.02)
  expect_length(w, 5)
  expect_identical(sum(w), 1.5)
  expect_identical(w[1], 0.02)
  expect_true(all(diff(w) > 0))
  expect_identical(soil_widths_graded(2, 1), 2)
})

test_that("a profile that would thin with depth is refused", {
  expect_error(soil_widths_graded(depth = 1, n = 5, top = 0.3), "thickens with depth")
  expect_error(soil_widths_graded(depth = -1), "positive")
  expect_error(soil_widths_graded(n = 2.5), "whole number")
})
