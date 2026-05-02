#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ ! -f .env.local ]; then
  echo "error: .env.local not found at ${ROOT}/.env.local" >&2
  echo "Copy .env.local.example to .env.local and set MOTISIG_SDK_KEY, MOTISIG_PROJECT_ID, MOTISIG_BASE_URL." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
. ./.env.local
set +a

exec swift test --filter '^MotiSigIntegrationTests\.' "$@"
