# Contributing to MotiSig iOS SDK

Thank you for helping improve this project. By participating, you agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md).

## Getting started

1. Clone the repository and open the package in Xcode, or work from the command line with Swift 6 (see `Package.swift` `swift-tools-version`).
2. Run unit tests:

   ```bash
   swift test --filter MotiSigTests
   ```

3. Integration tests call the live API and are skipped unless environment variables are set (see below).

## Pull requests

- Keep changes focused on a single concern when possible.
- Match existing Swift style and naming in the module you touch.
- Add or update tests when behavior changes.
- Do not commit SDK keys, project IDs, or other secrets. Use local environment variables or ignored local files only.

## Integration tests

`MotiSigIntegrationTests` require:

- `MOTISIG_SDK_KEY`
- `MOTISIG_PROJECT_ID`
- `MOTISIG_BASE_URL` (valid URL)

See [Tests/MotiSigIntegrationTests/IntegrationTestCredentials.swift](Tests/MotiSigIntegrationTests/IntegrationTestCredentials.swift). Run with:

```bash
export MOTISIG_SDK_KEY="…"
export MOTISIG_PROJECT_ID="…"
export MOTISIG_BASE_URL="https://…"
swift test --filter MotiSigIntegrationTests
```

## Documentation

User-facing guides live under [docs/](docs/). When you change public API or runtime behavior, update the relevant doc and the [README](README.md) if install or quick-start instructions are affected.

## Code of Conduct enforcement contact

Reports under the Code of Conduct go to **conduct@vfcreative.com** (see [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)). Update those addresses in this repository if your organization uses different inboxes.

## License

Contributions are accepted under the [LICENSE](LICENSE) (MIT) unless you explicitly state otherwise in the pull request.
