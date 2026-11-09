## The leaf- and wood-economics trade-offs FF16 and TF24 share: leaf mass per
## area sets leaf turnover; wood density sets intrinsic mortality, sapwood
## turnover and the respiration of sapwood and bark per unit mass; the seed
## accessory cost scales with seed mass.
##
## The expressions are plant's, term for term, so the doubles are plant's.
economic_tradeoffs <- function(lma, rho, omega, co) {
  list(
    k_l = co$B_kl1 * (lma / co$lma_0) ^ (-co$B_kl2),
    d_I = co$B_dI1 * (rho / co$rho_0) ^ (-co$B_dI2),
    k_s = co$B_ks1 * (rho / co$rho_0) ^ (-co$B_ks2),
    ## Respiration per unit volume is held constant, so per unit mass it falls
    ## with density.
    r_s = co$B_rs1 / rho,
    r_b = co$B_rb1 / rho,
    a_f3 = co$B_f1 * omega)
}
