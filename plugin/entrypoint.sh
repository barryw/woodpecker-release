#!/bin/bash
# entrypoint.sh — Woodpecker CI release plugin
#
# Modes:
#   bump         — Version bump only (cog bump + push commit + push tag)
#   release-tag  — Bump + GitHub Release with changelog (no artifacts)
#   release-go   — Bump + Go cross-compile + optional GPG sign + GitHub Release
#
# All modes handle: --skip-ci, explicit push, tag-by-name push.
# See plugin/lib/ for individual components.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source all library scripts
. "$SCRIPT_DIR/lib/git.sh"
. "$SCRIPT_DIR/lib/cog.sh"
. "$SCRIPT_DIR/lib/changelog.sh"
. "$SCRIPT_DIR/lib/github_release.sh"
. "$SCRIPT_DIR/lib/go_build.sh"
. "$SCRIPT_DIR/lib/gpg_sign.sh"
. "$SCRIPT_DIR/lib/terraform.sh"

MODE="${PLUGIN_MODE:-bump}"
CHANGELOG_FILE="/tmp/release-notes.md"

echo "============================================"
echo "  Woodpecker Release Plugin"
echo "  Mode:    ${MODE}"
echo "  Repo:    ${CI_REPO:-unknown}"
echo "  Branch:  ${PLUGIN_GIT_BRANCH:-main}"
echo "============================================"

# --- Step 1: Git setup (all modes) ---
# Export GH_TOKEN for the gh CLI (it reads this env var for auth)
export GH_TOKEN="${PLUGIN_GITHUB_TOKEN:-}"

git_configure
git_ensure_full_history

# --- Step 2: Version bump (all modes) ---
VERSION_FILE="${PLUGIN_VERSION_FILE:-/woodpecker/version.txt}"

bump_exit=0
NEW_VERSION=$(cog_bump) || bump_exit=$?

if [ "$bump_exit" -eq 1 ]; then
  # Return code 1 = no bump needed (benign)
  echo "No version bump needed. Exiting cleanly."
  echo "NONE" > "$VERSION_FILE"
  exit 0
elif [ "$bump_exit" -ne 0 ]; then
  # Return code 2+ = actual error
  echo "ERROR: Version bump failed (exit code ${bump_exit}). Failing pipeline." >&2
  exit 1
fi

echo "New version: ${NEW_VERSION}"

# Write version to shared file for downstream steps
echo "$NEW_VERSION" > "$VERSION_FILE"
echo "Version written to ${VERSION_FILE}"

# --- Step 3: Push commit and tag (all modes) ---
git_push_commit
git_push_tag "$NEW_VERSION"

# Early exit for bump-only mode
if [ "$MODE" = "bump" ]; then
  echo "Bump complete: ${NEW_VERSION}"
  exit 0
fi

# --- Step 4: Generate changelog (release modes) ---
changelog_generate "$NEW_VERSION" "$CHANGELOG_FILE"

# --- Step 5: Build artifacts (mode-specific) ---
case "$MODE" in
  release-go)
    # Cross-compile Go binaries
    go_build_all "$NEW_VERSION"

    # Terraform manifest (if enabled)
    if [ "${PLUGIN_TERRAFORM_MANIFEST:-false}" = "true" ]; then
      terraform_generate_manifest "$NEW_VERSION"
    fi

    # Copy any extra manifest files from the repo
    if [ -f "terraform-registry-manifest.json" ]; then
      _binary_name="${PLUGIN_GO_BINARY_NAME:-$(basename "$CI_REPO")}"
      _clean_version="${NEW_VERSION#v}"
      cp terraform-registry-manifest.json "dist/${_binary_name}_${_clean_version}_manifest.json"
    fi

    # Generate checksums
    CHECKSUMS_FILE=$(go_build_checksums "$NEW_VERSION")

    # GPG sign (if enabled)
    if [ "${PLUGIN_GPG_SIGN:-false}" = "true" ]; then
      gpg_import_key
      gpg_sign_file "$CHECKSUMS_FILE"
    fi
    ;;
  release-tag)
    # No artifacts to build
    ;;
  *)
    echo "ERROR: Unknown mode: ${MODE}" >&2
    exit 1
    ;;
esac

# --- Step 6: Create GitHub Release ---
github_release_create "$NEW_VERSION" "$CHANGELOG_FILE"

# Upload artifacts if any exist
if [ -d "dist" ] && [ "$(find dist -maxdepth 1 -type f 2>/dev/null | wc -l)" -gt 0 ]; then
  github_release_upload "$NEW_VERSION" dist/*
fi

echo "============================================"
echo "  Release ${NEW_VERSION} complete!"
echo "============================================"
