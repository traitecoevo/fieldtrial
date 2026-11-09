test_that("TF24 trade-offs match plant's to the bit", {
  ref <- plant_reference("make_TF24_hyperpar")
  s <- plant::TF24_Strategy()
  m <- tf24_grid()
  for (filter in c(FALSE, TRUE)) {
    expect_identical(tradeoffs("TF24")(m, s, filter = filter),
                     ref()(m, s, filter = filter))
  }
  one <- plant::trait_matrix(0.1, "lma")
  for (filter in c(FALSE, TRUE)) {
    expect_identical(tradeoffs("TF24")(one, s, filter = filter),
                     ref()(one, s, filter = filter))
  }
  empty <- matrix(numeric(0), 0, 1, dimnames = list(NULL, "lma"))
  expect_identical(tradeoffs("TF24")(empty, s, filter = FALSE),
                   ref()(empty, s, filter = FALSE))
})

test_that("overridden coefficients match plant's arguments", {
  ref <- plant_reference("make_TF24_hyperpar")
  s <- plant::TF24_Strategy()
  m <- tf24_grid()
  expect_identical(
    tradeoffs("TF24", list(B_Hv2 = -0.3, B_hks2 = 1, B_c2 = 0.1))(m, s, FALSE),
    ref(B_Hv2 = -0.3, B_hks2 = 1, B_c2 = 0.1)(m, s, FALSE))
})

test_that("each TF24 variant matches plant's hyperpar for it", {
  m <- tf24_grid()
  for (model in c("TF24f", "TF24t", "TF24w")) {
    ref <- plant_reference(paste0(model, "_hyperpar"))
    s <- get(paste0(model, "_Strategy"), envir = asNamespace("plant"))()
    expect_identical(tradeoffs(model)(m, s, filter = TRUE),
                     ref(m, s, filter = TRUE), label = model)
  }
})

test_that("the default stem curve is the curve at the default K_s", {
  ## plant's TF24 defaults for the stem vulnerability curve were chosen to lie
  ## on this trade-off (traitecoevo/plant#611). If plant moves either side,
  ## this fails, and the two must be brought back together deliberately.
  s <- plant::TF24_Strategy()
  d <- tradeoffs("TF24")(plant::trait_matrix(s$pars$K_s, "K_s"), s,
                         filter = FALSE)
  for (name in c("stem_P50", "stem_c", "stem_b", "psi_crit")) {
    expect_identical(unname(d[1, name]), s$pars[[name]], label = name)
  }
})

test_that("TF24 refuses what plant refuses", {
  s <- plant::TF24_Strategy()
  f <- tradeoffs("TF24")
  expect_error(f(plant::trait_matrix(0, "K_s"), s), "K_s must be > 0")
  expect_error(f(cbind(lma = 0.1, k_l = 1), s), "overwrite generated parameters")
  expect_error(f(plant::trait_matrix(0, "lma"), s), "infinite value")
  expect_error(tradeoffs("TF24", list(latitude = 30)), "Unknown TF24")
  expect_error(tradeoffs("TF24", list(B_Hv2 = c(1, 2))), "single number")
  expect_null(attr(f, "input_traits"))
})
