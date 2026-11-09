## The committed baseline is plant's own output (data-raw/make-tradeoff-baseline.R),
## so these hold without plant's trade-off functions and catch a change on this
## side that plant would not see.
##
## The baseline was written on one platform and is read on others. pow(),
## log10() and the solar trigonometry come from the platform's maths library,
## which may round the last bit differently (glibc and macOS differ in stem_P50),
## so this is a check to within that rounding, not to the bit; the comparisons
## against a live plant on the same platform are the bit-for-bit ones. FF16's
## assimilation fit amplifies its last-bit inputs, hence its looser tolerance.
baseline <- readRDS(test_path("fixtures", "tradeoff-baseline.rds"))

test_that("TF24 reproduces the committed plant baseline", {
  expect_equal(
    tradeoffs("TF24")(baseline$grids$TF24, baseline$strategy, filter = FALSE),
    baseline$TF24, tolerance = 1e-14)
})

test_that("FF16 reproduces the committed plant baseline", {
  expect_equal(
    tradeoffs("FF16")(baseline$grids$FF16, baseline$strategy, filter = FALSE),
    baseline$FF16, tolerance = 1e-9)
  expect_equal(
    tradeoffs("FF16", list(latitude = 30))(baseline$grids$FF16,
                                           baseline$strategy, filter = FALSE),
    baseline$FF16_latitude_30, tolerance = 1e-9)
})
