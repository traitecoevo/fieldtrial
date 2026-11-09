## TF24's trade-offs: the shared economic chain, the hydraulic cost scale on
## wood density, the stem vulnerability curve from sapwood conductivity, and
## leaf nitrogen and respiration from leaf mass per area, vcmax_25 and jmax_25.
tf24_tradeoffs <- function(co) {
  force(co)
  function(m, s, filter = TRUE) {
    lma <- trait_values(m, s, "lma")
    rho <- trait_values(m, s, "rho")
    omega <- trait_values(m, s, "omega")
    K_s <- trait_values(m, s, "K_s")
    vcmax_25 <- trait_values(m, s, "vcmax_25")
    jmax_25 <- trait_values(m, s, "jmax_25")

    econ <- economic_tradeoffs(lma, rho, omega, co)

    TF24_cost_scale <- co$B_hks1 * (rho / co$rho_0) ^ (-co$B_hks2)

    ## Stem vulnerability curve exp(-(psi / stem_b) ^ stem_c). stem_b and
    ## psi_crit (95% loss) are derived again by phylloptim from stem_P50 and
    ## stem_c; they are reported here so a strategy's pars agree with its curve.
    if (any(K_s <= 0, na.rm = TRUE)) {
      stop("K_s must be > 0 for stem_P50 derivation", call. = FALSE)
    }
    stem_P50 <- 10^(co$B_Hv1 + co$B_Hv2 * log10(K_s))
    stem_c <- co$B_c1 * exp(-co$B_c2 * stem_P50)
    stem_b <- stem_P50 / ((-log(1 - 50 / 100))^(1 / stem_c))
    psi_crit <- stem_b * (log(1 / 0.05))^(1 / stem_c)

    ## Leaf nitrogen per area: structural from lma (in g m-2), photosynthetic
    ## from vcmax_25 and jmax_25; respiration per unit leaf mass from each.
    narea_ls <- (co$a_lf1 + co$B_lf1 * lma * 1000) / 1000
    narea_lp <- (co$B_lf2 * vcmax_25 + co$B_lf3 * jmax_25) / 1000
    nmass_ls <- narea_ls / lma
    nmass_lp <- narea_lp / lma
    nmass_l <- nmass_ls + nmass_lp
    r_l <- co$B_lf4 * nmass_ls + co$B_lf5 * nmass_lp

    extra <- cbind(k_l = econ$k_l,
                   d_I = econ$d_I, TF24_cost_scale = TF24_cost_scale,
                   k_s = econ$k_s, r_s = econ$r_s, r_b = econ$r_b,
                   a_f3 = econ$a_f3,
                   r_l = r_l, nmass_l = nmass_l,
                   stem_c = stem_c, stem_P50 = stem_P50, stem_b = stem_b,
                   psi_crit = psi_crit)
    append_derived(m, extra, s, filter)
  }
}
