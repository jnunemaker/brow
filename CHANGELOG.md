# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2021-11-04

### Added

- Allow configuring most options from ENV variables by default (fb7819b0237a81e573677f3050446a4f41e8fb47).
- Extra early return to avoid mutex lock if thread is alive (ac7dcfe54ee83b18e0df5ab3778a077584c843bd).
- Validation on many of the configuration options (c50b11a2917272a87937f8aa86007816a87c63a2 and 07e2581397f870249a347d4d68e4fce172d33cef).

### Changed

- Stop stringifying keys. Just enqueue whatever is passed and let JSON do the rest (2e63d5328e048f0fad9fc41ca0935f97fb5ada2f).
- A bunch of test stuff to make them faster and less flaky.

## [0.3.0] - 2021-10-29

https://github.com/jnunemaker/brow/pull/4

### Fixed

- Fixed thread churn. Upon digging in, I realized that the previous code was creating a bunch of threads. Basically one for each batch, which seems far from ideal. I'm surprised it worked that way. This changes it to be one worker thread that just sits there forever in a loop. When a batch is full, it transports it. When shutdown happens, a shutdown message is enqueued and the worker breaks the loop.
- Moved worker thread management to `Worker` from `Client`.
- Back off policy is now reset after `Transport#send_batch` completes. Previously it wasn't, which meant the next interval would get to the max and stay there.

### Changed

- Switched to stringify data keys instead of symbolize. Old versions of ruby didn't gc symbols so that was a memory leak. Might be fixed now, but strings are fine here so lets roll with them.
- Removed test mode and test queue. I didn't like this implementation and neither did @bkeepers. We'll come up with something new and better soon like Brow::Clients::Memory.new or something.

## [0.2.0] - 2021-10-25

### Changed

- [c25dce](https://github.com/jnunemaker/brow/commit/c25dcedcab2b75cfe28a561e80e537fefae6cc52) `record` is now `push`.

### Fixed

- [eceb02](https://github.com/jnunemaker/brow/commit/eceb02f810cc5ace7d7540c957fc1cf924849629) Fixed problems with shutdown (required a flush to get whatever batches were in progress) and forking (caused queue to not get worked off).

### Added

- [c7f7e4](https://github.com/jnunemaker/brow/commit/c7f7e42b0d6bfa9fa96bac58fda0ef94f93d223d) `BackoffPolicy` now gets `options` so you can pass those to `Client` and they'll make it all the way through.

## [0.1.0] - 2021-10-20

- Initial release. Let's face it I just wanted to squat on the gem name.
