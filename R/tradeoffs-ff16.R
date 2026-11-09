## FF16's trade-offs: the shared economic chain, and leaf nitrogen per area
## setting the annual assimilation curve (a_p1, a_p2) and leaf respiration.
ff16_tradeoffs <- function(co) {
  force(co)
  f <- function(m, s, filter = TRUE) {
    lma <- trait_values(m, s, "lma")
    rho <- trait_values(m, s, "rho")
    omega <- trait_values(m, s, "omega")
    narea <- trait_values(m, s, "narea", co$narea)

    econ <- economic_tradeoffs(lma, rho, omega, co)

    ## The light extinction coefficient comes from the strategy, so the
    ## assimilation integral matches the canopy model the plant is run with.
    k_I <- s$pars$k_I

    a_p1 <- a_p2 <- 0 * narea
    if (length(narea) > 0) {
      i <- match(narea, unique(narea))
      y <- vapply(unique(narea), ff16_annual_assimilation_curve, numeric(2),
                  co = co, k_I = k_I)
      a_p1 <- y["p1", i]
      a_p2 <- y["p2", i]
    }

    ## Respiration per unit leaf area is set by nitrogen; per unit mass it
    ## falls with lma.
    r_l <- co$B_lf4 * narea / lma

    extra <- cbind(k_l = econ$k_l,
                   d_I = econ$d_I, k_s = econ$k_s, r_s = econ$r_s,
                   r_b = econ$r_b,
                   a_f3 = econ$a_f3,
                   a_p1 = a_p1, a_p2 = a_p2,
                   r_l = r_l)
    append_derived(m, extra, s, filter)
  }
  ## narea is read from the trait matrix but is not a parameter of the
  ## strategy, so plant would otherwise refuse it as an unknown trait.
  attr(f, "input_traits") <- "narea"
  f
}

## Annual assimilation [mol CO2 m-2 yr-1] as a function of canopy openness E,
## fitted as p1 * E / (p2 + E). The year is integrated over half its days,
## since the solar path is symmetric.
ff16_annual_assimilation_curve <- function(narea, co, k_I) {
  E <- seq(0, 1, by = 0.02)
  D <- seq(0, 365 / 2, length.out = 10000)
  I <- ff16_PAR_given_solar_angle(ff16_solar_angle(D, latitude = abs(co$latitude)))
  Amax <- co$B_lf1 * (narea / co$narea_0)^co$B_lf5
  theta <- co$B_lf2
  QY <- co$B_lf3
  ## One row per openness, one column per day: row i is plant's integrand at
  ## E[i], computed term for term as plant does, k_I * I * E[i].
  light <- t(outer(k_I * I, E))
  AA <- 2 * trapezium_rows(D, rectangular_hyperbola(light, Amax, theta, QY))
  if (all(diff(AA) < 1e-8)) {
    ## The fit fails on a flat curve, e.g. all zero.
    ret <- c(AA[length(AA)], 0)
    names(ret) <- c("p1", "p2")
  } else {
    fit <- stats::nls(AA ~ p1 * E / (p2 + E), data.frame(E = E, AA = AA),
                      start = list(p1 = 100, p2 = 0.2))
    ret <- stats::coef(fit)
  }
  ret
}

rectangular_hyperbola <- function(I, Amax, theta, QY) {
  x <- QY * I + Amax
  (x - sqrt(x^2 - 4 * theta * QY * I * Amax)) / (2 * theta)
}

## Trapezium rule over x for each row of Y, summed in plant's order and
## precision: plant's C++ adds (x[j+1] - x[j]) * (y[j+1] + y[j]) to a double,
## one interval at a time, and halves the total.
##
## ⚠️ DO NOT REPLACE THE LOOP WITH sum() OR cumsum(). Both accumulate in long
## double, which is 80-bit on x86 Linux, and the assimilation fit downstream
## amplifies the last-bit difference to ~1e-11 in a_p1. The loop runs over the
## intervals with all rows at once, so it costs one vector add per interval.
trapezium_rows <- function(x, Y) {
  n <- length(x)
  if (!is.matrix(Y) || ncol(Y) != n || n < 2L) {
    stop("trapezium_rows() needs a matrix with one column per x, and at ",
         "least 2 of them", call. = FALSE)
  }
  dx <- x[-1L] - x[-n]
  total <- numeric(nrow(Y))
  for (j in seq_len(n - 1L)) {
    total <- total + dx[j] * (Y[, j + 1L] + Y[, j])
  }
  total * 0.5
}

## PAR on a surface normal to the sun [mol m-2 d-1] at solar elevation
## `solar_angle` [rad]: S_atmos [W m-2] outside the atmosphere, tau the
## transmissivity of the shortest path, PAR_frac the PAR share.
ff16_PAR_given_solar_angle <- function(solar_angle, S_atmos = 1360, tau = 0.8,
                                       PAR_frac = 0.5) {
  M <- 1 / cos(pi / 2 - solar_angle)
  mol_per_watt <- 4.6 / 1e+06
  sec_per_day <- 3600 * 24
  ret <- (S_atmos * PAR_frac) * tau^M * mol_per_watt * sec_per_day
  ret[solar_angle <= 0] <- 0
  ret
}

## Solar elevation [rad] at `decimal_day_time` (day of year plus fraction of
## day) and `latitude` [deg].
##
## ⚠️ THE DECLINATION HERE IS sin(declination), USED AS THE ANGLE. Its
## amplitude 0.39785 is sin(23.44 deg), so solstice declination is about 0.6 deg
## low. Kept so FF16's trade-offs match plant's frozen copy; the corrected form
## belongs to the driver code, and changing it here moves a_p1 and a_p2.
ff16_solar_angle <- function(decimal_day_time, latitude) {
  day <- floor(decimal_day_time)
  time <- (decimal_day_time - day) * 24
  radians <- function(x) x / 180 * pi
  lat_radians <- radians(latitude)
  delta <- 0.39785 * sin(4.869 + day / 365 * 2 * pi +
                           0.03345 * sin(6.224 + day / 365 * 2 * pi))
  HrAng <- radians(180 - time * 15)
  SinA <- sin(lat_radians) * sin(delta) +
    cos(lat_radians) * cos(delta) * cos(HrAng)
  asin(SinA)
}
