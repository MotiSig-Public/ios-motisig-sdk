#!/bin/sh
# Full Swift Package Manager release helper for MotiSig iOS SDK.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION=""
DRY_RUN=0
SKIP_TESTS=0
REMOTE="origin"

usage() {
  cat <<'EOF'
Usage: scripts/release.sh <X.Y.Z> [--dry-run] [--skip-tests] [--remote <name>]

Full SPM release:
  1. Roll CHANGELOG [Unreleased] into the new version
  2. Update README SPM version pins
  3. Run unit tests
  4. Commit, annotated tag, push

No publish credentials are required — consumers resolve the new Git tag via SPM.
EOF
  exit "${1:-0}"
}

log() {
  printf '%s\n' "$*"
}

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] $*"
  else
    log "+ $*"
    "$@"
  fi
}

validate_semver() {
  case "$1" in
    [0-9]*.[0-9]*.[0-9]*)
      case "$1" in
        *[!0-9.]*)
          log "error: invalid semver (digits and dots only): $1" >&2
          exit 1
          ;;
      esac
      ;;
    *)
      log "error: invalid semver: $1" >&2
      exit 1
      ;;
  esac
}

latest_released_version() {
  git tag --list '[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | head -n 1
}

roll_changelog() {
  local version="$1"
  local date
  date="$(date +%Y-%m-%d)"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] roll CHANGELOG [Unreleased] -> [$version] - $date"
    return 0
  fi
  awk -v ver="$version" -v dt="$date" '
    /^## \[Unreleased\]/ {
      print "## [Unreleased]"
      print ""
      print "## [" ver "] - " dt
      next
    }
    { print }
  ' CHANGELOG.md > CHANGELOG.md.tmp
  mv CHANGELOG.md.tmp CHANGELOG.md
}

bump_readme_pins() {
  local old_version="$1"
  local new_version="$2"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] update README SPM pins: $old_version -> $new_version"
    return 0
  fi

  sed \
    -e "s/from: \"${old_version}\"/from: \"${new_version}\"/g" \
    -e "s/\\.upToNextMajor(from: \"${old_version}\")/.upToNextMajor(from: \"${new_version}\")/g" \
    -e "s/exact: \"${old_version}\"/exact: \"${new_version}\"/g" \
    -e "s/from \`${old_version}\`/from \`${new_version}\`/g" \
    README.md > README.md.tmp
  mv README.md.tmp README.md
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --skip-tests) SKIP_TESTS=1 ;;
    --remote)
      shift
      REMOTE="${1:?--remote requires a value}"
      ;;
    -h|--help) usage 0 ;;
    -*)
      log "error: unknown option: $1" >&2
      usage 1
      ;;
    *)
      if [ -n "$VERSION" ]; then
        log "error: unexpected argument: $1" >&2
        usage 1
      fi
      VERSION="$1"
      ;;
  esac
  shift
done

[ -n "$VERSION" ] || usage 1
validate_semver "$VERSION"

if git rev-parse "$VERSION" >/dev/null 2>&1; then
  log "error: git tag $VERSION already exists." >&2
  exit 1
fi

OLD_VERSION="$(latest_released_version)"
if [ -z "$OLD_VERSION" ]; then
  log "error: no existing semver tags found; cannot infer README pin version." >&2
  exit 1
fi

if [ "$OLD_VERSION" = "$VERSION" ]; then
  log "error: latest tag is already $VERSION; choose a higher version." >&2
  exit 1
fi

log "Releasing MotiSig iOS SDK $OLD_VERSION -> $VERSION"
roll_changelog "$VERSION"
bump_readme_pins "$OLD_VERSION" "$VERSION"

if [ "$SKIP_TESTS" -eq 0 ]; then
  run ./scripts/run-unit-tests.sh
else
  log "Skipping unit tests (--skip-tests)."
fi

run git add CHANGELOG.md README.md
run git commit -m "Prepare release $VERSION"
run git tag -a "$VERSION" -m "Release $VERSION"

CURRENT_BRANCH="$(git branch --show-current)"
run git push "$REMOTE" "$CURRENT_BRANCH"
run git push "$REMOTE" "$VERSION"

log ""
log "Released MotiSig iOS SDK $VERSION (Git tag pushed for SPM)."
log "Swift Package Index re-indexes automatically if the repo is registered:"
log "https://swiftpackageindex.com/add-a-package"
if [ "$DRY_RUN" -eq 1 ]; then
  log ""
  log "Dry run complete. No files, commits, tags, or pushes were changed."
fi
