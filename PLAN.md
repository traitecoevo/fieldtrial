# Scoping `fieldtrial`: parameter sets + environmental drivers for `plant`

Status: scoped 2026-11-09; phase 0 (this scaffold) in progress. Decisions taken by the maintainers are marked **Decided**. This file is the single source of truth for the work: keep it current, mark phases done, and retire inventory that no longer holds.

## Context

plant runs "out of the box" on defaults that record a development history rather than any species or site (#697). The trait→parameter trade-off functions (`*_hyperpar`) and the few driver generators plant has are mixed into the model package, the light driver is a constant (#701), and the parameter surface is opaque to users (#698). Nothing in the family holds a species parameter set or reads a gridded climate product; the only extraction code is a maintainer's standalone AGCD script plus two copies in projects outside the family. Verbruggen's `capabilities.md` records the gap bluntly: "no reader for daily/half-hourly met files anywhere".

`fieldtrial` will own: (1) named parameter sets for species and sites, (2) the trait trade-off functions and their coefficient sets, moved out of plant and simplified, (3) workflows that turn gridded and flux-tower climate into plant driver series, Australia first.

## Decisions

- **Decided: the recommended trade-off functions move to fieldtrial.** plant keeps the contract `f(m, s, filter = TRUE)` (+ optional `attr(f, "input_traits")`) and no longer applies any trade-off silently.
- **Decided: plant keeps one frozen *testing* parameter set, explicitly loaded.** It is the current defaults plus the current trade-off functions, so every golden and test in plant stays self-contained without fieldtrial. It is reached only through an explicit call (`default_parameters(model)`), which warns that this is a testing set and not a recommended parameterisation of any species or site. The bare `scm_base_parameters(model)` attaches no trade-offs: traits are written straight to `pars`. Consequence accepted: two copies of the forms exist, plant's frozen (changing it means re-blessing goldens) and fieldtrial's live (science evolves there). A bit-identity test in fieldtrial records when they diverge.
- **Decided: a `Parameters` object carries its own trade-offs.** `param_hyperpar(p)` reads them from `p`; identity when none are attached. This is what lets regnans, logpile and fieldtrial sets all work through the same plant API without plant naming fieldtrial.
- **Decided: first sets are mulga at Alice Springs (TF24) and a tall eucalypt (TF24); `mulga_delta` follows shortly** (Delta is one of the four mulga monitoring sites in `mulga_plots_data`, with Barcheka, Bendemere and Corrie Downs; no flux tower, so its met is AGCD plus gap-fill).
- **Decided: pass-through scope is every parameter of the TF24 (TF24_floor cost curve) model, including TF24t's thermal fields, and no other stomatal model's parameters for now.** Sets carry a `model:` key and `check_passthrough(model)` is per model, so swapping models later is a new row, not a redesign.
- **Decided: climate sources are pluggable adapters, with several in the first release:** FLUXNET Shuttle site packages (ONEFlux FULLSET half-hourly, CC-BY, 700+ sites, TERN's OzFlux towers released as `2026_r1`) as the primary site source, with PLUMBER2 NetCDF as a second reader of the same quantities; AGCD (Australia, monthly, from the existing extraction script); global grids WorldClim 2.1 (monthly climatology) and CRU TS (monthly series, 1901 onward). SILO, TerraClimate and ERA5-Land are later adapters.
- **Decided: the canonical met table carries noon values and diurnal amplitudes, not daytime means.** This follows plant: `SWdown`'s default 900 W m⁻² is documented as clear-sky midday, and the `experiment/618-daily-integral` branch defines `SWdown(t)` and `atm_vpd(t)` as values at solar noon and rebuilds the day from latitude and a VPD amplitude driver. Daily means and extremes are kept as extra columns for diagnostics and for TF24t.
- **Decided: public repo.** Private field data (mulga_plots_data) is cited, never committed; only derived publishable series ship.
- **Decided: fieldtrial joins the plant-family workspace and plant-meta** (clone, dependency map, AGENTS.md tables, label sync list, board auto-add).
- Dependency direction is one way: `fieldtrial` Imports `plant` (pinned by sha via `Remotes: traitecoevo/plant@develop` and a `.plant-interface-version` file, the regnans pattern). plant does not need fieldtrial for its tests; it may list it in Suggests for one optional integration test.

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
  R/tradeoffs-tf24.R              K_s -> stem curve; lma/vcmax/jmax -> nmass_l, r_l
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

Cross-repo invariant test, in fieldtrial: `tradeoffs("TF24")` at plant's default traits reproduces `TF24_Strategy()$pars[c("stem_P50", "stem_c", "stem_b", "psi_crit")]`. The `B_Hv1` entry in `TF24.yml` documents that the K_s→P50 slope acts on tip conductivity since #615 and names #49 as the open question on the height exponent.

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

PR B (next minor release): remove the shims, `pulse_series_*`, `solar_model.R`, `soil_widths_graded`, the scenario sinusoid. `build_scenario()` takes a driver table argument; the scenario gateway (`scenario_model_fingerprint`, `make bless-scenarios`, `test-scenario-gateway`) stays in plant as QA, reading a committed fixture series. The two `inst/scenarios/*.csv` move to fieldtrial as sets; plant keeps a copy only as long as the gateway reads them.

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

`parameter_set(name)` returns a list of class `fieldtrial_set` with `$p` (plant `Parameters` from `scm_base_parameters(model)` + `add_strategies(p, trait_matrix(traits), tradeoffs(model, coefficients))`), `$env` (`Environment(model)` with soil applied), `$events` (rainfall pulses when the driver is a record), `$meta`. `check_set()` refuses when `plant::model_id(model)` differs from `plant_scientific_version` unless overridden; this is how the C++-default pin stays visible per set. Trait and parameter values for the two first sets come from the TF24 C++ comments (*Acacia aneura*, Robinson's mulga), mulga-library's hydrology plan, phytofile, and literature; every value cites a Zotero key, never memory.

First sets: `mulga_alice_springs` (AU-ASM, Alice Mulga OzFlux; AGCD rainfall 1900–2023 as the long record, the FLUXNET Shuttle AU-ASM package as the observed met) and a tall eucalypt set whose met site is a tall wet-sclerophyll tower in the Shuttle (AU-Tum Tumbarumba, *E. delegatensis*, or AU-Wom Wombat, *E. obliqua*; species for the trait values to be chosen when the set is built, recorded in provenance). Next: `mulga_delta` (monitoring site, AGCD-driven, logger data from `mulga_plots_data` as validation), and a TF24t variant of the mulga set once phylloptim #187 delivers thermal values.

### Pass-through: every relevant parameter reaches `run_scm`

`run_scm(p, env = NULL, ctrl = control(), events = NULL, ...)` (`plant/R/scm_support.R:105`) has four input channels, and a set must be expressible entirely through them. A `fieldtrial_set` therefore materialises to exactly these four objects, and `run_set(set, ...)` is nothing more than `run_scm(set$p, set$env, set$ctrl, events = set$events)`.

| Channel | What it carries | How a set fills it | Verified today |
|---|---|---|---|
| `Parameters` (`p`) | per-species `strategy$pars` (all model parameters, including the leaf traits), birth-rate drivers, patch settings (`max_patch_lifetime`, disturbance), the attached trade-offs | `scm_base_parameters(model)` + `add_strategies(trait_matrix, tradeoffs(...))` + direct `pars` + `$hyperpar` | Leaf traits are `TF24_Pars` fields carrying phylloptim's names and handed to the `Leaf` constructor positionally (`inst/include/plant/models/tf24_strategy.h:166-180`): `vcmax_25, jmax_25, stem_P50, stem_c, root_P50, root_c, TF24_beta2, TF24_cost_scale, phi_J, curv_fact_elec_trans, curv_fact_colim, R_d_25, alpha_PAR, alpha_NIR, use_energy_balance, d`. No separate leaf object is passed; the strategy owns its leaf. |
| `Environment` (`env`) | soil fields (`soil_moist_sat, K_sat, a_psi, n_psi, a_infil, b_infil, water_mixing_rate, f_PAR`), layer widths, initial soil water, the eight climate drivers | `Environment(model)` + `set_tf24_soil()` + `apply_drivers()` | All exposed to R for TF24 (`inst/RcppR6_classes.yml` TF24_Environment block). FF16/K93 expose only `set_fixed_environment`. |
| `Control` (`ctrl`) | numerics, including the leaf's own numerical controls (`GSS_tol_abs, vulnerability_curve_ncontrol, ci_abs_tol, ci_niter`, `inst/include/plant/control.h:130-133`) and `function_integration_rule` | a set's `control:` block (optional; defaults otherwise) | Exposed. These are the plant-side mirror of `phylloptim::leaf_control()`. |
| `Events` | scheduled rainfall pulses, harvests, resource pulses, climate extremes | `pulse_series_*` → `rainfall_pulse()` | Exposed (`R/events.R`, `R/tf24_events.R`). |
| Strategy top-level fields (TF24t) | the 26 thermal fields (`topt_offset, k_i, k_i_Ea, k_i_Tiso, k_rec, k_rec_Ea, k_mat, k_mat_Ea, dTopt_max, dTimpair_max, K_A, alpha, beta, t_accl, softplus_s, k_mean_leaf_temp, c_*` …) | a set's `strategy:` block, assigned as `s[[name]] <- value` after `generate_strategy()` | Exposed as R fields of `TF24t_Strategy` (`inst/RcppR6_classes.yml`, "copied into the Leaf in prepare_strategy"), **but not in `pars`**: `generate_strategy()` writes only `strategy$pars`, so a trait matrix cannot reach them today. |

**Known gaps, both closed by plant PR A:**

- phylloptim's `leaf_traits()` has `g_min` (residual conductance, phylloptim #182) with no `TF24_Pars` field (plant hands the leaf a literal 0.0). Add `g_min` to `TF24_Pars` (default 0.0, bit-identical; non-zero `g_min` is untested anywhere in plant and must be checked when exposed). `JS22_gamma`, `CMax_a`, `CMax_b` belong to other stomatal models and are out of scope.
- TF24t's thermal parameters sit beside `pars`, not in it. Either `generate_strategy()` learns to assign top-level strategy fields named in `parameter_table("TF24t")`, or the thermal fields move into a `TF24t_Pars`. The first is the smaller change and keeps the trait matrix as the one way in; fieldtrial's `strategy:` block is the fallback until it lands. These values are needed soon: phylloptim #187 will replace the placeholders, and a TF24t set is where the fitted values land.

**Audit instead of trust.** fieldtrial carries `check_passthrough(model)`: it compares `names(phylloptim::leaf_traits())` with `names(<model>_Strategy()$pars)` and `names(phylloptim::leaf_control())` with `names(Control())`, and lists every leaf-side name that plant cannot set. It runs as a test against the pinned plant and phylloptim, so a new phylloptim trait that plant does not yet forward shows up as a failing test in fieldtrial, with the fix going to plant. Every set file is validated against `parameter_table(model)` so a key that reaches none of the four channels is refused at load, never silently dropped (the #636 rule, applied to sets).

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
| `Tair_mean`, `Tair_max`, `Tair_min` | °C | daily; `Tair_mean` → `leaf_temp` when the pin is lifted; `Tair_max` for TF24t and heat events |
| `Precip` | mm d⁻¹ | daily total |
| `Wind` | m s⁻¹ | daytime mean |
| `Psurf` | kPa | → `atm_kpa` |
| `CO2air` | ppm | bundled global history when absent; → `ca` in Pa via `Psurf` |

Site metadata (`lat`, `lon`, `elev`, `vpd_peak_hour`) travel as attributes and are written to the environment's fields. `apply_drivers(env, met, t0, rainfall = c("pulse", "spline"))` sets `t = (date - t0) / 365.25`, converts units, writes `latitude`, and calls `extrinsic_drivers_set_variable` for continuous drivers. Rainfall defaults to **pulses**: `pulse_series_record()` → `plant::rainfall_pulse()`, with the continuous `rainfall` driver set to 0; a daily record is a sum of discrete depths and interpolating it smears each event over its neighbours. plant lands a soil substep on each knot and `rainfall_pulse()` warns on double counting. The spline path remains for climatologies and the scenario sinusoid. `met_climatology(met)` collapses a record to a mean year for equilibrium runs. `swdown_clear_sky(lat, doy)` from the moved solar code gives a location- and season-dependent light driver where no observed radiation exists (#701).

**Source adapters.** Every source is one function `met_from_<source>(sites, ...)` returning the canonical table (or a monthly climatology table for climatology-only sources), with attributes recording the source, version, resolution and which columns were gap-filled rather than observed. `met_sources()` lists them. First release:

| Adapter | Coverage | Gives directly | Gap-filled by fieldtrial | Access |
|---|---|---|---|---|
| `met_from_fluxnet()` | site, half-hourly, continuously updated tower record | all drivers, plus the noon values and `VPD_amp` fitted from the half-hourly course | none | FLUXNET Shuttle ONEFlux FULLSET CSV (`SW_IN_F, TA_F, VPD_F, P_F, WS_F, PA_F, CO2_F_MDS`); CC-BY, cite the site's provider. AU-ASM and the eucalypt towers are TERN `2026_r1` packages. |
| `met_from_plumber2()` | site, half-hourly, fixed release | as above | none | PLUMBER2 NetCDF (local copy); same aggregation code as FLUXNET |
| `met_from_agcd()` | Australia, 5 km, monthly 1900– (daily exists) | Precip, Tmax, Tmin, vapour pressure | `SWdown_noon` from `swdown_clear_sky` × a transmissivity, `VPD_noon` from Tmax + vapour pressure, `VPD_amp` from the Tmax–Tmin range, Wind constant | the skill's `extract_agcd()`; archive on OneDrive, NCI `gadi:/g/data/zv2` |
| `met_from_worldclim()` | global, 30 s–10 min, 1970–2000 climatology | Tavg, Tmin, Tmax, Prec, Srad, Wind, Vapr | noon values from daily Srad and the Tmax–Tmin range (climatology only; no interannual series) | `geodata::worldclim_global()` / `worldclim_tile()` |
| `met_from_cru()` | global, 0.5°, monthly 1901– | pre, tmp, tmn, tmx, vap, cld, wet | SWdown from cloud cover + clear-sky, VPD and amplitude as for AGCD, Wind constant | CRU TS NetCDF (CEDA download, manual) |

Every gap-fill is a named, documented function, so the same estimate is used by every adapter, and its presence is recorded per column in the table's attributes. The noon/amplitude fit from half-hourly data is validated once against the 618 analysis' synthetic sites and reused by FLUXNET and PLUMBER2 alike; `swdown_clear_sky()` uses the corrected declination from `tf24_diurnal.h` so plant's reconstructed day and fieldtrial's clear-sky estimate agree.

Later adapters, in this order: SILO (Australia, daily, has radiation and VPD), TerraClimate (global 4 km monthly 1958–, has srad and vpd directly, so the fewest gap-fills of any global grid), ERA5-Land (hourly, via `ecmwfr`/`mcera5`). Monthly sources feed `met_climatology()` directly or a `pulse_series_fit()`/`pulse_series_markov()` daily disaggregation; the disaggregation choice is recorded in the set's `drivers` block. Raw grids never enter the repo; each set ships the small derived daily or monthly CSV for its site.

### Registration in the family

- **plant-family workspace**: clone `traitecoevo/fieldtrial` beside the other family repos. Done 2026-11-09.
- **plant-meta**: `dependencies.yml` gains a `fieldtrial` entry under `packages` (kind r-package; role: parameter sets, trait trade-offs, driver tables for plant runs; `r_imports: [plant, terra, yaml]`; `r_depends` pin via `.plant-interface-version`; `data_consumes` from AGCD, PLUMBER2, WorldClim, CRU, mulga-library, phytofile; `produces` trade-off functions, parameter sets, driver tables) plus two `cross_boundary_artifacts` rows (trait trade-offs: fieldtrial → plant runs, regnans, logpile; parameter sets + driver tables: fieldtrial → plant, floracle). `AGENTS.md`: add to the model-core table, both graphs, the source-of-truth table ("recommended trade-offs and species/site sets → fieldtrial; plant's `default_parameters()` is a frozen testing set"), and a gotcha for the two-copies rule. `governance/apply-labels.sh`: add `traitecoevo/fieldtrial` to the repo list; `project-board.md`: name it; `triage.md`: default branch `fieldtrial → main`. Install the `add-to-project` workflow in fieldtrial per `auto-add-to-board.md`. Fieldtrial's README carries the family boilerplate from floracle's README.

## Phased plan

0. **fieldtrial first commit**: package skeleton, `PLAN.md` (this document, trimmed), `.plant-interface-version`, README with family boilerplate, board auto-add workflow, CI that installs plant@develop. Clone into plant-family. Open the tracking epic in fieldtrial; link plant #697, #698, #701. **plant-meta PR**: register fieldtrial as above.
1. **fieldtrial PR: trade-offs** — port `make_FF16_hyperpar`/`make_TF24_hyperpar` as `tradeoffs()` with the simplifications above; coefficient YAMLs; bit-identity tests against plant's current functions over a trait grid; the stem_P50 invariant test.
2. **fieldtrial PR: generators and adapters** — move `pulse_series.R`, `solar_model.R`, `soil_widths_graded`; add `swdown_clear_sky`, `apply_drivers`, canonical met schema, `met_from_fluxnet`, `met_from_plumber2`, `extract_agcd` (from the skill) + `met_from_agcd`, `met_from_worldclim`, `met_from_cru`, `met_climatology`. Tests on committed one-year excerpts.
3. **plant PR A** (as above: `Parameters$hyperpar`, `default_parameters()` with warning, `testing_parameters()` helper, shims, `parameter_table()`, housekeeping). `scientific_version` unchanged (same numbers); goldens unchanged.
4. **fieldtrial PR: sets** — `parameter_set()`, `check_set()`, `check_passthrough()`, `run_set()`, `mulga_alice_springs`, tall eucalypt; scenario CSVs re-expressed as sets; a vignette running each set end to end through `run_scm` via all four channels.
5. **regnans**: `plant_default_assembly_pars()` loads `default_parameters("FF16", quiet = TRUE)` or a fieldtrial set; bump `.plant-interface-version`. **logpile**: hash `param_hyperpar(p)` instead of `make_hyperpar(model)`. **overstorey**: `guides/extrinsic-drivers.qmd` fixes the stale PPFD row and gains a "from a met file" section; default-parameter claims read `parameter_table()` so they cannot rot.
6. **plant PR B** (next minor release): removals listed above.

Out of scope, recorded so nobody absorbs it: forecasting draws and driver uncertainty (floracle, #521, mulgafutures DR1); the height exponent of stem conductance (#615, phylloptim #49: a plant/phylloptim functional-form question, fieldtrial only documents `B_Hv1`); thermal-pathway calibration (phylloptim #187; its fitted values may later enter TF24t sets); microclimf downscaling; SILO, ERA5-Land, SoilGrids readers (next release); Dahra/Verbruggen set (after the global path exists).

## Verification

- fieldtrial: `tradeoffs("TF24")` and `tradeoffs("FF16")` bit-identical to plant's functions on a committed trait grid before plant PR B; `TF24_Strategy()$pars` stem curve reproduced by `tradeoffs("TF24")` at defaults; `parameter_set("mulga_alice_springs")` runs `run_scm` to completion with `check_set()` passing against the pinned plant; `apply_drivers()` on the PLUMBER2 excerpt reproduces the file's daily values through `extrinsic_drivers_evaluate_range`, and total pulsed rainfall equals the record's sum; `extract_agcd()` reproduces `~/GitHub/projects/Ford-ring_model/data/derived/agcd_precip_monthly.csv` for its 17 sites.
- fieldtrial pass-through: `check_passthrough("TF24")` returns an empty gap list against the pinned plant after plant PR A (today it would list `g_min`); a set that names a key reaching no channel is refused by `parameter_set()`; `run_set()` on each shipped set reproduces a run built by hand from its four objects.
- fieldtrial noon fit: on a FLUXNET Shuttle AU-ASM year, `SWdown_noon` × the clear-sky shape integrates to within a stated tolerance of the observed daily `SW_IN_F` sum on clear days, and `VPD_noon`/`VPD_amp` reproduce the observed daily VPD integral; the 618 synthetic sites round-trip through `apply_drivers()`.
- fieldtrial adapters: `met_from_worldclim()` and `met_from_cru()` at the AU-ASM coordinates give mean annual rainfall within the published site value's range, and the four adapters' outputs pass one schema check (`validate_met()`).
- plant PR A: full `test_check` without fieldtrial installed is identical to develop (default baselines and goldens unchanged, through `testing_parameters()`); `default_parameters("TF24")` warns once and `scm_base_parameters("TF24")` attaches no trade-offs; regnans and logpile test suites pass against the PR branch through the shims; `parameter_table("TF24")` lists the 13 derived parameters.
- Each PR gets an independent review from a second model on open; findings are checked against the code before they are fixed or rejected.
