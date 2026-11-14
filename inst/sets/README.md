# Parameter sets

One YAML file per species at a site. `fieldtrial::parameter_set("<name>")` reads `<name>.yml` from this folder and builds the four inputs of `plant::run()`; `run_set()` runs them.

Every scientific value is written `name: {value: <number>, source: "<Zotero key or dataset>"}`. A value without a source is refused. Run and control settings are plain values.

```yaml
schema: 1                           # the file format's version
name: mulga_alice_springs
description: "Acacia aneura at the Alice Springs Mulga flux site"
model: TF24                         # TF24, TF24f, TF24t, TF24w or FF16
plant_scientific_version: "TF24@v15"  # the plant model the values were checked against
site: {name: "Alice Springs Mulga (AU-ASM)", latitude: -22.283, longitude: 133.249, elevation: 606}
traits:                             # inputs to the trade-offs; one strategy
  lma: {value: 0.2, source: "Key-2020"}
tradeoff_coefficients:              # overrides of inst/tradeoffs/<family>.yml
  B_lf1: {value: 0.009, source: "Key-2020"}
pars:                               # parameters set directly; must not be derived by a trade-off
  hmat: {value: 6, source: "Key-2020"}
strategy:                           # top-level strategy fields (TF24t's thermal parameters)
  k_mat: {value: 0.02, source: "Key-2020"}
environment:
  soil:                             # depth and n_layers make a graded profile (top: surface layer, m)
    depth: {value: 1.5, source: "Key-2020"}
    n_layers: {value: 5, source: "Key-2020"}
    K_sat: {value: 16.3, source: "Key-2020"}
  fields:                           # other fields of the environment
    f_PAR: {value: 0.5, source: "Key-2020"}
drivers:
  source: worldclim                 # or met_file, with file: <path relative to this file>
  res: 10                           # WorldClim resolution, arc-minutes
  rainfall: spline                  # or pulse
  leaf_temp: true                   # set leaf_temp from the site's noon air temperature
run: {max_patch_lifetime: 50, birth_rate: 1}
control: {}                         # plant Control fields
provenance: {author: "", date: "", notes: ""}
```

A key that reaches none of plant's inputs is refused rather than ignored: an unknown trait, a parameter the trade-offs derive (set the trait it comes from instead), a field plant does not have. `check_set()` refuses a set whose `plant_scientific_version` differs from the installed plant's, since the same numbers can mean a different plant after a scientific change.
