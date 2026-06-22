# Releasing the MotiSig iOS SDK

Maintainers only. This package is distributed via **Swift Package Manager** — a release is an annotated **Git tag** on this repository. No registry credentials are required.

## Prerequisites

1. **Swift 6** toolchain (see `Package.swift` `swift-tools-version`).
2. Git access to push commits and tags to this repository.

No publish secrets or signing keys are needed for SPM source releases.

## Release checklist

1. **Write release notes** under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md).
2. **Dry-run** the release to verify steps without side effects:

   ```bash
   scripts/release.sh 1.0.2 --dry-run
   ```

3. **Run the release** (replace the version):

   ```bash
   scripts/release.sh 1.0.2
   ```

   The script will:

   - Roll `CHANGELOG.md` `[Unreleased]` into the new version with today's date
   - Update SPM version pins in [README.md](README.md) (`from:`, `upToNextMajor`, `exact:`)
   - Run [scripts/run-unit-tests.sh](scripts/run-unit-tests.sh)
   - Commit `Prepare release X.Y.Z`, create an annotated tag, and push branch + tag

4. **Verify** — in Xcode or another `Package.swift`, resolve the new tag:

   ```swift
   .package(url: "https://github.com/MotiSig-Public/ios-motisig-sdk.git", from: "1.0.2")
   ```

5. **Swift Package Index** (optional) — if the repo is registered at [swiftpackageindex.com/add-a-package](https://swiftpackageindex.com/add-a-package), indexing picks up new tags automatically.

## Options

```bash
scripts/release.sh <X.Y.Z> [--dry-run] [--skip-tests] [--remote origin]
```

| Flag | Effect |
|------|--------|
| `--dry-run` | Print every step; no file edits, commits, tags, or push |
| `--skip-tests` | Skip unit tests (use only when you have already verified locally) |
| `--remote <name>` | Git remote to push (default: `origin`) |

## Manual release (without the script)

```bash
# 1. Update CHANGELOG.md and README.md version pins
# 2. Run tests
scripts/run-unit-tests.sh
# 3. Commit, tag, push
git commit -am "Prepare release 1.0.2"
git tag -a 1.0.2 -m "Release 1.0.2"
git push origin main
git push origin 1.0.2
```
