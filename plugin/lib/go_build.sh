#!/bin/bash
# go_build.sh — Cross-compile Go binaries for multiple platforms

set -e

# Cross-compile Go binaries for all configured platforms.
# Creates zipped binaries in the dist/ directory.
# Supports Terraform provider naming convention.
go_build_all() {
  local version="$1"
  local platforms="${PLUGIN_GO_PLATFORMS:-linux/amd64,linux/arm64,darwin/amd64,darwin/arm64,windows/amd64}"
  local binary_name="${PLUGIN_GO_BINARY_NAME:-$(basename "$CI_REPO")}"
  local ldflags="${PLUGIN_GO_LDFLAGS:--s -w -X main.version=${version#v}}"
  local dist_dir="dist"

  if [ -z "$version" ]; then
    echo "ERROR: go_build_all requires a version" >&2
    return 1
  fi

  local clean_version="${version#v}"
  mkdir -p "$dist_dir"

  echo "Building ${binary_name} ${clean_version} for: ${platforms}"

  local old_ifs="$IFS"
  IFS=","
  for platform in $platforms; do
    local os="${platform%/*}"
    local arch="${platform#*/}"
    local ext=""
    [ "$os" = "windows" ] && ext=".exe"

    local output_name="${binary_name}_${clean_version}_${os}_${arch}"
    local binary_path="${dist_dir}/${output_name}${ext}"

    echo "  Building ${os}/${arch}..."
    CGO_ENABLED=0 GOOS="$os" GOARCH="$arch" \
      go build -trimpath -ldflags "$ldflags" -o "$binary_path" .

    # Zip and remove binary
    (cd "$dist_dir" && zip "${output_name}.zip" "$(basename "$binary_path")" && rm "$(basename "$binary_path")")
  done
  IFS="$old_ifs"

  echo "Built $(ls "$dist_dir"/*.zip 2>/dev/null | wc -l) archives in ${dist_dir}/"
}

# Generate SHA256 checksums for all files in dist/.
go_build_checksums() {
  local version="$1"
  local binary_name="${PLUGIN_GO_BINARY_NAME:-$(basename "$CI_REPO")}"
  local clean_version="${version#v}"
  local checksums_file="dist/${binary_name}_${clean_version}_SHA256SUMS"

  echo "Generating checksums..." >&2
  (cd dist && sha256sum *.zip *.json 2>/dev/null > "$(basename "$checksums_file")")
  echo "Checksums written to ${checksums_file}" >&2
  echo "$checksums_file"
}
