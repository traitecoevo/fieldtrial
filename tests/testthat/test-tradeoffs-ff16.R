## plant integrates the assimilation curve with a C++ sum; the R sum here can
## differ in the last bits on some platforms, so FF16 is compared to rounding.
ff16_tolerance <- 1e-12

test_that("FF16 trade-offs match plant's to rounding", {
  ref <- plant_reference("make_FF16_hyperpar")
  s <- plant::FF16_Strategy()
  m <- ff16_grid()
  for (filter in c(FALSE, TRUE)) {
    got <- tradeoffs("FF16")(m, s, filter = filter)
    expected <- ref()(m, s, filter = filter)
    expect_identical(colnames(got), colnames(expected))
    expect_equal(got, expected, tolerance = ff16_tolerance)
  }
})

test_that("FF16 matches plant on a one-trait and an empty matrix", {
  ref <- plant_reference("make_FF16_hyperpar")
  s <- plant::FF16_Strategy()
  one <- plant::trait_matrix(0.1, "lma")
  empty <- matrix(numeric(0), 0, 1, dimnames = list(NULL, "narea"))
  for (filter in c(FALSE, TRUE)) {
    expect_equal(tradeoffs("FF16")(one, s, filter = filter),
                 ref()(one, s, filter = filter), tolerance = ff16_tolerance)
    expect_identical(tradeoffs("FF16")(empty, s, filter = filter),
                     ref()(empty, s, filter = filter))
  }
})

test_that("FF16 at another latitude matches plant", {
  ref <- plant_reference("make_FF16_hyperpar")
  s <- plant::FF16_Strategy()
  m <- ff16_grid()
  expect_equal(tradeoffs("FF16", list(latitude = 30))(m, s, FALSE),
               ref(latitude = 30)(m, s, FALSE), tolerance = ff16_tolerance)
})

test_that("FF16 declares narea as a trait it reads but does not assign", {
  f <- tradeoffs("FF16")
  expect_identical(attr(f, "input_traits"),
                   attr(plant_reference("make_FF16_hyperpar")(), "input_traits"))
})

test_that("a flat assimilation curve is returned without a fit", {
  s <- plant::FF16_Strategy()
  ## No light reaches the leaf, so every openness gives the same assimilation.
  s$pars$k_I <- 0
  got <- tradeoffs("FF16")(plant::trait_matrix(1.87e-3, "narea"), s,
                           filter = FALSE)
  expect_identical(unname(got[1, "a_p2"]), 0)
})

test_that("the trapezium rule integrates exactly where it should", {
  x <- seq(0, 2, length.out = 11)
  expect_equal(trapezium(x, 3 * x + 1), 8)
  expect_error(trapezium(1, 1), "at least 2")
})
