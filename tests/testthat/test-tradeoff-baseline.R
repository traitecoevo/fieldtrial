## The committed baseline is plant's own output (data-raw/make-tradeoff-baseline.R),
## so these hold without plant's trade-off functions and catch a change on this
## side that plant would not see.
baseline <- readRDS(test_path("fixtures", "tradeoff-baseline.rds"))

test_that("TF24 reproduces the committed plant baseline to the bit", {
  expect_identical(
    tradeoffs("TF24")(baseline$grids$TF24, baseline$strategy, filter = FALSE),
    baseline$TF24)
})

test_that("FF16 reproduces the committed plant baseline to rounding", {
  expect_equal(
    tradeoffs("FF16")(baseline$grids$FF16, baseline$strategy, filter = FALSE),
    baseline$FF16, tolerance = 1e-12)
  expect_equal(
    tradeoffs("FF16", list(latitude = 30))(baseline$grids$FF16,
                                           baseline$strategy, filter = FALSE),
    baseline$FF16_latitude_30, tolerance = 1e-12)
})
