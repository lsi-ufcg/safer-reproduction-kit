# Changelog

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