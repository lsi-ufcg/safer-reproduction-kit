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