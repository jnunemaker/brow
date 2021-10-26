# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2021-10-25

### Changed

- [c25dce](https://github.com/jnunemaker/brow/commit/c25dcedcab2b75cfe28a561e80e537fefae6cc52) `record` is now `push`.

### Fixed

- [eceb02](https://github.com/jnunemaker/brow/commit/eceb02f810cc5ace7d7540c957fc1cf924849629) Fixed problems with shutdown (required a flush to get whatever batches were in progress) and forking (caused queue to not get worked off).

### Added

- [c7f7e4](https://github.com/jnunemaker/brow/commit/c7f7e42b0d6bfa9fa96bac58fda0ef94f93d223d) `BackoffPolicy` now gets `options` so you can pass those to `Client` and they'll make it all the way through.

## [0.1.0] - 2021-10-20

- Initial release. Let's face it I just wanted to squat on the gem name.
