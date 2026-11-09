test_that("strategies built through plant are the same with either copy", {
  for (spec in list(list("TF24", "TF24_hyperpar", c(0.1, 0.25), "lma"),
                    list("FF16", "FF16_hyperpar", c(0.1, 0.25), "lma"))) {
    ref <- plant_reference(spec[[2]])
    p <- plant::scm_base_parameters(spec[[1]])
    traits <- plant::trait_matrix(spec[[3]], spec[[4]])
    birth_rate <- rep(1, nrow(traits))
    a <- plant::add_strategies(p, traits, tradeoffs(spec[[1]]),
                               birth_rate = birth_rate, keep_existing = FALSE)
    b <- plant::add_strategies(p, traits, ref, birth_rate = birth_rate,
                               keep_existing = FALSE)
    for (i in seq_along(spec[[3]])) {
      expect_equal(a$strategies[[i]]$pars, b$strategies[[i]]$pars,
                   tolerance = 1e-12, label = paste(spec[[1]], "strategy", i))
    }
  }
})

test_that("plant accepts narea through FF16's declared input trait", {
  p <- plant::scm_base_parameters("FF16")
  expect_no_error(plant::add_strategies(
    p, plant::trait_matrix(2e-3, "narea"), tradeoffs("FF16"),
    keep_existing = FALSE))
})
