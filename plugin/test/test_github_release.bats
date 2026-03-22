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
