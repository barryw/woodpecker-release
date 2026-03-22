#!/usr/bin/env bats

setup() {
  . "$BATS_TEST_DIRNAME/../lib/cog.sh"
}

@test "cog_bump rejects unknown bump mode" {
  export PLUGIN_BUMP_MODE="invalid"

  # Mock cog
  cog() { echo "mock"; }
  export -f cog

  run cog_bump
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown bump mode"* ]]
}

@test "cog_current_version returns v0.0.0 when no tags" {
  # Mock git to return nothing
  git() { return 1; }
  export -f git

  run cog_current_version
  [ "$status" -eq 0 ]
  [ "$output" = "v0.0.0" ]
}
