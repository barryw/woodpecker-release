#!/bin/bash
# git.sh — Git configuration and push operations for Woodpecker CI
# Handles all known footguns: explicit remote/branch, tag-by-name push, credential setup

set -e

# Configure git credentials for pushing back to the repo.
# Uses Woodpecker's CI_* env vars or plugin settings.
git_configure() {
  local git_name="${PLUGIN_GIT_NAME:-Woodpecker CI}"
  local git_email="${PLUGIN_GIT_EMAIL:-ci@woodpecker.local}"

  git config --global user.name "$git_name"
  git config --global user.email "$git_email"
  git config --global --add safe.directory "$CI_WORKSPACE"

  # Set up authenticated remote using GitHub token
  if [ -n "$PLUGIN_GITHUB_TOKEN" ]; then
    local repo="${CI_REPO:?CI_REPO not set}"
    git remote set-url origin "https://x-access-token:${PLUGIN_GITHUB_TOKEN}@github.com/${repo}.git"
  fi
}

# Push the bump commit to the remote branch.
# Always explicit: origin + branch name. Never bare `git push`.
git_push_commit() {
  local branch="${PLUGIN_GIT_BRANCH:-main}"
  local remote="${PLUGIN_GIT_REMOTE:-origin}"

  echo "Pushing commit to ${remote}/${branch}..."
  git push "$remote" "$branch"
}

# Push a specific tag by name to the remote.
# NEVER use --follow-tags (only works with annotated tags; cog creates lightweight ones).
git_push_tag() {
  local tag="$1"
  local remote="${PLUGIN_GIT_REMOTE:-origin}"

  if [ -z "$tag" ]; then
    echo "ERROR: git_push_tag requires a tag name" >&2
    return 1
  fi

  echo "Pushing tag ${tag} to ${remote}..."
  git push "$remote" "$tag"
}

# Ensure the repo has full history and tags (Woodpecker shallow clones by default).
git_ensure_full_history() {
  git fetch --unshallow origin 2>/dev/null || true
  git fetch --tags origin 2>/dev/null || true
}
