# `fieldtrial` — developer guide for agents

`fieldtrial` **sets up [`plant`](https://github.com/traitecoevo/plant) runs by bundling a site's environment with a species' trait trade-offs and parameter sets.** It is a downstream application of `plant`: it Imports `plant` (pinned in [`.plant-interface-version`](.plant-interface-version)), and `plant` never imports it.

> **Status: scaffolding.** [`PLAN.md`](PLAN.md) is the single source of truth for scope, decisions and sequencing. Keep it current as pieces land, and retire what is done rather than letting it go stale.

## What lives here

- **Trait trade-offs** (`R/tradeoffs*.R`, `inst/tradeoffs/*.yml`): the functions that derive model parameters from traits, satisfying plant's contract `f(m, s, filter = TRUE)`. The recommended versions live here; `plant` keeps only a frozen copy as an explicitly loaded testing set (`plant::default_parameters()`).
- **Parameter sets** (`inst/sets/*.yml`, `R/parameter_set.R`): one YAML per named species × site, with provenance. `parameter_set(name)` materialises the four objects `run()` takes: `Parameters`, `Environment`, `Control`, `Events`.
- **Environmental drivers** (`R/met*.R`, `R/apply_drivers.R`): a canonical daily met table (noon values plus diurnal amplitudes, not daytime means) and one adapter per source. Raw grids never enter the repo; sets ship small derived site series under `inst/extdata/met/`.

## Checking against plant

The tests compare against plant's own trade-off functions, so they need the plant recorded in `.plant-interface-version`, not an older site-library copy (whose C++ defaults may predate the stem-curve change, plant#611). Build odelia, phylloptim and plant at their pinned refs into a scratch library and run with `R_LIBS` pointing at it. `data-raw/make-tradeoff-baseline.R` regenerates the committed baseline from that plant; regenerate it only when plant's frozen copy is meant to have moved, and say so in the PR.

## Rules that bite

- **Two copies of the trade-off forms exist by decision.** plant's is frozen (changing it re-blesses plant's goldens); this one is live. A bit-identity test here records when they diverge. Do not "fix" one to match the other without reading `PLAN.md` first.
- **Cite, never recall.** Every trait, coefficient and soil value in a set names a Zotero key or a dataset. A number without a source is refused in review.
- **Every value a set names must reach `run()`.** `check_passthrough(model)` lists leaf-side parameters plant cannot set; gaps are fixed in plant, not papered over here.
- **Driver semantics follow plant.** `SWdown` and `atm_vpd` are values at solar noon; rainfall is delivered as pulses by default; drivers cover whole days from time 0. Every adapter returns the table `validate_met()` accepts, and tower records go through `met_daily_from_subdaily()` rather than their own aggregation. See `PLAN.md` § Drivers before changing an adapter.

## Plant family

`fieldtrial` is part of the **plant family** in the [`traitecoevo`](https://github.com/traitecoevo) org — a hub-and-spoke set of packages built around the [`plant`](https://github.com/traitecoevo/plant) size- and trait-structured forest model.

- **Docs hub** — family user guides & theory: <https://traitecoevo.github.io/overstorey/>
- **Cross-package orientation** — how the family fits together (who depends on whom, source-of-truth rules, cross-repo gotchas) lives in [`plant-meta`](https://github.com/traitecoevo/plant-meta); start with its [`AGENTS.md`](https://github.com/traitecoevo/plant-meta/blob/main/AGENTS.md). Keep family-wide concerns there, not here.
- **Issues & board** — follow the [issue guide](https://github.com/traitecoevo/plant-meta/blob/main/governance/issue-guide.md); work is tracked on [board #5](https://github.com/orgs/traitecoevo/projects/5) (new issues auto-add with no Status = the triage queue). Labels: `bug` / `task` / `epic` plus `blocked`, `needs-info`, `cross-package`, `breaking`, `question`.
- **Commit messages** — the repo squash-merges, so a PR's title and body are copied verbatim into permanent history. Keep them short and durable, and put the working detail in the first PR comment instead.
