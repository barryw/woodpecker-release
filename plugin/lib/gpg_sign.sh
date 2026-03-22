#!/bin/bash
# gpg_sign.sh — GPG signing for release artifacts

set -e

# Import a GPG private key from the PLUGIN_GPG_KEY environment variable.
# The key is expected to be ASCII-armored (not base64).
gpg_import_key() {
  if [ -z "$PLUGIN_GPG_KEY" ]; then
    echo "ERROR: PLUGIN_GPG_KEY is not set" >&2
    return 1
  fi

  echo "Importing GPG key..."
  echo "$PLUGIN_GPG_KEY" | gpg --batch --import 2>/dev/null
  echo "GPG key imported"
}

# Sign a file with GPG detached signature.
gpg_sign_file() {
  local file="$1"
  local fingerprint="${PLUGIN_GPG_FINGERPRINT}"

  if [ -z "$file" ]; then
    echo "ERROR: gpg_sign_file requires a file path" >&2
    return 1
  fi

  local sign_args="--batch --detach-sign"
  if [ -n "$fingerprint" ]; then
    sign_args="$sign_args --local-user $fingerprint"
  fi

  echo "Signing ${file}..."
  # shellcheck disable=SC2086
  gpg $sign_args "$file"
  echo "Signature: ${file}.sig"
}
