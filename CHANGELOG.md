# Changelog

Breaking changes to an image's contract (removed tools, changed users, paths or defaults) are listed here. `ci-tools` bumps its major tag for them. The PHP images follow PHP minor versions, and breaking changes are announced here before they ship.

## Unreleased

### Added
- `ci-tools:1`, `php-ci:8.3|8.4|8.5` and `php-devcloud:8.3|8.4|8.5`: the initial images replacing `phase2/docker-cli`. Every PHP version, with its extensions, comes from packages.sury.org.

### Changed
- `php-ci` and `php-devcloud`: `zend.assertions = 1` (was Debian's production `-1`), so `assert()` runs, as it did in `phase2/docker-cli`. Assertion failures that `-1` hid will now surface.
