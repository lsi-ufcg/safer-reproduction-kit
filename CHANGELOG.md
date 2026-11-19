# Changelog

## Migration to the new Safer

`safer.zip` now ships the new Safer (a rewrite). Safer itself is used unchanged; everything
the previous Safer did for this experiment moved into the kit. Results are not comparable
with the paper's, so they go to `results/v2/` and `outputs/v2/`.

### Added

-   **`bash/prepare-project.sh`** (with `bash/prepare/pom_tools.py`) takes over what the
    previous `run-maven-build.sh` did: installs the EvoSuite runtime, injects the test
    dependencies of the generated suites, aligns `junit-vintage-engine` with the project's
    JUnit Platform and writes the test flags to `.mvn/maven.config`. The `pom.xml` is now
    edited as text, so only the injected blocks change (ElementTree dropped comments and
    reformatted the whole file).
-   **Runtime tree check.** `prepare-project.sh` resolves the runtime tree before and after
    the injection and records any difference in `results/v2/prepare-project_<combination>.csv`:
    a direct `test` declaration takes a transitive artifact (typically `junit`) out of the
    tree Safer scores.
-   **`libs/evosuite-standalone-runtime-1.1.0.jar`**, checked by SHA-256. It used to ship
    inside `safer.zip`, and version 1.1.0 is not on Maven Central. It is copied straight into
    Safer's Maven cache with a minimal POM, so no Maven is needed on the host.
-   **`bash/report-to-csv.py`** builds the dataset row from Safer's run directory, which
    replaces the `CSV:` line of the previous Safer. Same 20 columns, plus
    `Unknown vulnerabilities (Before/After)`, `Rate (Before/After)` and `Tests Executed`.
    It refuses to append to a CSV with the previous header.
-   **`safer-config.json`**: Safer's defaults with `projectTests: true`, passed through
    `SAFER_CONFIG`.
-   **`post-processing/lib/safer-run.ts`**, shared by both post-processing scripts.

### Changed

-   **`run-test-filtering.sh`** runs Safer's build (`mvn -B clean verify`) in its own
    container (`java-container-safer-filter-<project>`, started by Safer's
    `init-java-container.sh`), calls `prepare-project.sh` before the first round and backs
    up the `pom.xml` after it, so Safer receives the prepared `pom.xml`. The `pom.xml` is no
    longer restored between rounds (the build does not touch it any more). Default time
    limit 3600 s, as in Safer. New statuses `prepare_error` and `killed` (Maven killed
    before the time limit, previously reported as `timeout`). Output paths that did not
    exist yet resolved to an empty string; fixed with `readlink -m`.
-   **`bash/test-filtering/safer-java-version.ts`** uses the new Safer's `detectJavaVersion`
    (raw `pom.xml`, 17 as fallback) instead of the removed `MavenAdapter`.
-   **`bash/run-experiment.sh`** passes Safer an absolute project path, takes the run
    directory from the `Safer run dir:` line, moves it to `outputs/v2/<project>/safer-run`
    (with a `kit.json` holding the row `id`), converts it with `report-to-csv.py`, and exits
    1 on failure (it always exited 0).
-   **`execucao_safer.sh`** writes to `results/v2/` and `outputs/v2/`, passes the prepare CSV
    to the filter and moves `safer-run/` into `execution_<n>/`.
-   **`post-processing/count-version-changes`** and **`calculate-offset-changes`** read
    Safer's `decisions.jsonl` and `run.json` instead of the previous stdout text, now in
    TypeScript (they import Safer's version ordering). They keep every input column, find
    each row's run by `id` (also across `execution_<n>/`), and the offsets script rewrites its
    output instead of appending to it.
-   **`count-version-changes`** adds `countNoChange` (dependencies Safer kept; the column
    existed in the published datasets but not in the script) and `countOther` (updates that
    fit no semver category, e.g. `1.9 -> 1.10.0`, which the previous script dropped
    silently). The semver classification itself is unchanged.
-   **`calculate-offset-changes`** takes the version list from Safer's `candidates` events,
    pre-releases included, so `bash/get-dependencies-versions.sh` is no longer needed.
-   **`setup-safer.sh`** uses `npm ci`: `npm install` could rewrite `package-lock.json`,
    leaving Safer's repository dirty and every `run.json` with `"dirty": true`.

### Removed

-   The previous Safer's own patches described below (`MavenAdapter` filter,
    `run-maven-build.sh`, `init-java-container.sh` EvoSuite install): the new Safer skips
    `test`-scope dependencies by itself, and the rest lives in `prepare-project.sh`.
-   `post-processing/*/src/script.js`, replaced by `src/script.ts`.

---

# Previous Safer (paper)

## Added

### Ignore EvoSuite runtime dependency during dependency analysis

Added a filtering mechanism in `MavenAdapter.ts` to ignore the dependency:

```ts
org.evosuite:evosuite-standalone-runtime
```

during Maven dependency extraction.

Previously, the dependency was being included in the dependency analysis pipeline, causing the Safer tool to:

- analyze EvoSuite runtime vulnerabilities;
- search for alternative versions;
- attempt automatic dependency updates;
- include EvoSuite in generated reports.

This behavior was undesirable because the EvoSuite runtime is only required for test execution support and should not be treated as a project dependency candidate for vulnerability remediation.

The filtering was implemented directly inside:

```ts
MavenAdapter.getFromMvn()
```

after parsing the output of:

```bash
mvn dependency:list -DexcludeTransitive=true
```

#### Before

All dependencies returned by Maven were considered by Safer.

#### After

