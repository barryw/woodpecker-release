#!/bin/bash
# cog.sh — Cocogitto version bump operations
# Handles: --skip-ci enforcement, version extraction, bump override

set -e

# Run cog bump and capture the new version.
# Returns the new version tag (e.g., "v1.2.3") on stdout.
# Exits 0 if a bump was performed, 1 if no bump was needed.
cog_bump() {
  local bump_mode="${PLUGIN_BUMP_MODE:-auto}"
  local skip_ci_marker="[skip ci]"

  echo "Running cog bump (mode: ${bump_mode})..."

  local bump_args="--skip-ci"
  case "$bump_mode" in
    auto)  bump_args="--auto $bump_args" ;;
    major) bump_args="--major $bump_args" ;;
    minor) bump_args="--minor $bump_args" ;;
    patch) bump_args="--patch $bump_args" ;;
    *)
      echo "ERROR: Unknown bump mode: ${bump_mode}. Use: auto, major, minor, patch" >&2
      return 1
      ;;
  esac

  if [ "${PLUGIN_SKIP_UNTRACKED:-true}" = "true" ]; then
    bump_args="$bump_args --skip-untracked"
  fi

  local output
  # shellcheck disable=SC2086
  if ! output=$(cog bump $bump_args 2>&1); then
    # Check if it's a "no bump needed" situation
    if echo "$output" | grep -qi "no conventional commits\|No conventional commits\|no version bump"; then
      echo "No version bump needed"
      return 1
    fi
    echo "ERROR: cog bump failed:" >&2
    echo "$output" >&2
    return 1
  fi

  echo "$output" >&2

  # Extract the new version from the latest tag
  local new_version
  new_version=$(git describe --tags --abbrev=0 2>/dev/null)

  if [ -z "$new_version" ]; then
    echo "ERROR: cog bump succeeded but no tag found" >&2
    return 1
  fi

  # Verify the bump commit contains [skip ci]
  local commit_msg
  commit_msg=$(git log -1 --format="%s %b")
  if ! echo "$commit_msg" | grep -qF "$skip_ci_marker"; then
    echo "ERROR: Bump commit does not contain '${skip_ci_marker}'. Check cog.toml skip_ci setting." >&2
    echo "Commit message was: ${commit_msg}" >&2
    return 1
  fi

  echo "$new_version"
}

# Get the current version from the latest tag without bumping.
cog_current_version() {
  git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0"
}
