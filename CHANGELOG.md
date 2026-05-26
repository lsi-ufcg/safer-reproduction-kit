# Changelog

## [Experimental Test Execution Update]

### Added
- Support for EvoSuite runtime installation inside Docker containers.
- Automatic installation of `evosuite-standalone-runtime-1.1.0.jar`.
- Dedicated Maven local repository inside containers (`/opt/maven-repo`).
- Forced execution of all detected test suites during Maven builds.

### Changed
- Maven execution now always runs tests (`-DskipTests=false`).
- Docker image now creates and configures `/opt/maven-repo`.
- Maven download source updated to Apache archive repository.
- Verbose logging enabled for Maven executions.

### Fixed
- Dependency resolution failure for EvoSuite runtime.
- Maven local repository permission issues inside Docker containers.
- Inconsistent execution of generated and native tests.
- Build instability caused by missing runtime dependencies.