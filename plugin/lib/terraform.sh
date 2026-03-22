#!/bin/bash
# terraform.sh — Terraform Registry manifest generation

set -e

# Generate the Terraform Registry manifest JSON.
# This file is required for the Registry to discover provider archives.
terraform_generate_manifest() {
  local version="$1"
  local binary_name="${PLUGIN_GO_BINARY_NAME:-$(basename "$CI_REPO")}"
  local clean_version="${version#v}"
  local manifest_file="dist/${binary_name}_${clean_version}_manifest.json"

  if [ -z "$version" ]; then
    echo "ERROR: terraform_generate_manifest requires a version" >&2
    return 1
  fi

  echo "Generating Terraform Registry manifest..."

  cat > "$manifest_file" <<EOF
{
  "version": 1,
  "metadata": {
    "protocol_versions": ["6.0"]
  }
}
EOF

  echo "Manifest: ${manifest_file}"
}
