# fieldtrial

Sets up [`plant`](https://github.com/traitecoevo/plant) runs by bundling a site's environment with a species' trait trade-offs and parameter sets.

> **Status: early development.** Interfaces may still change; the scope and sequencing are in [`PLAN.md`](PLAN.md).

`fieldtrial` owns three things for the plant model:

- **Parameter sets** for named species and sites (mulga at Alice Springs and at Delta, alpine ash at Tumbarumba), each a reviewable YAML record that cites a source for every value.
- **Trait trade-offs**: the functions that derive model parameters from traits, moved out of `plant`, where a frozen copy remains as an explicitly loaded testing set.
- **Environmental drivers**: adapters that turn gridded and flux-tower climate into the daily driver series `plant` reads (WorldClim today; AGCD, FLUXNET Shuttle and CRU TS planned), and generators of rainfall pulse series.

The [Overstorey](https://traitecoevo.github.io/overstorey/) guides show `plant` in use; its guides on strategies and traits and on extrinsic drivers will use fieldtrial's trade-offs and drivers.

## Installation

```r
# install.packages("pak")
pak::pak("traitecoevo/fieldtrial")
```

This also installs `plant` at the commit fieldtrial is pinned to (the `Remotes:` field of `DESCRIPTION`, recorded with the plant changes it has absorbed in [`.plant-interface-version`](.plant-interface-version)). `plant` compiles from source, so a C++ toolchain is needed.

## Using fieldtrial

Attach the recommended trade-offs to a `plant` `Parameters` object, so each strategy's parameters are derived from its traits:

```r
library(fieldtrial)
p <- plant::scm_base_parameters("TF24")
p$hyperpar <- tradeoffs("TF24")
p <- plant::add_strategies(p, plant::trait_matrix(0.1, "lma"))
p$strategies[[1]]$pars[c("lma", "k_l", "r_l")]
tradeoff_table("TF24")   # every coefficient, with units and source
```

List the named parameter sets, load one, and run it (the first load downloads WorldClim's 10 arc-minute grids, about 200 MB, and caches them):

```r
list_sets()
set <- parameter_set("mulga_alice_springs")
set                  # p, env, ctrl and events: the four inputs of plant::run_scm()
res <- run_set(set)  # a 105-year patch: about ten minutes
```

Build driver series for a site yourself: a mean year from WorldClim, repeated and written into a TF24 environment, or a drawn series of rainfall pulses:

```r
met <- met_from_worldclim(-22.283, 133.249)   # Alice Springs Mulga: a daily mean year
d <- apply_drivers(plant::Environment("TF24"), met_repeat(met, 5),
                   rainfall = "spline", drivers = c("SWdown", "atm_vpd", "leaf_temp",
                                                    "atm_kpa", "wind_speed", "rainfall"))
d$drivers                                     # which drivers came from the table

set.seed(1)
rain <- pulse_series_poisson(0, 100, rate = 20, mean_amount = 0.014)  # ~0.28 m a year
ev <- plant::rainfall_pulse(rain$time, rain$amount)                   # for plant::events()
```

## Plant family

`fieldtrial` is part of the **plant family** of packages in the [`traitecoevo`](https://github.com/traitecoevo) org, built around the [`plant`](https://github.com/traitecoevo/plant) forest model. Docs hub: <https://traitecoevo.github.io/overstorey/>.

**Contributing:** please skim the family [issue guide](https://github.com/traitecoevo/plant-meta/blob/main/governance/issue-guide.md) before filing. Issues across the family are triaged on [board #5](https://github.com/orgs/traitecoevo/projects/5), and cross-package context lives in [`plant-meta`](https://github.com/traitecoevo/plant-meta).

## Licence

AGPL (>= 3), the same licence as `plant`, since the trade-off functions are ported from it.
