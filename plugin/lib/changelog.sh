#!/bin/bash
# changelog.sh — Generate release notes from conventional commits via cog

set -e

# Generate changelog for a specific version tag.
# Writes markdown to the specified file path.
# Falls back to a simple "Release <version>" message on failure.
changelog_generate() {
  local version="$1"
  local output_file="$2"

  if [ -z "$version" ] || [ -z "$output_file" ]; then
    echo "ERROR: changelog_generate requires <version> <output_file>" >&2
    return 1
  fi

  echo "Generating changelog for ${version}..."

  if cog changelog --at "$version" > "$output_file" 2>/dev/null; then
    # Check if the changelog has actual content
    if [ -s "$output_file" ]; then
      echo "Changelog generated ($(wc -l < "$output_file") lines)"
      return 0
    fi
  fi

  # Fallback: simple release message
  echo "Release ${version}" > "$output_file"
  echo "Changelog: using fallback message"
}