The following dependency is ignored during dependency extraction:

```ts
const ignoredDependencies = [
  { group: 'org.evosuite', name: 'evosuite-standalone-runtime' },
];
```

This change allows EvoSuite-based tests to continue executing normally while preventing the dependency from interfering with vulnerability analysis and automatic version replacement.

Files modified:

- `maven-adapter.ts`

---

## Fixed

### EvoSuite runtime descriptor breaking dependency resolution

`init-java-container.sh` installs `evosuite-standalone-runtime` into the container's local
repository with `mvn install:install-file`. Since no `-DpomFile` is given, the plugin takes
the POM embedded in the jar's `META-INF/maven`, and that POM inherits from:

```
org.evosuite:evosuite:1.1.0
```

a parent that was never published to Maven Central. Any project that needs to read the
descriptor of the EvoSuite dependency then fails before compiling anything:

```
Failed to collect dependencies at org.evosuite:evosuite-standalone-runtime:jar:1.1.0:
Failed to read artifact descriptor for org.evosuite:evosuite-standalone-runtime:jar:1.1.0:
Could not find artifact org.evosuite:evosuite:pom:1.1.0 in central
```

`run-maven-build.sh` now replaces that descriptor with a minimal POM inside the container,
right before invoking Maven. The jar is shaded and has no transitive dependency, so
dropping the parent and the dependency list has no side effect.

The replacement is idempotent and guarded by a check for the artifact directory, so it is a
no-op when the EvoSuite runtime was not installed.

Files modified:

- `run-maven-build.sh`

---

### EvoSuite runtime install reading the project POM

`init-java-container.sh` installs the EvoSuite runtime with `mvn install:install-file`, and
the container's `WORKDIR` is `/app`. Maven therefore read the project's `pom.xml` before
installing the jar, which made the installation depend on resolving the project's parent
POM over the network:

```
Non-resolvable parent POM ... Could not transfer artifact org.springframework.boot:...
```

A network hiccup left the container unbuilt, and the project went through the pipeline with
no filtering at all. In one run this accounted for 71 projects in a row.

The command now runs from `/tmp`, where there is no POM to read. Installing the jar never
depended on the project in the first place.

Files modified:

- `init-java-container.sh`

---

### junit-vintage-engine version mismatch hiding every test

The generated suites are JUnit 4, so `run-maven-build.sh` injects
`org.junit.vintage:junit-vintage-engine` for Surefire to discover them. The version was
fixed at 5.10.0, but many projects manage the JUnit Platform at an older version --
`spring-boot-starter-test` 2.1, for instance, pins it at 1.3.2. Maven then downgrades the
Platform that vintage 5.10.0 needs, and discovery dies with:

```
java.lang.NoClassDefFoundError: org/junit/platform/commons/util/LruCache
    at org.junit.vintage.engine.descriptor.TestSourceProvider.<init>
```

Depending on the Surefire version this surfaced as a loud
`TestEngine with ID 'junit-jupiter' failed to discover tests`, or silently as
`Tests run: 0` -- and with `-DfailIfNoTests=true` the build failed with
`No tests were executed!`. In one run this accounted for roughly one project in six.

The version is now aligned with the Platform the project actually resolves: jupiter and
vintage are released together, so Platform `1.X.Y` corresponds to vintage `5.X.Y`. The
lookup runs once per project, right after the dependency enters the POM -- the managed
version is not visible before that.

Measured on `amigoscode_springboot-twilio` (45 generated suites): before, 0 tests executed
and the build failed; after, 43 tests executed, and the filter converged to 35 green tests.

Files modified:

- `run-maven-build.sh`

---

## Changed

### Maven test execution patterns

Updated `run-maven-build.sh` to support broader test discovery patterns during Maven execution.

#### Previous command

```bash
-Dtest='*'
```

#### New command

```bash
-Dtest='*Test,*Tests,*TestCase,*_ESTest,*_init_*,*_equals_*'
```

The new configuration enables execution of:

- native project tests;
- EvoSuite generated tests;
- Kex generated tests.

This improves compatibility with automatically generated test suites that do not follow standard Maven naming conventions.

Files modified:

- `run-maven-build.sh`

---

## Recommended Maven test execution configurations

### Execute all tests

```bash
CMD="mvn clean install \
  -Dmaven.repo.local=/opt/maven-repo \
  -DskipTests=false \
  -Dmaven.test.skip=false \
  -Ddependency-check.skip=true \
  -DfailIfNoTests=false \
  -Dtest='*Test,*Tests,*TestCase,*_ESTest,*_init_*,*_equals_*'"
```

### Execute only EvoSuite tests

```bash
CMD="mvn clean install \
  -Dmaven.repo.local=/opt/maven-repo \
  -DskipTests=false \
  -Dmaven.test.skip=false \
  -Ddependency-check.skip=true \
  -DfailIfNoTests=false \
  -Dtest='*_ESTest'"
```

### Execute only Kex tests

```bash
CMD="mvn clean install \
  -Dmaven.repo.local=/opt/maven-repo \
  -DskipTests=false \
  -Dmaven.test.skip=false \
  -Ddependency-check.skip=true \
  -DfailIfNoTests=false \
  -Dtest='*_init_*,*_equals_*'"
```

### Execute EvoSuite + Kex tests

```bash
CMD="mvn clean install \
  -Dmaven.repo.local=/opt/maven-repo \
  -DskipTests=false \
  -Dmaven.test.skip=false \
  -Ddependency-check.skip=true \
  -DfailIfNoTests=false \
  -Dtest='*_ESTest,*_init_*,*_equals_*'"
```