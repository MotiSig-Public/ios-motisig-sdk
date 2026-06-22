# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
when version tags are published.

## [Unreleased]

## [1.0.2] - 2026-06-22

## [1.0.1] - 2026-05-26

### Fixed

- Push **click tracking** reliability: persistent FIFO queue, deduplication, and exponential-backoff retries until delivery succeeds or entries expire (new internal `ClickDispatcher`, `PendingClicksQueue`, `ClickDedupeStore`).
- **Cold-start** notification taps: optional `launchOptions` on `MotiSig.initialize` (UIKit) so `launchOptions[.remoteNotification]` is handled during init; improved AppDelegate / scene swizzling and notification-center proxy for SwiftUI and UIKit.
- Duplicate click delivery when the same tap is observed via both cold-start `launchOptions` and `UNUserNotificationCenter` delegate paths.

### Changed

- README quick start: separate **SwiftUI** (`@UIApplicationDelegateAdaptor`) and **UIKit** examples; document that init must run in `application(_:didFinishLaunchingWithOptions:)` for push click tracking.
- Example app: passes `launchOptions` into `MotiSig.initialize`.

### Added

- Unit tests: `EventBufferReplayTests`, `PushNotificationManagerTests`.

## [1.0.0] - 2026-05-01

First **semver Git tag** for Swift Package Manager consumption (`1.0.0`).

- Documentation: README (SPM install, versioning, Swift Package Index), client guides under `docs/`, and open-source community files (license, security, contributing, code of conduct).
