# Count Version Changes

Counts, for each row of the dataset, the version changes Safer applied, by
semver type.

## Columns

It keeps every column of the input dataset (including the ones
`bash/report-to-csv.py` adds) and appends:

| column | meaning |
|---|---|
| `javaVersion` | Java version Safer used for the project (`run.json`, `tools.java`) |
| `countMajor` | dependencies updated with a major change |
| `countMinor` | dependencies updated with a minor change |
| `countPatch` | dependencies updated with a patch change |
| `countPrerelease` | dependencies updated with a pre-release change |
| `countBuildmetadata` | dependencies updated with a build-metadata change |
| `countNoChange` | dependencies Safer evaluated and kept at the same version |
| `countOther` | updates that fit none of the five types: a version outside the `X.Y.Z` form (e.g. `1.9 -> 1.10.0`), or a difference only past the third number or in the qualifier (e.g. `2.9.10 -> 2.9.10.8`, `1.0.0-RC1 -> 1.0.0`) |

The semver classification is the same as the previous version of this script
(same regular expression, same order of checks). That script silently dropped
the `countOther` cases and had no `countNoChange`; with both columns, the counts
add up to the number of dependencies Safer evaluated.

Only dependencies Safer evaluates are counted. Skipped ones are left out:
versions managed by a parent POM or BOM, `test`/`provided` scope (which
includes the test dependencies `bash/prepare-project.sh` injects). Each member of
a group (dependencies upgraded together) counts once.

## Input

- The dataset written by `bash/report-to-csv.py` (e.g. `results/dataset_native_kex.csv`).
- For each row, the Safer run directory in `outputs/v2/<project>/safer-run` or
  `outputs/v2/<project>/execution_<n>/safer-run`, found by the row `id` (in the
  `kit.json` that `bash/run-experiment.sh` writes there).

## How to Run

Requires `./setup-safer.sh` (the script reuses Safer's `tsx` and version code).

```
cd post-processing/count-version-changes
../../safer/node_modules/.bin/tsx src/script.ts ../../results/dataset_native_kex.csv
```

Output: `final-<dataset name>` next to the input (`-o` to change it;
`--outputs` to point to another outputs directory; default `outputs/v2`).
