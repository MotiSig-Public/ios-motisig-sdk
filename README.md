# MotiSig iOS SDK

Swift package for integrating **MotiSig** into iOS and macOS apps: user registration, profile and tags, custom attributes, analytics-style events, APNs token registration, and notification delivery hooks.

Distribution is **Swift Package Manager only** (no CocoaPods podspec in this repository).

## Requirements

- **iOS 14+** or **macOS 11+** (see `Package.swift` `platforms`)
- **Swift 6** toolchain (`swift-tools-version: 6.0`)

Use a recent Xcode that supports Swift 6 when developing or consuming this package.

## Installation (SPM)

In Xcode: **File → Add Package Dependencies…** and enter your Git URL for this repository.

In another Swift package, add a dependency:

```swift
.package(url: "https://github.com/YOUR_ORG/motisig-sdk-ios.git", from: "1.0.0")
```

Replace the URL and version requirement with the values for your fork or release tags.

To work on the SDK locally, add a **local package** dependency pointing at your clone.

## Quick start

```swift
import MotiSig

// Call once at launch (e.g. AppDelegate or @main App)
MotiSig.initialize(
    sdkKey: "YOUR_SDK_KEY",
    projectId: "YOUR_PROJECT_ID",
    baseURL: nil,
    logLevel: .info
)

// After sign-in
MotiSig.shared.setUser(id: userId)

MotiSig.shared.addTags(["premium"])

MotiSig.shared.triggerEvent(eventName: "screen_view", data: ["screen": "home"]) { result in
    switch result {
    case .success(let message):
        print(message)
    case .failure(let error):
        print(error)
    }
}

final class NotificationRouter: MotiSigNotificationListener {
    func motiSig(didReceiveNotification notification: MotiSigNotification, inForeground: Bool) {
        // Handle notification; see docs/PUSH_NOTIFICATIONS.md
    }
}
// Retain your listener; the SDK holds it weakly.
private let router = NotificationRouter()
private var subscription: MotiSigNotificationSubscription?

func registerListener() {
    subscription = MotiSig.shared.addNotificationListener(router, order: 0)
}
```

## Example

See [examples/motisig-ios-example](examples/motisig-ios-example). Open `examples/motisig-ios-example/motisig-ios-example.xcodeproj` in Xcode. The app target depends on this repository as a **local Swift package** (`../..` from the example folder to the package root), so you can run and debug against the SDK sources in the same clone.

## Configuration

You can pass `sdkKey`, `projectId`, and `baseURL` explicitly, or rely on the process environment:

| Environment variable   | Purpose |
|------------------------|---------|
| `MOTISIG_SDK_KEY`      | Used when `sdkKey` is empty |
| `MOTISIG_PROJECT_ID`   | Used when `projectId` is empty |
| `MOTISIG_BASE_URL`     | Used when `baseURL` is `nil` |

Details and defaults: [docs/CONFIGURATION.md](docs/CONFIGURATION.md).

## Push and iOS setup

Enable **Push Notifications** (and any required background modes) for your app target. After `initialize`, the SDK participates in permission requests, token registration, and notification handling (including AppDelegate swizzling as documented in code).

For listeners, ordering, buffering, and click tracking behavior, read [docs/PUSH_NOTIFICATIONS.md](docs/PUSH_NOTIFICATIONS.md).

### Rich push images

Banner images require a **Notification Service Extension (NSE)** in your app — iOS does not auto-download remote URLs. The SDK ships `MotiSigRichPushHandler`, so the NSE is a one-line forwarder. The server payload uses `_motisig.imageUrl` and `mutable-content: 1`.

Full Xcode walkthrough, payload contract, and troubleshooting: **[docs/RICH_IMAGES.md](docs/RICH_IMAGES.md)**. A reference target lives at [`examples/motisig-ios-example/MotiSigNSE/`](examples/motisig-ios-example/MotiSigNSE/).

## Documentation

| Guide | Description |
|-------|-------------|
| [docs/GETTING_STARTED.md](docs/GETTING_STARTED.md) | Lifecycle and mutation ordering |
| [docs/CONFIGURATION.md](docs/CONFIGURATION.md) | Keys, URLs, logging, environment |
| [docs/USER_PROFILE.md](docs/USER_PROFILE.md) | `setUser`, `updateUser`, `logout` |
| [docs/EVENTS_TAGS_ATTRIBUTES.md](docs/EVENTS_TAGS_ATTRIBUTES.md) | Tags, attributes, `ping`, `triggerEvent` |
| [docs/PUSH_NOTIFICATIONS.md](docs/PUSH_NOTIFICATIONS.md) | APNs, listeners, subscriptions |
| [docs/RICH_IMAGES.md](docs/RICH_IMAGES.md) | Notification Service Extension and image payload |
| [docs/PRIVACY_AND_DATA.md](docs/PRIVACY_AND_DATA.md) | Data categories for your privacy disclosures |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Symptom-driven debugging checklist |
| [docs/MIGRATION.md](docs/MIGRATION.md) | Cross-SDK API parity and versioning |

Public API is also documented with Swift DocC comments in `Sources/MotiSig/`.

## Development

Run unit tests from the package root:

```bash
swift test --filter MotiSigTests
```

**Integration tests** hit the live API and are skipped unless `MOTISIG_SDK_KEY`, `MOTISIG_PROJECT_ID`, and `MOTISIG_BASE_URL` are set in the environment. See [Tests/MotiSigIntegrationTests/IntegrationTestCredentials.swift](Tests/MotiSigIntegrationTests/IntegrationTestCredentials.swift). Do not commit real credentials.

See [CONTRIBUTING.md](CONTRIBUTING.md) for pull requests and [SECURITY.md](SECURITY.md) for vulnerability reporting.

## Changelog

Release notes: [CHANGELOG.md](CHANGELOG.md).

## License

Published under the [MIT License](LICENSE) (Copyright (c) 2026 VF Creative Inc.).

## Community

- [Code of Conduct](CODE_OF_CONDUCT.md)
- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)
