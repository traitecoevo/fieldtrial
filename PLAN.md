# Scoping `fieldtrial`: parameter sets + environmental drivers for `plant`

Status: scoped 2026-11-09. Phases 0, 1, 2a and WorldClim done (fieldtrial#2–#5; plant-meta#9). Phases 3 and 6 (plant PR A with PR B folded in) merged as plant#731 (develop@218501e1, 2026-11-10). Phase 4 set machinery in review; the first real sets wait on cited trait values. Decisions taken by the maintainers are marked **Decided**. This file is the single source of truth for the work: keep it current, mark phases done, and retire inventory that no longer holds.

## Context

plant runs "out of the box" on defaults that record a development history rather than any species or site (#697). The trait→parameter trade-off functions (`*_hyperpar`) and the few driver generators plant has are mixed into the model package, the light driver is a constant (#701), and the parameter surface is opaque to users (#698). Nothing in the family holds a species parameter set or reads a gridded climate product; the only extraction code is a maintainer's standalone AGCD script plus two copies in projects outside the family. Verbruggen's `capabilities.md` records the gap bluntly: "no reader for daily/half-hourly met files anywhere".

`fieldtrial` will own: (1) named parameter sets for species and sites, (2) the trait trade-off functions and their coefficient sets, moved out of plant and simplified, (3) workflows that turn gridded and flux-tower climate into plant driver series, Australia first.

## Decisions

- **Decided: the recommended trade-off functions move to fieldtrial.** plant keeps the contract `f(m, s, filter = TRUE)` (+ optional `attr(f, "input_traits")`) and no longer applies any trade-off silently.
- **Decided: plant keeps one frozen *testing* parameter set, explicitly loaded.** It is the current defaults plus the current trade-off functions, so every golden and test in plant stays self-contained without fieldtrial. It is reached only through an explicit call (`default_parameters(model)`), which warns that this is a testing set and not a recommended parameterisation of any species or site. The bare `base_parameters(model)` attaches no trade-offs: traits are written straight to `pars`. Consequence accepted: two copies of the forms exist, plant's frozen (changing it means re-blessing goldens) and fieldtrial's live (science evolves there). A bit-identity test in fieldtrial records when they diverge.
- **Decided: a `Parameters` object carries its own trade-offs.** `param_hyperpar(p)` reads them from `p`; identity when none are attached. This is what lets regnans, logpile and fieldtrial sets all work through the same plant API without plant naming fieldtrial.
- **Decided: first sets are mulga at Alice Springs (TF24) and a tall eucalypt (TF24); `mulga_delta` follows shortly** (Delta is one of the four mulga monitoring sites in `mulga_plots_data`, with Barcheka, Bendemere and Corrie Downs; no flux tower, so its met is AGCD plus gap-fill).
- **Decided: pass-through scope is every parameter of the TF24 (TF24_floor cost curve) model, including TF24t's thermal fields, and no other stomatal model's parameters for now.** Sets carry a `model:` key and `check_passthrough(model)` is per model, so swapping models later is a new row, not a redesign.
- **Decided: climate sources are pluggable adapters, with several in the first release:** FLUXNET Shuttle site packages (ONEFlux FULLSET half-hourly, CC-BY, 700+ sites, TERN's OzFlux towers released as `2026_r1`) as the primary site source, with PLUMBER2 NetCDF as a second reader of the same quantities; AGCD (Australia, monthly, from the existing extraction script); global grids WorldClim 2.1 (monthly climatology) and CRU TS (monthly series, 1901 onward). SILO, TerraClimate and ERA5-Land are later adapters.
- **Decided: the canonical met table carries noon values and diurnal amplitudes, not daytime means.** This follows plant: `SWdown`'s default 900 W m⁻² is documented as clear-sky midday, and the `experiment/618-daily-integral` branch defines `SWdown(t)` and `atm_vpd(t)` as values at solar noon and rebuilds the day from latitude and a VPD amplitude driver. Daily means and extremes are kept as extra columns for diagnostics and for TF24t.
- **Decided: public repo.** Private field data (mulga_plots_data) is cited, never committed; only derived publishable series ship.
- **Decided: fieldtrial joins the plant-family workspace and plant-meta** (clone, dependency map, AGENTS.md tables, label sync list, board auto-add).
- Dependency direction is one way: `fieldtrial` Imports `plant` (pinned by sha via `Remotes: traitecoevo/plant@<sha>` and a `.plant-interface-version` file recording the same ref and the breaking changes absorbed, the regnans pattern; move both together). plant does not need fieldtrial for its tests; it may list it in Suggests for one optional integration test.

## Inventory: what exists today

### In `plant` (develop, verified 2026-11-09)

**Hyperparameter functions are R-only.** No `hyperpar` symbol in `src/` or `inst/include`; the function runs when a strategy is built and writes into `strategy$pars`.

| Function | Where | Encodes |
|---|---|---|
| `make_FF16_hyperpar()` / `FF16_hyperpar` | `plant/R/ff16.R:115`, `:319` | lma→k_l; rho→d_I, k_s, r_s, r_b; omega→a_f3; narea+latitude→a_p1, a_p2 by integrating a solar-driven PAR day (`solar_angle`, `PAR_given_solar_angle`, unexported C++ `trapezium`) then an `nls` fit; narea, lma→r_l. Reads `s$pars$k_I`. Sets `input_traits = "narea"`. |
| `make_TF24_hyperpar()` / `TF24_hyperpar` | `plant/R/tf24.R:116`, `:312` | same economic chain; rho→TF24_cost_scale; K_s→stem_P50→stem_c→stem_b, psi_crit (`B_Hv1` re-anchored for #615); lma, vcmax_25, jmax_25→nmass_l, r_l (Dong 2022). 13 derived params. `latitude` accepted, unused. |
| `make_TF24f/t/w_hyperpar` | `tf24f.R:85`, `tf24t.R:41`, `tf24w.R:84` | pass-through to TF24 |
| `make_K93_hyperpar` | `k93.R:34` | identity |
| `make_hyperpar(type)`, `param_hyperpar(p)`, `hyperpar(type)` | `strategy_support.R:9, 22, 38` | `switch()` dispatch |
| `TF24_H_ANCHOR`, `TF24_K_s_from_whole_stem()` | `tf24.R:335`, `:361` | calls internal C++; **stays in plant** |

Contract consumers in plant: `generate_strategy` (`util_model.R:26`, default `hyperpar = param_hyperpar(p)`), `add_strategies` (`:188`), `add_mutant` (`:224`), `stand_gradient` + `trade_off()` (`stand_gradient.R:223, 287, 336`; calls hyperpar with an empty matrix and `filter = FALSE` to list derived columns), `fixed_point_fitness` (`continuous_patch.R:316`), `optimise_individual_rate_at_size_by_trait` (`individual.R:275`), `build_scenario` (`scenario_eval.R:156`, hard-codes `TF24_hyperpar`).

Outside plant: regnans calls `plant::param_hyperpar`, `generate_strategy(hyperpar=)`, `add_mutant(hyperpar=)`, `stand_gradient(hyperpar=)` (`regnans/R/community_plant.R:59, 74, 310, 354, 363`). logpile hashes `plant::make_hyperpar(model_type)` (`logpile/R/fingerprint.R:211`, `solver.R:23`).

**Cross-repo invariant created by the move:** TF24's C++ default `stem_P50 = 2.8887` is "TF24_hyperpar's value at the default K_s" (#611); `B_Hv1 = 0.36591565…` was re-anchored so the K_s→P50 chain survived the tip-conductivity change (#615). plant's `test-model-version.R` snapshots struct defaults, not coefficients.

**Drivers: plant keeps the store, has almost no generators.** Store is `odelia::drivers::Drivers` wrapped by `Environment` (`inst/include/plant/environment.h:116-146`), monotone Hermite, time = patch age in years. Only `TF24_Environment` exposes `extrinsic_drivers_set_constant / set_variable / evaluate / evaluate_range` to R. TF24 drivers and defaults (`tf24_environment.h:89-112`): `SWdown` 900 W m⁻² (replaced `PPFD`; `PPFD_above = 4.57 * f_PAR * SWdown`), `rainfall` 1 m yr⁻¹, `atm_vpd` 1 kPa, `ca` 40 Pa, `leaf_temp` 25 °C (air temperature on the PM/TF24t path), `atm_o2_kpa` 21, `atm_kpa` 101.3, `wind_speed` 2.0 m s⁻¹. Soil water is state; soil parameters are fields set via `set_tf24_soil()`.

Pure-R generators that move: `R/pulse_series.R` (`pulse_series_poisson/regular/record/fit/markov`; `_fit` is a seasonal first-order Markov daily-rain generator), `R/solar_model.R` (`solar_angle`, `PAR_given_solar_angle`), `soil_widths_graded` (`R/tf24_soil.R:70`), the inline sinusoid in `build_scenario` (`scenario_eval.R:166-194`). Thin C++ clients that stay: `check_driver_interpolation` (`R/drivers.R`, doc stale: says cubic overshoot, drivers are monotone), `set_tf24_soil`, `R/events.R`, `R/tf24_events.R` (`rainfall_pulse`). Dead: `R/root_uptake.R` (unexported, uncalled) — delete.

Parameter-set-like artefacts: `inst/scenarios/model_scenarios_hydraulic.csv` (8 qualitative scenarios) + `scenario_mapping.csv` (18 rows: level → `rainfall_mean`, `K_sat`, `K_s`, `vcmax_25`, `lma`, `rho`, `theta`, `root_depth_shape_eta`). No `data/`, `data-raw/`, `inst/extdata/`. Species only in C++ comments ("default Eucalyptus saligna", *Acacia aneura*). `inst/docs/FF16/FF16-params-hyper.csv` documents hyperpar symbols.

Blast radius: ~37 test files call `*_hyperpar` directly; ~50 call `trait_matrix`/`add_strategies`; `inst/reports/FF16_report.Rmd`; `overstorey_staging/*`; overstorey guides; regnans; logpile.

### In sibling repos (verified 2026-11-09)

| Repo | Relevant content |
|---|---|
| `regnans` | No species/site content. Consumer of the hyperpar contract via `plant::param_hyperpar` default. Never touches drivers. |
| `mulgafutures` | `framework/plan.md:164-170`: drivers exogenous, a "driver realisation (history joined to one forecast draw)" shared across runs; Tier 1a climate history; node DR1. The forecast-draw side belongs to floracle. |
| `mulga_plots_data` | Barcheka NSW 15-min loggers from 2025-07 (soil T, moisture, sap flow). Private. |
| `mulga-library` | `reports/arid-zone hydrology/PLAN.md:64-71`: calibration sites Fowlers Gap, Alice Springs Mulga OzFlux, Charleville, QLD mulga; "AGCD rainfall". |
| `microclimf` | Unmodified clone of Maclean's v2.0.0. Hourly `climdata` schema (temp, relhum, pres, swdown, difrad, lwdown, windspeed, winddir, precip); bundled USDA `soilparameters.rda`. Optional downscaling stage, not a dependency now. |
| `Verbruggen` | `capabilities.md:19-26, 158`: no met-file reader; drivers must be daily daytime means (no diurnal cycle); rain must not be splined; no bundled CO₂ history; VPD supplied directly. Forcing: ERA5-Land, MSWEP, FLUXNET, GLEAM; soil via Cosby → `set_soil_parameters()`. |
| `phytofile` | `data/ff16_parameters.csv`, `data/wright_2004_locations.csv` (lat, lon, MAT, MAP). Reads `make_FF16_hyperpar` defaults (`R/ms_tables.R:30`). |
| `overstorey` | `guides/extrinsic-drivers.qmd` still says `PPFD 1800`; `posts/2026-06-15-awra-soil-water/` is a soil-driver precedent. |
| `ATLS` | TF24t temperature-response table `meetings/2026.10/temp_model/R/params.R`. |
| `floracle` | Empty. Forecast loop (#521) stays there. |

**AGCD extraction already exists as a standalone R script** held by the maintainers (terra only; sites CSV → long monthly CSV; one NetCDF per year; forces EPSG:4326; lon/lat swap check; 1e20 fill check; variables `precip/total`, `tmax/mean`, `tmin/mean`, `vapourpres_h09/mean`). The source is AGCD v2 on NCI (`gadi:/g/data/zv2/agcd`); a local copy of monthly precipitation 1900–2023 at 0.05° exists, and two mulga projects already hold outputs made with the script. It becomes `extract_agcd()` here.

## Design

### Package layout

```
fieldtrial/                       R package, Imports plant (sha-pinned), terra, yaml; Suggests ncdf4, testthat
  PLAN.md                         this document, trimmed to open work
  .plant-interface-version        plant sha + migrations applied (regnans pattern)
  R/tradeoffs.R                   tradeoffs(model, coefficients) -> hyperpar closure; the contract plant expects
  R/tradeoffs-economic.R          shared lma/rho/omega forms used by FF16 and TF24
  R/tradeoffs-ff16.R              narea+latitude -> a_p1, a_p2 (solar-day integral + nls), with its own trapezium()
  R/tradeoffs-tf24.R              K_s -> stem curve; lma/vcmax/jmax -> r_l
  R/parameter_set.R               parameter_set(name), check_set(), list_sets()
  R/met.R                         canonical daily met table, validate_met(), met_climatology(), met_sources()
  R/met_from_*.R                  one adapter per source: fluxnet, plumber2, agcd, worldclim, cru
  R/apply_drivers.R               apply_drivers(env, met, t0, rainfall = c("pulse", "spline"))
  R/pulse_series.R                moved from plant unchanged
  R/solar.R                       solar_angle(), PAR_given_solar_angle(), swdown_clear_sky(lat, doy)  (#701)
  R/soil.R                        soil_widths_graded() (moved), cosby_from_texture() (Verbruggen)
  R/extract_agcd.R                the standalone AGCD script, as a function
  inst/tradeoffs/{FF16,TF24}.yml  coefficient sets with per-coefficient source citations
  inst/sets/*.yml                 parameter sets
  inst/extdata/met/*.csv          small derived daily series only; never raw NetCDF
  tests/testthat/
```

### Trade-offs (the hyperpar move, simplified)

`fieldtrial::tradeoffs(model, coefficients = tradeoff_coefficients(model))` returns a closure satisfying plant's contract. Simplifications applied during the port:

- One TF24 set serves TF24, TF24f, TF24t, TF24w (lookup maps variant → family). The four pass-throughs disappear.
- K93's identity hyperpar disappears; plant's identity fallback covers it.
- TF24's unused `latitude` argument is dropped.
- The economic chain shared by FF16 and TF24 (lma→k_l; rho→d_I, k_s, r_s, r_b; omega→a_f3) is one function; FF16 adds the assimilation fit, TF24 adds the hydraulic and nitrogen chains. `tradeoffs()` composes them.
- Coefficients live in `inst/tradeoffs/<model>.yml` with `value`, `units`, `source` per coefficient. That file is the #698 table of trade-off parameters; plant's new `parameter_table(model)` covers the rest (see plant changes).
- FF16's `trapezium` dependency on unexported plant C++ is replaced by a three-line R version.
- Later, optional: a declarative table of forms (power law `B1*(x/x0)^-B2`, linear, special) replacing hand-written code. Not in phase 1.

Port discipline: before plant removes anything, fieldtrial's tests assert bit-identity of `tradeoffs("TF24")(m, s, filter = FALSE)` against `plant::TF24_hyperpar(m, s, filter = FALSE)` over a trait grid, and likewise FF16. The baseline is plant's current output, committed as a fixture (porting numerics needs a committed baseline).

Cross-repo invariant test, in fieldtrial: `tradeoffs("TF24")` at plant's default traits reproduces `TF24_Model()$pars[c("stem_P50", "stem_c", "stem_b", "psi_crit")]`. The `B_Hv1` entry in `TF24.yml` documents that the K_s→P50 slope acts on tip conductivity since #615 and names #49 as the open question on the height exponent.

**As implemented in phase 1** (plant develop@ae869f13). These constrain later edits:

- **Coefficient values are quoted R arithmetic expressions** (`value: "2.0 * 4012.0"`), evaluated by an arithmetic-only reader (`eval_coefficient()`). YAML's number parser gives a different double from R's for `B_Hv1 = 0.36591565341924093`, and reads `21000` as an integer; with R's parser every coefficient is identical to plant's formals. Do not switch a value to a bare YAML number.
- **Both models match plant to the bit on the same platform** (216-row TF24 grid, both `filter` settings, overrides, all three TF24 variants, FF16 at two latitudes, empty and one-trait matrices; checked on macOS arm64 and ubuntu x86-64 CI). FF16's assimilation integral is summed by `trapezium_rows()` one interval at a time in double precision, as plant's C++ does: R's `sum()` and `cumsum()` accumulate in 80-bit long double on x86 Linux, and the `nls` fit amplified that to 3.5e-11 in `a_p1`. Do not vectorise that loop.
- **Across platforms, agreement is to libm rounding, not the bit.** The committed baseline (written on macOS) and plant's C++ default stem curve differ from glibc's `pow()` by one ulp in `stem_P50`; those two checks use a tolerance of 1e-14 (TF24) and 1e-9 (FF16, whose fit amplifies trigonometry rounding).
- **FF16 keeps plant's solar model unchanged, declination slip included** (`ff16_solar_angle()` uses sin δ as δ, about 0.6° low at the solstices). Correcting it moves `a_p1` and `a_p2`, so it is a deliberate science change for a later PR, not part of the port. The driver code (phase 2) uses the corrected form.
- **The committed baseline** `tests/testthat/fixtures/tradeoff-baseline.rds` is plant's own output (recording the ref in `.plant-interface-version`), written by `data-raw/make-tradeoff-baseline.R` from a plain-list strategy and a full trait grid, so it does not depend on plant's C++ defaults and keeps testing the port after plant's copy changes.
- `tradeoffs("K93")` is refused with a pointer to `hyperpar = NULL`. The closure carries `attr(f, "model")` and `attr(f, "coefficients")`.
- **Open:** every coefficient's `source` is "plant default"; the `reference` fields (Zotero keys for Falster et al. and Dong et al. 2022) are empty until they are traced.

### plant changes

PR A: trade-offs travel with `Parameters`; the testing set is explicit.

- `Parameters` gains a `hyperpar` slot (an R closure, or `NULL`). `param_hyperpar(p)` returns `p$hyperpar %||% identity_hyperpar`. `generate_strategy`, `add_strategies`, `add_mutant`, `stand_gradient`, `fixed_point_fitness` keep their `hyperpar = param_hyperpar(p)` defaults and so read it from `p`; passing `hyperpar =` explicitly still overrides. The contract is unchanged, so regnans's call sites (`community_plant.R:59, 74, 310, 354, 363`) need no edit once it loads its `p` from a set or from `default_parameters()`.
- New `default_parameters(model, quiet = FALSE)`: `scm_base_parameters(model)` with plant's frozen trade-offs attached and the current C++ defaults; warns "plant's testing parameter set, not a recommended parameterisation of any species or site; see fieldtrial for curated sets". The current `make_FF16_hyperpar` / `make_TF24_hyperpar` bodies move to `R/default_parameters.R` as internal, frozen functions; the K93 identity and the TF24f/t/w pass-throughs go. A testthat helper `testing_parameters(model)` calls it with `quiet = TRUE`; the ~37 tests that named `TF24_hyperpar` use `param_hyperpar(p)` or the helper, and the ~50 that used `add_strategies` defaults switch `scm_base_parameters` → `testing_parameters`. Goldens do not move.
- Bare `scm_base_parameters(model)` attaches nothing: a trait is written straight to `pars`, and `generate_strategy` informs once per session that no trade-offs are attached. `hyperpar = NULL` keeps meaning explicit identity.
- The exported `*_hyperpar`, `make_*_hyperpar`, `make_hyperpar(type)`, `hyperpar(type)` become deprecation shims for one minor release: they return the frozen testing trade-offs with a warning pointing at `default_parameters()` and fieldtrial. logpile's `plant::make_hyperpar(model_type)` (`fingerprint.R:211`, `solver.R:23`) keeps working through the shim, and logpile should switch to hashing `param_hyperpar(p)` before the shim goes.
- `build_scenario()` (`scenario_eval.R:156`) uses `default_parameters("TF24", quiet = TRUE)` instead of the hard-coded `TF24_hyperpar`.
- Add `parameter_table(model)`: traits a trade-off reads, derived parameters (`colnames(f(matrix(numeric(0), 1, 0), s, filter = FALSE))`), remaining `pars`, control knobs, from the C++ struct and `inst/docs` CSVs. Answers #698's "comprehensive list with groupings".
- Delete `R/root_uptake.R`. Fix `R/drivers.R` doc (monotone, not cubic). Fix the shadowing local in `TF24_Environment`'s constructor (`tf24_environment.h:81`).
- Add `g_min` to `TF24_Pars` (default 0.0, forwarded to the leaf in place of the literal), and any other leaf-side name `check_passthrough()` reports, so a set can reach every leaf trait through `pars`.
- Let `generate_strategy()` assign TF24t's top-level thermal fields when named in the trait matrix (validated against `parameter_table("TF24t")`), so one mechanism covers `pars` and strategy fields.
- When the 618 design lands in plant proper (`latitude`, `vpd_peak_hour`, `atm_vpd_diurnal_amp`, `Control$daily_integration`), fieldtrial's `apply_drivers()` already writes those three; until then it writes the noon values to `SWdown`/`atm_vpd` and ignores `VPD_amp`, which is bit-identical to today's one-solve path.
- The stem_P50 pin (#611) stays testable inside plant against the frozen copy; fieldtrial tests its own copy against the same C++ defaults.

Scientific version: unchanged by PR A, since the testing set reproduces today's numbers.

**As implemented in PR A** (plant#731, branch `feat/parameters-hyperpar`, 2026-11-10). These constrain later edits:

- **The carrier is a C++ field.** `Parameters` is an RcppR6 list class whose constructor refuses unknown names and whose validator rebuilds the R list from the C++ struct, so neither an extra list element nor an R attribute survives `validate()` or `scm$parameters`. `Parameters<T,E>` therefore gained a `SEXP`-typed field `hyperpar` (yml type `SEXP`; struct member `plant::RObjectHandle`, a preserve/release holder written against `RcppCommon.h` because `parameters.h` is included before `Rcpp.h`). C++ never reads it. `p$hyperpar <- NULL` removes the list element, and the generated converter's `containsElementNamed` guard reads that as NULL, so removal and NULL are the same state.
- **`param_hyperpar(p)` returns `p$hyperpar`, or an identity closure flagged `attr(, "unattached")`** when none is attached. `generate_strategy()` informs once per session on the flagged identity and is silent on `hyperpar = NULL` (explicit identity). `stand_gradient()` treats any identity as the partial-derivative path.
- **`default_hyperpar(model, ...)` is exported**: the frozen testing trade-off closure (TF24's for TF24/TF24f/TF24t/TF24w; the identity for K93), with coefficient overrides through `...`. fieldtrial's bit-identity test must compare against it once its plant pin passes plant#731, which removed `plant::TF24_hyperpar` outright (PR B was folded in; there is no deprecation release). The closure also carries `attr(f, "coefficients")`, the coefficients it was built with, the shape fieldtrial's own closures use. It carries `attr(f, "traits")`, every trait-matrix column it reads, beside the older `input_traits` (the subset that are not `pars` fields); `parameter_table()` reads both, so a fieldtrial closure that sets `traits` is classified fully.
- **`parameter_table(x, hyperpar = NULL)`** takes a model name or a `Parameters`, returns a tibble (`name`, `group`, `default` as text, `description`, `symbol`, `unit`) with groups `trait`, `derived`, `parameter`, `strategy` (numeric top-level fields: TF24t's thermal set, TF24f's `k_acclim` and `psi_fd_step`) and `control`. Descriptions come from `inst/docs/FF16/FF16-params-core.csv` by code name; TF24-only names have none yet.
- **`generate_strategy()` assigns any numeric top-level strategy field named in a trait matrix** (not only TF24t's), one at a time beside `pars`; a logical field (TF24f's `use_ad_gradient`) is refused as an unknown trait. So a set's `strategy:` block can be folded into the trait matrix for every numeric field.
- **`g_min` is appended to `TF24_Pars`** (default 0, written to `Leaf::g_min` after construction) and listed `undifferentiable` in the AD table: at g_min = 0 phylloptim's residual terms are exact zeros by a test on the value, so a gradient column would be an exact zero that reads as an answer. The model-version snapshot was re-accepted for the new field; no `scientific_version` bump. `check_passthrough("TF24")` should now return an empty gap list.
- **`default_parameters()` warns on every non-quiet call**, not once per session, so the warning is testable and the opt-out is explicit (`quiet = TRUE`). The testthat helper is `testing_parameters(model)`.
- `make_K93_hyperpar()` and `K93_hyperpar` are shims returning the identity; `default_parameters("K93")` attaches the identity explicitly rather than nothing, so K93 tests do not trigger the "no trade-offs attached" message.

PR B was **folded into plant#731** (maintainer's decision, 2026-11-10), so there is no deprecation release: the shims, `pulse_series_*`, `solar_model.R` (its two functions survive unexported inside the frozen FF16 trade-off) and `soil_widths_graded` are gone at once, and regnans and logpile move in lockstep. `build_scenario(config, ..., drivers = <table>)` applies a rainfall driver table (`time`, `rainfall`) or constant rain; the gateway reads the former sinusoid from `inst/scenarios/scenario_rainfall_drivers.rds` (`scenario_rainfall_drivers(config)`, written by `scripts/make-scenario-drivers.R`, knots `identical()` to the old inline series, 100 years only). The two `inst/scenarios/*.csv` still move to fieldtrial as sets; plant keeps a copy only as long as the gateway reads them. Found on the way: plant's gateway baseline was already stale on develop@155995cb (four scenarios moved after the phylloptim 0.34/0.35 pins, identically with and without #731); re-blessing it is a separate plant commit.

### Parameter sets

One YAML per set under `inst/sets/`, reviewable in a diff:

```yaml
name: mulga_alice_springs
model: TF24
plant_scientific_version: "TF24@v13"
traits: {lma: , rho: , K_s: , vcmax_25: , jmax_25: }
tradeoff_coefficients: {}          # overrides of inst/tradeoffs/TF24.yml only
pars: {hmat: , root_depth_shape_eta: }   # direct pars NOT derived by a trade-off; refused otherwise
environment: {soil: {depth: , n_layers: , widths: graded, K_sat: , a_psi: , n_psi: }, f_PAR: 0.5}
site: {name: "Alice Mulga OzFlux (AU-ASM)", lat: -22.283, lon: 133.249, elev: }
drivers: {met: met/AU-ASM_daily.csv}   # or a generator spec {kind: markov, fit_from: ...}
provenance: {sources: [Zotero keys], author: , date: , notes: }
```

`parameter_set(name)` returns a list of class `fieldtrial_set` with `$p` (plant `Parameters` from `base_parameters(model)` + `add_strategies(p, trait_matrix(traits), tradeoffs(model, coefficients))`), `$env` (`Environment(model)` with soil applied), `$events` (rainfall pulses when the driver is a record), `$meta`. `check_set()` refuses when `plant::model_id(model)` differs from `plant_scientific_version` unless overridden; this is how the C++-default pin stays visible per set. Trait and parameter values for the two first sets come from the TF24 C++ comments (*Acacia aneura*, Robinson's mulga), mulga-library's hydrology plan, phytofile, and literature; every value cites a Zotero key, never memory.

First sets: `mulga_alice_springs` (AU-ASM, Alice Mulga OzFlux; AGCD rainfall 1900–2023 as the long record, the FLUXNET Shuttle AU-ASM package as the observed met) and a tall eucalypt set whose met site is a tall wet-sclerophyll tower in the Shuttle (AU-Tum Tumbarumba, *E. delegatensis*, or AU-Wom Wombat, *E. obliqua*; species for the trait values to be chosen when the set is built, recorded in provenance). Next: `mulga_delta` (monitoring site, AGCD-driven, logger data from `mulga_plots_data` as validation), and a TF24t variant of the mulga set once phylloptim #187 delivers thermal values.

### Pass-through: every relevant parameter reaches `run()`

`run(p, env = NULL, control = control(), events = NULL, ...)` (`plant/R/run.R`) has four input channels, and a set must be expressible entirely through them. A `fieldtrial_set` therefore materialises to exactly these four objects, and `run_set(set, ...)` is nothing more than `run(set$p, env = set$env, control = set$ctrl, events = events, ...)`, with `events` the set's pulses added to `events_default(set$p)`.

| Channel | What it carries | How a set fills it | Verified today |
|---|---|---|---|
| `Parameters` (`p`) | per-species `strategy$pars` (all model parameters, including the leaf traits), birth-rate drivers, patch settings (`max_patch_lifetime`, disturbance), the attached trade-offs | `base_parameters(model)` + `add_strategies(trait_matrix, tradeoffs(...))` + direct `pars` + `$hyperpar` | Leaf traits are `TF24_Pars` fields carrying phylloptim's names and handed to the leaf in `construct_leaf()` (`inst/include/plant/models/tf24_model.h`), most of them positionally to the `Leaf` constructor and the rest by name: `vcmax_25, jmax_25, stem_P50, stem_c, root_P50, root_c, TF24_beta2, TF24_cost_scale, phi_J, curv_fact_elec_trans, curv_fact_colim, R_d_25, alpha_PAR, alpha_NIR, use_energy_balance, d`. No separate leaf object is passed; the strategy owns its leaf. |
| `Environment` (`env`) | soil fields (`soil_moist_sat, K_sat, a_psi, n_psi, a_infil, b_infil, water_mixing_rate, f_PAR`), layer widths, initial soil water, the eight climate drivers | `Environment(model)` + `set_tf24_soil()` + `apply_drivers()` | All exposed to R for TF24 (`inst/RcppR6_classes.yml` TF24_Environment block). FF16/K93 expose only `set_fixed_environment`. |
| `Control` (`ctrl`) | numerics, including the leaf's own numerical controls (`GSS_tol_abs, vulnerability_curve_ncontrol, ci_abs_tol, ci_niter`, `inst/include/plant/control.h:130-133`) and `function_integration_rule` | a set's `control:` block (optional; defaults otherwise) | Exposed. These are the plant-side mirror of `phylloptim::leaf_control()`. |
| `Events` | scheduled rainfall pulses, harvests, resource pulses, climate extremes | `pulse_series_*` → `rainfall_pulse()` | Exposed (`R/events.R`, `R/tf24_events.R`). |
| Strategy top-level fields (TF24t) | the 26 thermal fields (`topt_offset, k_i, k_i_Ea, k_i_Tiso, k_rec, k_rec_Ea, k_mat, k_mat_Ea, dTopt_max, dTimpair_max, K_A, alpha, beta, t_accl, softplus_s, k_mean_leaf_temp, c_*` …) | a set's `strategy:` block, assigned as `s[[name]] <- value` after `generate_strategy()` | Exposed as R fields of `TF24t_Model` (`inst/RcppR6_classes.yml`, "copied into the Leaf in prepare_strategy"), **but not in `pars`**: `generate_strategy()` writes only `strategy$pars`, so a trait matrix cannot reach them today. |

**Known gaps, both closed by plant PR A:**

- phylloptim's `leaf_traits()` has `g_min` (residual conductance, phylloptim #182) with no `TF24_Pars` field (plant hands the leaf a literal 0.0). Add `g_min` to `TF24_Pars` (default 0.0, bit-identical; non-zero `g_min` is untested anywhere in plant and must be checked when exposed). `JS22_gamma`, `CMax_a`, `CMax_b` belong to other stomatal models and are out of scope.
- TF24t's thermal parameters sit beside `pars`, not in it. Either `generate_strategy()` learns to assign top-level strategy fields named in `parameter_table("TF24t")`, or the thermal fields move into a `TF24t_Pars`. The first is the smaller change and keeps the trait matrix as the one way in; fieldtrial's `strategy:` block is the fallback until it lands. These values are needed soon: phylloptim #187 will replace the placeholders, and a TF24t set is where the fitted values land.

**As implemented in phase 4 (machinery).** These constrain later edits:

- **Every scientific value is `{value, source}`**, and a value without a source is refused. Run and control settings are plain values. YAML integers are coerced to the type plant's field already has.
- **A key that reaches none of plant's inputs is refused**: an unknown trait, a direct parameter the trade-offs derive (it would be overwritten), a strategy plumbing field, an unknown environment, `Parameters` or `Control` field. Direct `pars` and `strategy` fields are written to `strategy_default` before `add_strategies()`, so the one strategy is built on them.
- **TF24t's thermal fields already reach plant through a set's `strategy:` block**, written to `strategy_default`. plant PR A's change to `generate_strategy()` is for trait matrices (sweeps, gradients), not needed by sets.
- **Trade-offs are passed to `add_strategies()` explicitly** and kept on the set as `set$tradeoffs`. plant#731 settled the carrier: `p$hyperpar` (a `SEXP` field of `Parameters`, surviving `validate()` and `run()`), so once fieldtrial's plant pin moves past it the loader also sets `set$p$hyperpar <- set$tradeoffs`, and `add_strategies()`/`stand_gradient()` need no explicit argument.
- **`check_passthrough()` reads phylloptim's own `leaf_traits()` and `leaf_control()`.** `plant::Leaf`'s constructor lists only the 15 traits plant passes by position, so it cannot show what is missing. phylloptim is deliberately not a declared dependency: plant links it, so it is installed wherever plant was built. Declared in Suggests without a Remotes entry, pak resolved it through plant's pin for the install but then failed a second resolve (the pandoc check in `setup-r-dependencies`) looking for it on CRAN; a Remotes entry of fieldtrial's own would clash with plant's pin at every bump.
- **Two gaps found on plant develop@155995cb**: `g_min` (no `TF24_Pars` field) and the leaf's `integration_tol` (no `Control` field; plant forwards only `function_integration_rule`). plant#731 closes `g_min`. **`integration_tol` is a non-gap, not a plant fix**: in phylloptim 0.35.0 it sets only `Leaf::integration_tol_`, the tolerance of `transpiration_full_integration()`'s direct quadrature, which phylloptim marks "off the production path" and plant never calls, and the companion `integration_rule` is ignored by `initialize_integrator()` itself. A `Control` field for it would be settable and reach nothing (the #636 silence), so plant refuses to add one; `check_passthrough()` classifies it as out of scope beside `JS22_gamma`/`CMax_*`, with this reason, and fails on any new name (confirmed in phylloptim 0.35.0: `integration_tol_` is read only by `transpiration_full_integration()`).

**The first set, `mulga_alice_springs`** (decided with the maintainer 2026-11-10). Values were extracted from the lab's mulga-library (numbers may be used publicly with citations; the papers' text may not) and from austraits-means, and each quoted value was checked against its paper before use.

- **Sources:** site-measured *A. aptaneura* values at AU-ASM first (Vcmax/Jmax, Huber value; wood density from the Ti Tree basin), AusTraits *A. aneura* sensu lato means to fill (LMA, seed mass, plant height). Papers not in Zotero are cited by mulga-library key and DOI.
- **Stem and root P50 = 6.7 MPa is a flagged proxy**: the leaf water potential at stomatal closure, a lower bound on P50. No vulnerability curve exists for any mulga taxon in the library, while field midday leaf water potential reaches −6.5 to below −10 MPa; plant's defaults (2.9 and 3.4 MPa) would fail where mulga routinely operates. The stem value goes through the trade-off by overriding `B_Hv1` at plant's default K_s. Replace both when a measured curve is found (the Xylem Functional Traits database is the next place to look).
- **`hmat` = 2.5 m**, the size of the flowering trees Preece-1971a studied (2–3 m), a proxy: height at maturation has no direct measurement. AusTraits' mean plant height (4.7 m) was tried first and changed by the maintainer on 2026-11-10: the stand reached it only in the 105th year of a patch, so it barely reproduced (offspring production 3.4e-7); 2.5 m is reached at about 9 years, in line with 5 to over 10 years to first reproduction (Beadle-1948).
- **Soil to the hardpan at 1.0 m**, saturated water content 0.35 (measured porosity).
- **Left at plant's defaults for lack of mulga data:** K_s (only anatomical indices exist), the curves' shape parameters, leaf lifespan, and `K_sat`.
- **Two plant gaps found while building it:** `K_sat`'s units are not documented in plant (so a measured or database value cannot be converted), and the per-layer soil parameters `set_tf24_soil()` sets have no R getter (the loader's test checks them on the way in). Both are for plant.
- `parameter_set(drivers = FALSE)` builds a set without its climate data, which is how CI checks packaged sets.

**Mulga at `hmat` = 2.5 m** (plant develop@218501e1, WorldClim drivers): the tallest cohort matures at 10 years and offspring production is 42.8, against 3.4e-7 at 4.7 m. After maturity the stand nearly stops growing, plateauing at 2.7 m, while the canopy at the tower averages 6.5 m (trees 3–7 m). Mature at the right age but too short: an open calibration question, likely in how reproductive allocation ramps after maturity.

**`mulga_delta`** reuses `mulga_alice_springs`'s species values and proxies at the Delta monitoring plots (north-western NSW), with its own WorldClim climate. Its site is published only to 0.1° (−30.1, 145.3; the plots' centre, from the mulga project's QGIS layer), a rule a test enforces. Soil stays at plant's defaults: Alice Springs' hardpan and porosity do not carry over, and no Delta soil data are cited. The taxon at Delta is not recorded in the sources.

**fieldtrial on plant after plant#731** (pin develop@218501e1, same PR as the mulga set): the bit-identity tests compare against `plant::default_hyperpar()` (330 tests, none skipped, identical for TF24 and FF16); a set's trade-offs are attached to `set$p$hyperpar`, so mutants and gradients built from it use them; fieldtrial's closures carry `attr(f, "traits")` for plant's `parameter_table()`; `check_passthrough("TF24")` finds no gaps. The `integration_tol` reclassification had missed fieldtrial#6's squash and is restored here.

**fieldtrial on plant's tidied interface** (fieldtrial#13; pin develop@4520694a, 2026-11-13): plant#760 renamed the model classes `*_Strategy` -> `*_Model` ("strategy" now means one species' trait values only), so `check_passthrough()` and the tests build `<model>_Model()`, and a set's refused `strategy:` key names `<model>_Model`. plant#762 removed TF24's nine unused parameters, `nmass_l` among them, so `tradeoffs("TF24")` no longer returns `nmass_l` (it still builds `r_l` from leaf nitrogen, unchanged); plant refuses a trait matrix that names a parameter `TF24_Pars` lacks, so the two must move together. The committed baseline was re-blessed for that column alone: every other entry and column is `identical()` to the previous fixture. `Remotes:` is now pinned to the sha, not `develop`, so a plant rename cannot break a fresh install before fieldtrial migrates. The other renames in plant's NEWS since develop@218501e1 (`NodeSchedule` -> `Schedule`, `opt_psi_stem` -> `opt_psi_leaf`, TF24f's finite-difference gradient, the TF24 stand reports, the unexported scenario gateway) have no call sites here.

**fieldtrial on plant's `run()` interface** (fieldtrial#15; pin develop@83a973ff, 2026-11-14): plant#779 replaced `run_scm()` with `run()` and renamed `scm_base_parameters()` `base_parameters()`, and plant#781 renamed `Parameters$patch_type` `fitness_weighting`. `run_set()` now returns the `plant_run` `run()` returns, not the live `SCM`: its fitness values are fields of the result, and the solver is `$solver`. A set's `run:` block takes `fitness_weighting`, and `patch_type` is refused as an unknown key.

**`alpine_ash_tumbarumba`** (decided with the maintainer 2026-11-10): *E. delegatensis* at AU-Tum. Values were found by a literature search beyond the lab library (Zotero first, then Scite and Consensus), each quote checked against the paper's text before use.

- **Site values first**: Vcmax 81.5, Jmax 194.6 and crown-average LMA 0.206 kg m⁻² measured at AU-Tum (Medlyn-2007); AusTraits means fill wood density, seed mass and the Huber value (2 records).
- **Stem and root P50 = 5.31 MPa is a derived proxy** (changed 2026-11-10 from 4.98): the stem P50 of *E. regnans* seedlings (4.98 MPa, Pan 2026) scaled by the ratio of the two species' leaf P50s measured together in the same experimental forest (*E. delegatensis* 3.42, *E. regnans* 3.21 MPa; Britton-2022, optical method, 6-year-old trees, Tasmania). Stem organ from the congener, species difference from the leaves. `hmat` was re-derived after the change (23.51 m, from 23.55).
- **`hmat` is derived, not looked up**: 23.51 m, the tallest cohort's height at 20 years in a run of the set with no maturation, matching the ~20-year primary juvenile period Doherty-2017 gives. This was chosen because TF24 stands nearly stop growing after maturity (mulga plateaued just above `hmat`), so a 5–6 m `hmat` from early-flowering saplings would cap a 40 m forest at about 6 m. Re-derive it if the set's other values change.
- **Soil depth 2.0 m** (Pepper-2008); roots may reach water below 3 m. Soil hydraulic parameters stay at plant's defaults.
- Pepper-2008 and Britton-2022 were added to Zotero on 2026-11-10. Others found but not used for values: van Gorsel 2007, Buckley 2011, Davidson & Reid 1989.

**Audit instead of trust.** fieldtrial carries `check_passthrough(model)`: it compares `names(phylloptim::leaf_traits())` with `names(<model>_Model()$pars)` and `names(phylloptim::leaf_control())` with `names(Control())`, and lists every leaf-side name that plant cannot set. It runs as a test against the pinned plant and phylloptim, so a new phylloptim trait that plant does not yet forward shows up as a failing test in fieldtrial, with the fix going to plant. Every set file is checked key by key against what plant has (the strategy's parameters and fields, the trade-offs' derived parameters, the environment's fields, an allowlist of run settings, `Control`'s fields), so a key that reaches none of the four channels is refused at load, never silently dropped (the #636 rule, applied to sets). Once plant has `parameter_table(model)` the check can read it instead.

### Drivers

**What plant needs from a day.** Today TF24 solves the leaf once at the driver values and bills a 12 h day. The `experiment/618-daily-integral` branch (not for merge as is, but the design plant will follow: Gauss-Lobatto 5 with three solves is its recommended method) adds `Control$daily_integration` with modes `fixed-12h`, `one-point`, `diurnal`, `lobatto`, and rebuilds the day from a minimal representation: `TF24_Environment$latitude` (new field), `vpd_peak_hour` (field, default 14.5), and a new driver `atm_vpd_diurnal_amp`. `SWdown(t)` and `atm_vpd(t)` are **values at solar noon**; the SWdown course through the day is clear-sky geometry (`inst/include/plant/models/tf24_diurnal.h`, which also fixes the declination: plant's R `solar_angle()` uses sin δ as δ, 0.6° low at the solstices), and the VPD course is one cosine harmonic. Temperature is not resolved diurnally: `leaf_temp` is pinned at 25 °C, the leaf refuses VPD ≥ e_s(T_air), and TF24t is refused in the sub-daily modes because a daylight-mean leaf temperature is meaningless for damage; heat extremes go to events (#631). So the minimum a site record must provide is latitude, noon SWdown, noon VPD and the VPD amplitude per day, and any future diurnal temperature follows the same pattern (a noon or maximum value plus an amplitude driver). The 618 plan already asks for exactly this fit from half-hourly data ("per-day noon SWdown, noon VPD and the relative amplitude, smoothed"), which is fieldtrial's job.

Canonical daily met table (ALMA-style names; a FLUXNET or PLUMBER2 record maps onto it after aggregation):

| column | unit | convention |
|---|---|---|
| `date` | ISO date | daily |
| `SWdown_noon` | W m⁻² | smoothed value at solar noon → driver `SWdown` |
| `SWdown_mean` | W m⁻² | 24 h mean, diagnostics only |
| `VPD_noon` | kPa | smoothed value at solar noon → `atm_vpd`; computed from `Qair`/`RH`, `Tair`, `Psurf` |
| `VPD_amp` | – | relative amplitude of the cosine fit, in [0, 1) → `atm_vpd_diurnal_amp` |
| `Tair_noon` | °C | air temperature at solar noon → `leaf_temp`, when requested |
| `Tair_mean`, `Tair_max`, `Tair_min` | °C | daily; `Tair_max` for TF24t and heat events |
| `Precip` | mm d⁻¹ | daily total |
| `Wind` | m s⁻¹ | daytime mean |
| `Psurf` | kPa | → `atm_kpa` |
| `CO2air` | ppm | bundled global history when absent; → `ca` in Pa via `Psurf` |

Site metadata (`lat`, `lon`, `elev`, `vpd_peak_hour`) travel as attributes and are written to the environment's fields. `apply_drivers(env, met, t0, rainfall = c("pulse", "spline"))` sets `t = (date - t0) / 365.25`, converts units, writes `latitude`, and calls `extrinsic_drivers_set_variable` for continuous drivers. Rainfall defaults to **pulses**: `pulse_series_record()` → `plant::rainfall_pulse()`, with the continuous `rainfall` driver set to 0; a daily record is a sum of discrete depths and interpolating it smears each event over its neighbours. plant lands a soil substep on each knot and `rainfall_pulse()` warns on double counting. The spline path remains for climatologies and the scenario sinusoid. `met_climatology(met)` collapses a record to a mean year for equilibrium runs. `swdown_clear_sky(lat, doy)` from the moved solar code gives a location- and season-dependent light driver where no observed radiation exists (#701).

**As implemented in phase 2a** (plant develop@ae869f13). These constrain later edits:

- **Driver knots sit at the middle of each day**, and the first and last days' values are pinned to the start of the first day and the end of the last. A run starts at time 0 (the start of 1 January), and plant refuses to evaluate a driver outside its knots; mid-day knots alone left the first half-day uncovered.
- **Time is calendar-fraction years from 1 January of `start_year`** (`met_time()`), so the fractional part is the day of year as plant's 618 geometry reads it, and a leap year's days are 1/366. Spline rainfall converts each day's total at its own year's day count, so a year's total is conserved.
- **Rainfall defaults to pulses** at the middle of each wet day, with the continuous driver set to zero. `apply_drivers(until =)` drops pulses past the run: plant refuses an event after `max_patch_lifetime`.
- **`leaf_temp` is not set unless asked for** (`drivers = c(..., "leaf_temp")`), because it moves every temperature response at once. Before anything is set, `VPD_noon` is checked against `(0, e_s(T))` at the leaf temperature it will meet, with phylloptim's Tetens constants, and refused with the first offending date.
- **`latitude`, `vpd_peak_hour` and `atm_vpd_diurnal_amp` are written only where the environment has them.** plant develop does not yet (the 618 branch adds them), so today a table's `VPD_amp` is recorded as "not in this plant version" and the one-solve path runs on the noon values unchanged.
- **The subdaily fit groups by local solar day** (UTC offset, longitude, equation of time). A solar day can hold one step more or fewer than 24 clock hours, so "complete" allows ±1 step; the uneven sampling biases the VPD cosine fit by about 3e-4. Amplitudes outside `[0, 0.99]` are clamped and noon VPD below 0.01 kPa raised, both counted in attributes.
- **`swdown_noon_from_mean()` conserves energy exactly**: the noon value of a clear-sky-shaped day holding the observed daily total, so the day plant rebuilds integrates to what was measured.

**As implemented for WorldClim (phase 2b).** These constrain later edits:

- **`Tair_noon` joins the table, and `leaf_temp` maps to it, not to `Tair_mean`** (a change to phase 2a). Every other driver is a noon value, and the leaf refuses a VPD at or above `e_s(leaf_temp)`: pairing a noon VPD with the daily mean temperature refused ordinary arid summer days (at Alice Springs the noon VPD exceeds `e_s` at the daily mean). Tower records fit `Tair_noon` with the same cosine as VPD; monthly sources read it from the day's temperature cosine.
- **`met_from_monthly()` holds every monthly-source assumption**, so WorldClim, CRU TS and AGCD share them: linear interpolation between mid-month values (wrapping for normals); precipitation and shortwave rescaled to keep each month's total exactly; one temperature cosine between Tmin and Tmax peaking at `peak_hour` (default 14.5, the same hour as VPD); VPD through the day `e_s(T(h)) - e_a` with `e_a` constant, fitted and bounded exactly as tower VPD is; pressure from elevation by the standard atmosphere. Columns from an assumption are named in `attr(, "filled")`.
- **WorldClim downloads whole global grids**, cached under `tools::R_user_dir("fieldtrial", "cache")`. Measured download sizes: about 200 MB for the seven variables at 10 arc-minutes (the default), 700 MB at 5, 2.5 GB at 2.5; 30 arc-seconds fetches the site's tile. Its wind is a 24-hour mean used for the table's daytime mean (marked filled). It has no CO₂.
- **No WorldClim values are committed.** The WorldClim 2.1 page states no licence or redistribution terms, so the tests use synthetic normals and small in-memory rasters; the download path is checked by hand.
- **`apply_drivers()` warns when a climatology's rainfall is sent as pulses**, since a mean year's rain is a daily drizzle.

**Candidate sources at TERN** (checked 2026-11-09 by web search; not yet tried from here):

- **ANUClimate 2.0**: daily 1 km grids for mainland Australia, with rainfall back to 1900 and the other variables from at least 1970: mean, maximum and minimum temperature, rainfall, solar radiation, vapour pressure deficit, pan evaporation. On NCI (project gh70, THREDDS DOI 10.25914/608bfc062f4c7). The best Australian daily source for this table, since it has radiation and VPD that AGCD lacks.
- **OzFlux L6** on TERN's THREDDS server (`dap.ozflux.org.au`), per-site processed tower data, as an open alternative to the FLUXNET Shuttle. The server timed out from this machine on 2026-11-09.
- **Soil and Landscape Grid of Australia**: clay, sand, available water capacity and more at six depth slices on a 90 m grid, served by WCS and Cloud-Optimised GeoTIFF; a source for TF24's soil parameters through pedotransfer functions.
- **SMIPS**: daily 1 km volumetric soil moisture, for initial soil water and for checking modelled soil water.
- **AusPlots** (R package `ausplotsR`): vegetation structure and composition at surveillance plots, for checking parameter sets.

**Source adapters.** Every source is one function `met_from_<source>(sites, ...)` returning the canonical table (or a monthly climatology table for climatology-only sources), with attributes recording the source, version, resolution and which columns were gap-filled rather than observed. `met_sources()` lists them. First release:

| Adapter | Coverage | Gives directly | Gap-filled by fieldtrial | Access |
|---|---|---|---|---|
| `met_from_fluxnet()` | site, half-hourly, continuously updated tower record | all drivers, plus the noon values and `VPD_amp` fitted from the half-hourly course | none | FLUXNET Shuttle ONEFlux FULLSET CSV (`SW_IN_F, TA_F, VPD_F, P_F, WS_F, PA_F, CO2_F_MDS`); CC-BY, cite the site's provider. AU-ASM and the eucalypt towers are TERN `2026_r1` packages. |
| `met_from_plumber2()` | site, half-hourly, fixed release | as above | none | PLUMBER2 NetCDF (local copy); same aggregation code as FLUXNET |
| `met_from_agcd()` | Australia, 5 km, monthly 1900– (daily exists) | Precip, Tmax, Tmin, vapour pressure | `SWdown_noon` from `swdown_clear_sky` × a transmissivity, `VPD_noon` from Tmax + vapour pressure, `VPD_amp` from the Tmax–Tmin range, Wind constant | `extract_agcd()`, ported from the standalone script; source AGCD v2 on NCI `gadi:/g/data/zv2` |
| `met_from_worldclim()` | global, 30 s–10 min, 1970–2000 climatology | Tavg, Tmin, Tmax, Prec, Srad, Wind, Vapr | noon values from daily Srad and the Tmax–Tmin range (climatology only; no interannual series) | `geodata::worldclim_global()` / `worldclim_tile()` |
| `met_from_cru()` | global, 0.5°, monthly 1901– | pre, tmp, tmn, tmx, vap, cld, wet | SWdown from cloud cover + clear-sky, VPD and amplitude as for AGCD, Wind constant | CRU TS NetCDF (CEDA download, manual) |

Every gap-fill is a named, documented function, so the same estimate is used by every adapter, and its presence is recorded per column in the table's attributes. The noon/amplitude fit from half-hourly data is validated once against the 618 analysis' synthetic sites and reused by FLUXNET and PLUMBER2 alike; `swdown_clear_sky()` uses the corrected declination from `tf24_diurnal.h` so plant's reconstructed day and fieldtrial's clear-sky estimate agree.

Later adapters, in this order: SILO (Australia, daily, has radiation and VPD), TerraClimate (global 4 km monthly 1958–, has srad and vpd directly, so the fewest gap-fills of any global grid), ERA5-Land (hourly, via `ecmwfr`/`mcera5`). Monthly sources feed `met_climatology()` directly or a `pulse_series_fit()`/`pulse_series_markov()` daily disaggregation; the disaggregation choice is recorded in the set's `drivers` block. Raw grids never enter the repo; each set ships the small derived daily or monthly CSV for its site.

### Registration in the family

- **plant-family workspace**: clone `traitecoevo/fieldtrial` beside the other family repos. Done 2026-11-09.
- **plant-meta**: `dependencies.yml` gains a `fieldtrial` entry under `packages` (kind r-package; role: parameter sets, trait trade-offs, driver tables for plant runs; `r_imports: [plant, terra, yaml]`; `r_depends` pin via `.plant-interface-version`; `data_consumes` from AGCD, PLUMBER2, WorldClim, CRU, mulga-library, phytofile; `produces` trade-off functions, parameter sets, driver tables) plus two `cross_boundary_artifacts` rows (trait trade-offs: fieldtrial → plant runs, regnans, logpile; parameter sets + driver tables: fieldtrial → plant, floracle). `AGENTS.md`: add to the model-core table, both graphs, the source-of-truth table ("recommended trade-offs and species/site sets → fieldtrial; plant's `default_parameters()` is a frozen testing set"), and a gotcha for the two-copies rule. `governance/apply-labels.sh`: add `traitecoevo/fieldtrial` to the repo list; `project-board.md`: name it; `triage.md`: default branch `fieldtrial → main`. Install the `add-to-project` workflow in fieldtrial per `auto-add-to-board.md`. Fieldtrial's README carries the family boilerplate from floracle's README.

## Phased plan

0. ✅ **fieldtrial first commit** (fieldtrial#2, plant-meta#9, 2026-11-09): package skeleton, `PLAN.md` (this document, trimmed), `.plant-interface-version`, README with family boilerplate, board auto-add workflow, CI that installs plant@develop. Clone into plant-family. Open the tracking epic in fieldtrial; link plant #697, #698, #701. **plant-meta PR**: register fieldtrial as above.
1. ✅ **fieldtrial PR: trade-offs** (fieldtrial#3) — port `make_FF16_hyperpar`/`make_TF24_hyperpar` as `tradeoffs()` with the simplifications above; coefficient YAMLs; bit-identity tests against plant's current functions over a trait grid; the stem_P50 invariant test.
2. **fieldtrial PRs: generators and adapters**, split in two.
   - ✅ **2a, driver core** (fieldtrial#4): canonical met table (`met_schema()`, `validate_met()`), corrected solar geometry matching plant's 618 branch (`solar_declination()`, `solar_day()`, `swdown_clear_sky()`, `swdown_noon_from_mean()`), `met_time()`, `met_daily_from_subdaily()` (the half-hourly → noon-value fit every tower adapter reuses), `apply_drivers()`, `met_climatology()`, `met_repeat()`; `pulse_series_*` and `soil_widths_graded()` copied from plant with their tests.
   - **2b, source adapters**, one PR each:
     - ✅ **WorldClim** (fieldtrial#5): `met_from_monthly()`, the shared monthly-to-daily converter every monthly source uses, and `met_from_worldclim()` / `worldclim_monthly()` on top of it.
     - **AGCD** (`extract_agcd` + `met_from_agcd`): the local archive holds monthly precipitation only; temperature and vapour pressure must be fetched from NCI first.
     - **Towers** (`met_from_fluxnet`, `met_from_plumber2`, or `met_from_ozflux` on TERN's OzFlux server, which needs no login): need the site files.
     - **CRU TS** (`met_from_cru`): needs a CEDA download.
     - `met_sources()` and a bundled CO₂ history once there are several adapters.
3. ✅ **plant PR A** (plant#731, merged as develop@218501e1): `Parameters$hyperpar`, `default_parameters()` with warning, `testing_parameters()` helper, shims, `parameter_table()`, `g_min`, trait-matrix access to top-level strategy fields, housekeeping. `scientific_version` unchanged (same numbers); goldens unchanged; 6585 tests pass.
4. **fieldtrial PRs: sets**, split in two.
   - ✅ **Machinery** (fieldtrial#6): set file format (schema 1, `inst/sets/README.md`), `parameter_set()`, `check_set()`, `run_set()`, `list_sets()`, `check_passthrough()`; tested on a synthetic set.
   - ✅ **`mulga_alice_springs`** (fieldtrial#8). ✅ **`mulga_delta`** (fieldtrial#9). 🔄 **`alpine_ash_tumbarumba`**, *E. delegatensis* at AU-Tum (in review). Then the scenario CSVs re-expressed as sets; a vignette running each set end to end.
5. 🔄 **regnans** (regnans#99, pinned at develop@218501e1): `plant_default_assembly_pars()` builds on `default_parameters(model, quiet = TRUE)`; `.plant-interface-version` bumped to the plant#731 head, to be repointed at the squash commit. **logpile** (logpile#7, pinned at develop@218501e1): `default_hyperpar(model)` with coefficient overrides from `global`, allowed names from `attr(f, "coefficients")`, `p$hyperpar` set on the built Parameters; its own suite has 12 pre-existing failures from `FF16@v1` pins, identical against plant develop. **overstorey**: `guides/extrinsic-drivers.qmd` fixes the stale PPFD row and gains a "from a met file" section; default-parameter claims read `parameter_table()` so they cannot rot.
6. ✅ **plant PR B**: folded into plant#731 (see § plant changes); nothing left to remove.

Out of scope, recorded so nobody absorbs it: forecasting draws and driver uncertainty (floracle, #521, mulgafutures DR1); the height exponent of stem conductance (#615, phylloptim #49: a plant/phylloptim functional-form question, fieldtrial only documents `B_Hv1`); thermal-pathway calibration (phylloptim #187; its fitted values may later enter TF24t sets); microclimf downscaling; SILO, ERA5-Land, SoilGrids readers (next release); Dahra/Verbruggen set (after the global path exists).

## Verification

- fieldtrial: `tradeoffs("TF24")` and `tradeoffs("FF16")` bit-identical to plant's frozen functions (`plant::default_hyperpar()` once the pin passes plant#731) on a committed trait grid; `TF24_Model()$pars` stem curve reproduced by `tradeoffs("TF24")` at defaults; `parameter_set("mulga_alice_springs")` runs `run()` to completion with `check_set()` passing against the pinned plant; `apply_drivers()` on the PLUMBER2 excerpt reproduces the file's daily values through `extrinsic_drivers_evaluate_range`, and total pulsed rainfall equals the record's sum; `extract_agcd()` reproduces the existing script's monthly output for a set of 17 mulga sites, committed as a fixture.
- fieldtrial pass-through: `check_passthrough("TF24")` returns an empty gap list against the pinned plant after plant PR A (today it would list `g_min`); a set that names a key reaching no channel is refused by `parameter_set()`; `run_set()` on each shipped set reproduces a run built by hand from its four objects.
- fieldtrial noon fit: on a FLUXNET Shuttle AU-ASM year, `SWdown_noon` × the clear-sky shape integrates to within a stated tolerance of the observed daily `SW_IN_F` sum on clear days, and `VPD_noon`/`VPD_amp` reproduce the observed daily VPD integral; the 618 synthetic sites round-trip through `apply_drivers()`.
- fieldtrial adapters: `met_from_worldclim()` and `met_from_cru()` at the AU-ASM coordinates give mean annual rainfall within the published site value's range, and the four adapters' outputs pass one schema check (`validate_met()`).
- plant PR A: full `test_check` without fieldtrial installed is identical to develop (default baselines and goldens unchanged, through `testing_parameters()`); `default_parameters("TF24")` warns once and `scm_base_parameters("TF24")` attaches no trade-offs; regnans and logpile test suites pass against the PR branch through the shims; `parameter_table("TF24")` lists the 13 derived parameters.
- Each PR gets an independent review from a second model on open; findings are checked against the code before they are fixed or rejected.
