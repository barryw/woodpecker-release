#!/usr/bin/env bash
#
# mint-installation-token.sh — exchange the WHI GitHub App's private key for a
# short-lived, down-scoped installation access token.
#
# WHY (WAL-68): replaces the shared admin PAT. Instead of every CI step / service
# holding one repo-wide `Administration` PAT with no attribution and no rotation,
# each consumer mints a token scoped to exactly the repos + permissions it needs.
# Tokens are minted on demand and expire in ~1h. This does NOT add folder-level
# scoping (GitHub permissions are repo-wide) — path separation stays the
# CODEOWNERS merge-gate (WAL-65). This is permission hygiene + token lifecycle.
#
# DEPENDENCIES: bash, openssl, curl, jq. On alpine CI images:
#   apk add --no-cache bash openssl curl jq
#
# REQUIRED ENV (inject as secrets — never commit):
#   GH_APP_ID               numeric App ID (App settings → About → "App ID")
#   GH_APP_INSTALLATION_ID  per-install id (Installed GitHub Apps → Configure URL)
#   GH_APP_PRIVATE_KEY      full PEM contents of the App private key (.pem).
#                           A single-line secret with literal "\n" is accepted.
#
# USAGE:
#   mint-installation-token.sh --profile <name>
#   mint-installation-token.sh --repos repo1,repo2 --perm contents=read [--perm pull_requests=write]
#
# OPTIONS:
#   --profile NAME    use a named consumer profile (see CONSUMER PROFILES below)
#   --repos LIST      comma-separated repo names (NOT owner/repo — install owner is implied)
#   --perm K=V        a permission grant, e.g. contents=read | administration=write
#                     (repeatable; may also be comma-joined: --perm contents=read,metadata=read)
#   --owner OWNER     repo owner for the audit log note (default: barryw)
#   --export          print `export GITHUB_TOKEN=<token>` instead of the bare token
#   --json            print the raw GitHub response (token + expires_at + permissions)
#   -h | --help       this help
#
# OUTPUT: the installation token on stdout (or an `export ...` line with --export).
# The token is short-lived; do not log it. Capture into an env var:
#   GITHUB_TOKEN="$(mint-installation-token.sh --profile config-service)"
#
# CONSUMER PROFILES: defined in profiles.env next to this script. Keep each
# profile to the minimum permission set its consumer actually needs. See
# ../docs/2026-06-30-github-app-token-profiles.md for the rationale per profile.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILES_FILE="${PROFILES_FILE:-$SCRIPT_DIR/profiles.env}"
API="${GITHUB_API_URL:-https://api.github.com}"
OWNER="barryw"
PROFILE=""
REPOS=""
declare -a PERMS=()
OUT_MODE="token"

die() { echo "mint-installation-token: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2 ;;
    --repos)   REPOS="$2"; shift 2 ;;
    --perm)    PERMS+=("$2"); shift 2 ;;
    --owner)   OWNER="$2"; shift 2 ;;
    --export)  OUT_MODE="export"; shift ;;
    --json)    OUT_MODE="json"; shift ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

# --- resolve a named profile into REPOS + PERMS -----------------------------
if [ -n "$PROFILE" ]; then
  [ -f "$PROFILES_FILE" ] || die "profiles file not found: $PROFILES_FILE"
  # profiles.env lines: PROFILE_<name>_REPOS="a,b"  /  PROFILE_<name>_PERMS="contents=read,metadata=read"
  # shellcheck disable=SC1090
  . "$PROFILES_FILE"
  key="$(echo "$PROFILE" | tr '[:lower:]-' '[:upper:]_')"
  r_var="PROFILE_${key}_REPOS"; p_var="PROFILE_${key}_PERMS"
  REPOS="${!r_var:-}"
  [ -n "$REPOS" ] || die "unknown profile '$PROFILE' (no $r_var in $PROFILES_FILE)"
  IFS=',' read -r -a PERMS <<< "${!p_var:-}"
fi

[ -n "$REPOS" ] || die "no repos: pass --repos or --profile"
[ "${#PERMS[@]}" -gt 0 ] || die "no permissions: pass --perm or --profile"

: "${GH_APP_ID:?GH_APP_ID not set}"
: "${GH_APP_INSTALLATION_ID:?GH_APP_INSTALLATION_ID not set}"
: "${GH_APP_PRIVATE_KEY:?GH_APP_PRIVATE_KEY not set}"

# --- write the private key to a 0600 temp file (handles single-line "\n" PEMs)
KEYFILE="$(mktemp)"; chmod 600 "$KEYFILE"
cleanup() { rm -f "$KEYFILE"; }
trap cleanup EXIT
if printf '%s' "$GH_APP_PRIVATE_KEY" | grep -q 'BEGIN.*PRIVATE KEY' && printf '%s' "$GH_APP_PRIVATE_KEY" | grep -q $'\n'; then
  printf '%s\n' "$GH_APP_PRIVATE_KEY" > "$KEYFILE"
else
  # secret stored single-line with literal backslash-n: restore real newlines
  printf '%b\n' "$GH_APP_PRIVATE_KEY" > "$KEYFILE"
fi

# --- build a short-lived (9 min) RS256 App JWT ------------------------------
b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
now="$(date +%s)"
iat="$((now - 60))"      # backdate 60s for clock skew (GitHub allows it)
exp="$((now + 540))"     # max 10 min; use 9
header='{"alg":"RS256","typ":"JWT"}'
payload="$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' "$iat" "$exp" "$GH_APP_ID")"
unsigned="$(printf '%s' "$header" | b64url).$(printf '%s' "$payload" | b64url)"
sig="$(printf '%s' "$unsigned" | openssl dgst -sha256 -sign "$KEYFILE" -binary | b64url)"
jwt="$unsigned.$sig"

# --- assemble the down-scoped request body ----------------------------------
repos_json="$(printf '%s' "$REPOS" | tr ',' '\n' | sed '/^$/d' | jq -R . | jq -s .)"
perms_json='{}'
for kv in "${PERMS[@]}"; do
  [ -n "$kv" ] || continue
  k="${kv%%=*}"; v="${kv#*=}"
  [ "$k" != "$kv" ] || die "bad --perm '$kv' (want key=level)"
  perms_json="$(printf '%s' "$perms_json" | jq --arg k "$k" --arg v "$v" '. + {($k):$v}')"
done
body="$(jq -n --argjson repos "$repos_json" --argjson perms "$perms_json" \
  '{repositories:$repos, permissions:$perms}')"

# --- mint the installation token --------------------------------------------
resp="$(curl -fsS -X POST \
  -H "Authorization: Bearer $jwt" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "$API/app/installations/$GH_APP_INSTALLATION_ID/access_tokens" \
  -d "$body")" || die "token request failed (check App ID / Installation ID / key / that repos are in the install)"

token="$(printf '%s' "$resp" | jq -r '.token // empty')"
[ -n "$token" ] || die "no token in response: $(printf '%s' "$resp" | jq -c '{message,documentation_url}')"

case "$OUT_MODE" in
  token)  printf '%s\n' "$token" ;;
  export) printf 'export GITHUB_TOKEN=%s\n' "$token" ;;
  json)   printf '%s\n' "$resp" | jq '{expires_at, permissions, repository_selection}' ;;
esac
