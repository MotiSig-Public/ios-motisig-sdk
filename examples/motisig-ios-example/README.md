# motisig-ios-example

Sample app for the MotiSig Swift package in this repository (notifications + MotiSig SDK).

## Signing

The Xcode project does not commit an Apple **Development Team**. Open the workspace, select the **motisig-ios-example** and **MotiSigNSE** targets, then in **Signing & Capabilities** choose your team so the app and Notification Service Extension can run on device and use push-related entitlements.

## MotiSig credentials (environment variables)

The example reads configuration from `ProcessInfo.processInfo.environment` (not from a checked-in `.env` file).

1. In Xcode: **Product → Scheme → Edit Scheme… → Run → Arguments → Environment Variables**.
2. Add at least:
   - **`MOTISIG_SDK_KEY`** — your project SDK key from the MotiSig dashboard (required for a real backend; if unset, the app uses placeholder `demo_key` for local UI only).

Optional:

- **`MOTISIG_PROJECT_ID`** — defaults to `sdk-example` when unset.
- **`MOTISIG_BASE_URL`** — omit to use the SDK default (production client API). Set only if you intentionally point at another base URL.

Variable names match the repository root [`.env.local.example`](../../.env.local.example).

**Security:** If an SDK key was ever committed to version control or shared publicly, treat it as compromised and **revoke or rotate** it in the MotiSig project dashboard, then update your local scheme variables.
