met_example <- function(from = "2001-01-01", to = "2003-12-31") {
  date <- seq(as.Date(from), as.Date(to), by = "day")
  n <- length(date)
  data.frame(date = date,
             SWdown_noon = 900 + 100 * cos(2 * pi * seq_len(n) / 365),
             VPD_noon = 1.5 + 0.5 * cos(2 * pi * seq_len(n) / 365),
             VPD_amp = rep(0.4, n),
             Tair_mean = 20 + 8 * cos(2 * pi * seq_len(n) / 365),
             Precip = ifelse(seq_len(n) %% 7 == 0, 10, 0),
             Psurf = rep(95, n), CO2air = rep(410, n))
}

test_that("a well-formed table validates", {
  expect_silent(validate_met(met_example()))
  expect_setequal(met_schema()$column, c("date", "SWdown_noon", "SWdown_mean",
    "VPD_noon", "VPD_amp", "Tair_mean", "Tair_max", "Tair_min", "Precip",
    "Wind", "Psurf", "CO2air"))
})

test_that("validation refuses what plant cannot use", {
  m <- met_example()
  expect_error(validate_met(cbind(m, rain = 1)), "Unknown met column")
  expect_error(validate_met(m[-10, ]), "consecutive days")
  bad <- m; bad$VPD_noon[5] <- NA
  expect_error(validate_met(bad), "missing value")
  bad <- m; bad$VPD_amp[3] <- 1
  expect_error(validate_met(bad), "VPD_amp")
  bad <- m; bad$Psurf[2] <- 950
  expect_error(validate_met(bad), "Psurf")
  bad <- m; bad$date <- as.character(bad$date)
  expect_error(validate_met(bad), "class Date")
})

test_that("a climatology is the mean of each day of year", {
  m <- met_example("2001-01-01", "2004-12-31")
  attr(m, "latitude") <- -22.28
  clim <- met_climatology(m)
  expect_identical(nrow(clim), 365L)
  expect_equal(clim$date[1], as.Date("2001-01-01"))
  jan5 <- format(m$date, "%m-%d") == "01-05"
  expect_equal(clim$SWdown_noon[5], mean(m$SWdown_noon[jan5]))
  expect_identical(attr(clim, "latitude"), -22.28)
  expect_identical(attr(clim, "climatology_of"), c(2001L, 2004L))
  expect_error(met_climatology(met_example("2001-02-01", "2001-12-31")), "no complete year")
})

test_that("repeated years cover the run, leap days included", {
  clim <- met_climatology(met_example())
  r <- met_repeat(clim, 4)
  expect_equal(r$date[1], as.Date("2001-01-01"))
  expect_equal(r$date[nrow(r)], as.Date("2004-12-31"))
  expect_silent(validate_met(r))
  ## 2004 is a leap year; its 29 February takes the 28th's values.
  expect_identical(attr(r, "climatology_of"), attr(clim, "climatology_of"))
  feb29 <- which(r$date == as.Date("2004-02-29"))
  expect_identical(r$SWdown_noon[feb29], r$SWdown_noon[feb29 - 1])
  expect_error(met_repeat(met_example("2001-03-01", "2002-12-31"), 3), "whole years")
})
