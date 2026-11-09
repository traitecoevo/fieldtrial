# fieldtrial

Sets up [`plant`](https://github.com/traitecoevo/plant) runs by bundling a site's environment with a species' trait trade-offs and parameter sets.

> **Status: scaffolding.** The scope and sequencing are in [`PLAN.md`](PLAN.md); nothing here is usable yet.

`fieldtrial` owns three things for the plant model:

- **Parameter sets** for named species and sites (first: mulga at Alice Springs, a tall eucalypt), each a reviewable YAML record with provenance.
- **Trait trade-offs**: the functions that derive model parameters from traits, moved out of `plant`, where a frozen copy remains as an explicitly loaded testing set.
- **Environmental drivers**: adapters that turn gridded and flux-tower climate (AGCD, FLUXNET Shuttle, WorldClim, CRU TS) into the daily driver series `plant` reads.

## Plant family

`fieldtrial` is part of the **plant family** of packages in the [`traitecoevo`](https://github.com/traitecoevo) org, built around the [`plant`](https://github.com/traitecoevo/plant) forest model. Docs hub: <https://traitecoevo.github.io/overstorey/>.

**Contributing:** please skim the family [issue guide](https://github.com/traitecoevo/plant-meta/blob/main/governance/issue-guide.md) before filing. Issues across the family are triaged on [board #5](https://github.com/orgs/traitecoevo/projects/5), and cross-package context lives in [`plant-meta`](https://github.com/traitecoevo/plant-meta).

## Licence

AGPL (>= 3), the same licence as `plant`, since the trade-off functions are ported from it.
