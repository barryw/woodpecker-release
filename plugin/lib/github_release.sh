#!/bin/bash
# github_release.sh — Create GitHub Releases with optional asset uploads

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

  # Detect pre-release versions
  if [[ "$version" =~ -(alpha|beta|rc|dev) ]]; then
    prerelease_flag="--prerelease"
    echo "Detected pre-release version: ${version}"
  fi

  echo "Creating GitHub Release ${version} for ${repo}..."

  # Build args array
  local args=("$version" --repo "$repo" --title "$version")

  if [ -n "$changelog_file" ] && [ -f "$changelog_file" ]; then
    args+=(--notes-file "$changelog_file")
  else
    args+=(--notes "Release ${version}")
  fi

  if [ -n "$prerelease_flag" ]; then
    args+=(--prerelease)
  fi

  # Create the release (ignore if already exists)
  gh release create "${args[@]}" 2>/dev/null \
    || echo "Release ${version} already exists, continuing with asset upload"
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
