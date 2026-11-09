test_that("FF16 trade-offs match plant's to the bit", {
  ref <- plant_frozen("FF16")
  s <- plant::FF16_Strategy()
  m <- ff16_grid()
  for (filter in c(FALSE, TRUE)) {
    got <- tradeoffs("FF16")(m, s, filter = filter)
    expected <- ref()(m, s, filter = filter)
    expect_identical(got, expected)
  }
})

test_that("FF16 matches plant on a one-trait and an empty matrix", {
  ref <- plant_frozen("FF16")
  s <- plant::FF16_Strategy()
  one <- plant::trait_matrix(0.1, "lma")
  empty <- matrix(numeric(0), 0, 1, dimnames = list(NULL, "narea"))
  for (filter in c(FALSE, TRUE)) {
    expect_identical(tradeoffs("FF16")(one, s, filter = filter),
                     ref()(one, s, filter = filter))
    expect_identical(tradeoffs("FF16")(empty, s, filter = filter),
                     ref()(empty, s, filter = filter))
  }
})

test_that("FF16 at another latitude matches plant", {
  ref <- plant_frozen("FF16")
  s <- plant::FF16_Strategy()
  m <- ff16_grid()
  expect_identical(tradeoffs("FF16", list(latitude = 30))(m, s, FALSE),
                   ref(latitude = 30)(m, s, FALSE))
})

test_that("FF16 declares narea as a trait it reads but does not assign", {
  f <- tradeoffs("FF16")
  expect_identical(attr(f, "input_traits"),
                   attr(plant_frozen("FF16")(), "input_traits"))
})

test_that("a flat assimilation curve is returned without a fit", {
  s <- plant::FF16_Strategy()
  ## No light reaches the leaf, so every openness gives the same assimilation.
  s$pars$k_I <- 0
  got <- tradeoffs("FF16")(plant::trait_matrix(1.87e-3, "narea"), s,
                           filter = FALSE)
  expect_identical(unname(got[1, "a_p2"]), 0)
})

test_that("the trapezium rule integrates each row, in plant's order", {
  x <- seq(0, 2, length.out = 11)
  Y <- rbind(3 * x + 1, -x)
  expect_equal(trapezium_rows(x, Y), c(8, -2))
  ## plant's sum: one interval at a time, in double precision.
  y <- sin(x * 7)
  total <- 0
  for (j in seq_len(length(x) - 1L)) {
    total <- total + (x[j + 1L] - x[j]) * (y[j + 1L] + y[j])
  }
  expect_identical(trapezium_rows(x, matrix(y, nrow = 1)), total * 0.5)
  expect_error(trapezium_rows(1, matrix(1)), "at least 2")
})
