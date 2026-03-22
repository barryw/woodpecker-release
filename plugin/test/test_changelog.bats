#!/usr/bin/env bats

setup() {
  . "$BATS_TEST_DIRNAME/../lib/changelog.sh"
  export TMPDIR="${BATS_TMPDIR}"
}

@test "changelog_generate fails without arguments" {
  run changelog_generate
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires"* ]]
}

@test "changelog_generate falls back on cog failure" {
  # Mock cog to fail
  cog() { return 1; }
  export -f cog

  local outfile="${BATS_TMPDIR}/notes.md"
  run changelog_generate "v1.0.0" "$outfile"
  [ "$status" -eq 0 ]
  [ -f "$outfile" ]
  [[ "$(cat "$outfile")" == "Release v1.0.0" ]]
}
