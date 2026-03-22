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

  echo "Running cog bump (mode: ${bump_mode})..." >&2

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
  output=$(cog bump $bump_args 2>&1) || true

  echo "$output" >&2

  # Check if no bump was needed (cog may return 0 or non-zero for this)
  if echo "$output" | grep -qi "no conventional commits\|no version bump\|nothing to bump\|required a bump"; then
    echo "No version bump needed" >&2
    return 1
  fi

  # Check for actual errors
  if echo "$output" | grep -qi "^Error:"; then
    echo "ERROR: cog bump failed" >&2
    return 1
  fi

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
