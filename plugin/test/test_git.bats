#!/usr/bin/env bats

setup() {
  . "$BATS_TEST_DIRNAME/../lib/git.sh"
  export CI_WORKSPACE="/tmp/test-workspace"
  export CI_REPO="barryw/test-repo"
}

@test "git_push_tag fails without tag name" {
  run git_push_tag ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires a tag name"* ]]
}

@test "git_push_tag uses explicit remote" {
  # Mock git to capture args
  git() {
    echo "git $*"
  }
  export -f git
  export PLUGIN_GIT_REMOTE="origin"

  run git_push_tag "v1.0.0"
  [ "$status" -eq 0 ]
  [[ "$output" == *"git push origin v1.0.0"* ]]
}

@test "git_push_commit uses explicit remote and branch" {
  git() {
    echo "git $*"
  }
  export -f git
  export PLUGIN_GIT_BRANCH="main"
  export PLUGIN_GIT_REMOTE="origin"

  run git_push_commit
  [ "$status" -eq 0 ]
  [[ "$output" == *"git push origin main"* ]]
}

@test "git_push_commit defaults to origin/main" {
  git() {
    echo "git $*"
  }
  export -f git
  unset PLUGIN_GIT_BRANCH
  unset PLUGIN_GIT_REMOTE

  run git_push_commit
  [ "$status" -eq 0 ]
  [[ "$output" == *"git push origin main"* ]]
}
