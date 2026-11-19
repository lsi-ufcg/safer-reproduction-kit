# Calculate Offset Changes

For each dependency Safer evaluated, this script calculates the distance (in
published versions) between the current version and the version Safer applied,
and between the version Safer applied and the newest version of the dependency.

## Columns

`projectName, tests, javaVersion, dependency, oldVersion, newVersion,
mostRecentVersion, oldVersionOffset, mostRecentVersionOffset, semVerChange, id`

The first ten are the same as in the previous version of this script; `id` (the
dataset row) was added at the end, so several executions of the same project
can be told apart.

- `oldVersionOffset`: versions between the current one and the applied one (0
  when Safer kept the dependency).
- `mostRecentVersionOffset`: versions between the applied one and the newest.
- `semVerChange`: `major`, `minor`, `patch`, `prerelease`, `buildmetadata`,
  `not semantic version` (a version outside the `X.Y.Z` form), `-` (none of the
  types) or `not changed`.

The version list comes from the `candidates` event of each run: every version
newer than the current one, including the ones Safer does not consider
(pre-releases, date-style versions, other flavors such as `-android`), like the
Sonatype list the previous script read. It is ordered by Safer's own version
comparison. `bash/get-dependencies-versions.sh` is no longer needed.

## Input

The same as `count-version-changes`: the dataset written by
`bash/report-to-csv.py` and the Safer run directories in `outputs/v2/`.

## How to run

Requires `./setup-safer.sh`.

```
cd post-processing/calculate-offset-changes
../../safer/node_modules/.bin/tsx src/script.ts ../../results/dataset_native_kex.csv
```

Output: `version-changes-<dataset name>` next to the input (`-o` to change it).
The file is rewritten on each run (the previous script appended to it).
