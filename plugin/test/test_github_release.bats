#!/usr/bin/env bats

setup() {
  . "$BATS_TEST_DIRNAME/../lib/github_release.sh"
  export CI_REPO="barryw/test-repo"
}

@test "github_release_create fails without version" {
  run github_release_create
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires a version"* ]]
}

@test "github_release_upload fails without version" {
  run github_release_upload
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires"* ]]
}

@test "github_release_create detects pre-release" {
  # Mock gh to capture args
  gh() {
    echo "gh $*"
  }
  export -f gh

  run github_release_create "v1.0.0-rc.1" "/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pre-release"* ]]
}

@test "github_release_create passes --draft when PLUGIN_DRAFT is true" {
  export CI_REPO="barryw/testrepo"
  export PLUGIN_DRAFT="true"
  gh() { echo "$@" >> "$BATS_TEST_TMPDIR/gh-args"; }
  export -f gh

  source "$BATS_TEST_DIRNAME/../lib/github_release.sh"
  github_release_create "v1.2.3" ""

  run cat "$BATS_TEST_TMPDIR/gh-args"
  [[ "$output" == *"--draft"* ]]
}

@test "github_release_create omits --draft by default" {
  export CI_REPO="barryw/testrepo"
  unset PLUGIN_DRAFT
  gh() { echo "$@" >> "$BATS_TEST_TMPDIR/gh-args"; }
  export -f gh

  source "$BATS_TEST_DIRNAME/../lib/github_release.sh"
  github_release_create "v1.2.3" ""

  run cat "$BATS_TEST_TMPDIR/gh-args"
  [[ "$output" != *"--draft"* ]]
}

@test "github_release_publish flips a draft public" {
  export CI_REPO="barryw/testrepo"
  gh() { echo "$@" >> "$BATS_TEST_TMPDIR/gh-args"; }
  export -f gh

  source "$BATS_TEST_DIRNAME/../lib/github_release.sh"
  github_release_publish "v1.2.3"

  run cat "$BATS_TEST_TMPDIR/gh-args"
  [[ "$output" == *"release edit v1.2.3"* ]]
  [[ "$output" == *"--draft=false"* ]]
}

@test "github_release.sh parses under /bin/sh (POSIX, no bashisms)" {
  # This file is sourced by Woodpecker `commands:` steps on the Alpine
  # plugin image, which run under busybox ash, not bash. A bashism here
  # (arrays, [[ ]], =~) is a parse-time error under ash that silently
  # skips defining every function in this file. The CI test image
  # (bats/bats, Alpine-based) has busybox ash as its own /bin/sh, so this
  # runs the real check with no docker-in-docker needed.
  run /bin/sh -n "$BATS_TEST_DIRNAME/../lib/github_release.sh"
  [ "$status" -eq 0 ]
}
