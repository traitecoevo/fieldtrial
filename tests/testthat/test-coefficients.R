test_that("coefficients are plant's defaults, to the bit", {
  for (model in c("TF24", "FF16")) {
    expected <- attr(plant_frozen(model)(), "coefficients")
    ## TF24's latitude argument was never read; fieldtrial does not carry it.
    if (model == "TF24") expected$latitude <- NULL
    got <- tradeoff_coefficients(model)
    expect_setequal(names(got), names(expected))
    for (name in names(got)) {
      expect_identical(got[[name]], as.numeric(expected[[name]]),
                       label = paste(model, name))
    }
  }
})

test_that("TF24's variants share TF24's coefficients", {
  for (model in c("TF24f", "TF24t", "TF24w")) {
    expect_identical(tradeoff_coefficients(model), tradeoff_coefficients("TF24"))
  }
})

test_that("every coefficient documents its units, meaning and source", {
  for (model in c("TF24", "FF16")) {
    tab <- tradeoff_table(model)
    expect_named(tab, c("name", "value", "units", "description", "source",
                        "reference"))
    expect_true(all(nzchar(tab$units)), label = paste(model, "units"))
    expect_true(all(nzchar(tab$description)), label = paste(model, "descriptions"))
    expect_true(all(nzchar(tab$source)), label = paste(model, "sources"))
  }
})

test_that("a coefficient value is plain arithmetic, nothing else", {
  expect_identical(eval_coefficient("2.0 * 4012.0", "x"), 8024)
  expect_identical(eval_coefficient("-0.2", "x"), -0.2)
  expect_identical(eval_coefficient("21000", "x"), 21000)
  expect_type(eval_coefficient("21000", "x"), "double")
  expect_error(eval_coefficient("system('true')", "x"), "not plain arithmetic")
  expect_error(eval_coefficient("pi", "x"), "not plain arithmetic")
  expect_error(eval_coefficient("(pi)", "x"), "not plain arithmetic")
  expect_error(eval_coefficient("-pi", "x"), "not plain arithmetic")
  expect_error(eval_coefficient("1+2i", "x"), "not plain arithmetic")
  expect_error(eval_coefficient("c(1, 2)", "x"), "not plain arithmetic")
  expect_error(eval_coefficient("1 / 0", "x"), "not a finite number")
  expect_error(eval_coefficient("1e999", "x"), "not a finite number")
  expect_error(eval_coefficient(0.2, "x"), "quoted R numeric expression")
})

test_that("unknown models are refused, K93 with a pointer", {
  expect_error(tradeoff_coefficients("K93"), "hyperpar = NULL")
  expect_error(tradeoff_coefficients("XYZ"), "No trade-offs for model")
  expect_error(tradeoffs(c("TF24", "FF16")), "single model name")
})
