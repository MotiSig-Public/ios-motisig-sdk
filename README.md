# MotiSig iOS SDK

> Swift package: **MotiSig**
>
> Official SDK from [MotiSig AI](https://motisig.ai).

Swift package for integrating **MotiSig AI** into **iOS** and **macOS** apps: user registration, profile and tags, custom attributes, analytics-style events, APNs token registration, and notification delivery hooks.

Distribution is **Swift Package Manager only** (no CocoaPods podspec in this repository).

## Requirements

- **iOS 14+** or **macOS 11+** (see `Package.swift` `platforms`)
- **Swift 6** toolchain (`swift-tools-version: 6.0`)

Use a recent Xcode that supports Swift 6 when developing or consuming this package.

## Installation (SPM)

Published versions are **Git tags** on this repository ([Semantic Versioning](https://semver.org/)). Pick a rule that matches how tightly you want to track releases: `from: "1.0.0"` (minimum version), `.upToNextMajor(from: "1.0.0")`, or `exact: "1.0.0"` for a fixed pin. Release notes: [CHANGELOG.md](CHANGELOG.md).

### Xcode (app or framework)

**File → Add Package Dependencies…** → paste:

`https://github.com/MotiSig-Public/ios-motisig-sdk.git`

Choose a version rule (e.g. **Up to Next Major** from `1.0.0`). Add the **MotiSig** product to the targets that need it.

### Another `Package.swift`

Add the package URL, then depend on the **MotiSig** product (the SwiftPM package name is the repository name, `ios-motisig-sdk`):

```swift
.package(url: "https://github.com/MotiSig-Public/ios-motisig-sdk.git", from: "1.0.0")
```

```swift
.target(
    name: "YourAppOrLib",
    dependencies: [
        .product(name: "MotiSig", package: "ios-motisig-sdk"),
    ]
)
```

Replace the version requirement to match the release tag you pin.

To work on the SDK locally, add a **local package** dependency pointing at your clone.

### Swift Package Index

To list this package on [Swift Package Index](https://swiftpackageindex.com/) for discovery and compatibility badges, a maintainer adds the **public GitHub URL** once the repo has at least one semver tag: [Add a package](https://swiftpackageindex.com/add-a-package). Indexing still resolves the same Git URL and tags as Xcode.

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
        // Handle notification; see https://motisig.ai/docs/sdks/ios/push-notifications
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

Details and defaults: **[Configuration](https://motisig.ai/docs/sdks/ios/configuration)** (local pointer: [docs/CONFIGURATION.md](docs/CONFIGURATION.md)).

## Push and iOS setup

Enable **Push Notifications** (and any required background modes) for your app target. After `initialize`, the SDK participates in permission requests, token registration, and notification handling (including AppDelegate swizzling as documented in code).

For listeners, ordering, buffering, and click tracking behavior, read **[Push notifications](https://motisig.ai/docs/sdks/ios/push-notifications)** ([docs/PUSH_NOTIFICATIONS.md](docs/PUSH_NOTIFICATIONS.md)).

### Rich push images

Banner images require a **Notification Service Extension (NSE)** in your app — iOS does not auto-download remote URLs. The SDK ships `MotiSigRichPushHandler`, so the NSE is a one-line forwarder. The server payload uses `_motisig.imageUrl` and `mutable-content: 1`.

Full Xcode walkthrough, payload contract, and troubleshooting: **[Rich notification images](https://motisig.ai/docs/sdks/ios/rich-images)** ([docs/RICH_IMAGES.md](docs/RICH_IMAGES.md)). A reference target lives at [`examples/motisig-ios-example/MotiSigNSE/`](examples/motisig-ios-example/MotiSigNSE/).

## Documentation

Authoritative guides live on **[MotiSig AI — iOS & macOS](https://motisig.ai/docs/sdks/ios)**. The `docs/*.md` files in this repository are short pointers for backwards compatibility and GitHub browsing.

| Guide | Description |
|-------|-------------|
| [Getting started](https://motisig.ai/docs/sdks/ios/getting-started) | Lifecycle and mutation ordering |
| [Configuration](https://motisig.ai/docs/sdks/ios/configuration) | Keys, URLs, logging, environment, init flags |
| [User and profile](https://motisig.ai/docs/sdks/ios/user-profile) | `setUser`, `updateUser`, `logout` |
| [Events, tags, attributes](https://motisig.ai/docs/sdks/ios/events-tags-attributes) | Tags, attributes, `ping`, `triggerEvent` |
| [Push notifications](https://motisig.ai/docs/sdks/ios/push-notifications) | APNs, listeners, subscriptions |
| [Rich images](https://motisig.ai/docs/sdks/ios/rich-images) | Notification Service Extension and image payload |
| [Privacy and data](https://motisig.ai/docs/sdks/ios/privacy-and-data) | Data categories for your privacy disclosures |
| [Troubleshooting](https://motisig.ai/docs/sdks/ios/troubleshooting) | Symptom-driven debugging checklist |
| [Migration](https://motisig.ai/docs/sdks/ios/migration) | Cross-SDK API parity |
| [Versioning](https://motisig.ai/docs/sdks/ios/versioning) | SemVer policy and canonical push payload contract |

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
