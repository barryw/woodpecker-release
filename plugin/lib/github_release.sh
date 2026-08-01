#!/bin/bash
# github_release.sh — Create GitHub Releases with optional asset uploads
#
# POSIX sh only below `set -e`: this file is sourced both by the plugin's
# bash entrypoint (plugin/entrypoint.sh, ~20 repos) and directly by
# `commands:` steps on the Alpine plugin image, which Woodpecker runs under
# busybox ash (/bin/sh -e). No bash arrays, no [[ ]], no =~. `local` is
# fine — both bash and ash support it, and keeping the bash shebang here
# (shellcheck reads dialect from it) keeps `local` from tripping SC3043;
# the file is always sourced, never executed, so the shebang itself is
# inert. See plugin/test/test_github_release.bats for the sh -n guard.

set -e

# Create a GitHub Release for the given version.
# Uploads assets matching the glob pattern if provided.
github_release_create() {
  local version="$1"
  local changelog_file="$2"
  local repo="${CI_REPO:?CI_REPO not set}"
  local prerelease_flag=""

  if [ -z "$version" ]; then
    echo "ERROR: github_release_create requires a version" >&2
    return 1
  fi

  # Detect pre-release versions (POSIX case, no bash regex)
  case "$version" in
    *-alpha*|*-beta*|*-rc*|*-dev*)
      prerelease_flag="--prerelease"
      echo "Detected pre-release version: ${version}"
      ;;
  esac

  echo "Creating GitHub Release ${version} for ${repo}..."

  # Build the gh args as positional parameters (no bash arrays)
  set -- "$version" --repo "$repo" --title "$version"

  if [ -n "$changelog_file" ] && [ -f "$changelog_file" ]; then
    set -- "$@" --notes-file "$changelog_file"
  else
    set -- "$@" --notes "Release ${version}"
  fi

  if [ -n "$prerelease_flag" ]; then
    set -- "$@" --prerelease
  fi

  if [ "${PLUGIN_DRAFT:-false}" = "true" ]; then
    set -- "$@" --draft
    echo "Creating as draft; publish with github_release_publish after artifacts land."
  fi

  # Create the release (ignore if already exists)
  if ! gh release create "$@" 2>&1; then
    echo "Note: gh release create returned non-zero (release may already exist)"
  fi
}

# Upload assets to an existing GitHub Release.
github_release_upload() {
  local version="$1"
  shift
  local repo="${CI_REPO:?CI_REPO not set}"

  if [ -z "$version" ] || [ $# -eq 0 ]; then
    echo "ERROR: github_release_upload requires <version> <file>..." >&2
    return 1
  fi

  echo "Uploading $# asset(s) to release ${version}..."
  gh release upload "$version" "$@" --repo "$repo" --clobber
  echo "Assets uploaded successfully"
}

# Flip a draft Release public. Called after artifacts have been published, so a
# failed artifact step never leaves a public Release claiming a version that
# does not exist.
github_release_publish() {
  local version="$1"
  local repo="${CI_REPO:?CI_REPO not set}"

  if [ -z "$version" ]; then
    echo "ERROR: github_release_publish requires a version" >&2
    return 1
  fi

  echo "Publishing draft Release ${version}..."
  gh release edit "$version" --draft=false --repo "$repo"
}
