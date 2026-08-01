# woodpecker-release

Reusable Woodpecker CI release infrastructure. Semantic versioning with [Cocogitto](https://docs.cocogitto.io/), conventional commits, and GitHub Releases — done once, shared everywhere.

Two components:
- **Plugin** (`ghcr.io/barryw/woodpecker-release`) — Docker image that handles cog bump, tag push, changelog, GitHub Release, Go cross-compilation, GPG signing
- **Config Service** — generates full pipeline YAML from templates so repos only need a 3-line config file

## Onboarding a New Repo

### Step 1: Add `cog.toml` + commit-msg hook

The canonical, copy-in `cog.toml` for every repo lives in this repo at
[`onboarding/cog.toml`](onboarding/cog.toml). Copy it to the repo root and set
the one repo-specific value (`[changelog].repository`):

```bash
cp /path/to/woodpecker-release/onboarding/cog.toml ./cog.toml
# edit cog.toml: set repository = "<this-repo-name>"
cog install-hook --all   # installs the commit-msg `cog verify` hook
```

`cog install-hook --all` writes the commit-msg hook from the `[git_hooks]`
block so only conventional commits can land. A standalone copy of that hook is
also provided at [`onboarding/commit-msg`](onboarding/commit-msg) for repos that
install hooks by hand.

For reference, the canonical `cog.toml`:

```toml
from_latest_tag = true
ignore_merge_commits = true
branch_whitelist = ["main"]
tag_prefix = "v"
skip_ci = "[skip ci]"
skip_untracked = false

pre_bump_hooks = []
post_bump_hooks = []

[changelog]
path = "CHANGELOG.md"
template = "remote"
remote = "github.com"
owner = "barryw"
repository = "CHANGEME"   # set to this repo's name

[commit_types]
feat = { changelog_title = "Features" }
fix = { changelog_title = "Bug Fixes" }
docs = { changelog_title = "Documentation" }
refactor = { changelog_title = "Refactoring" }
perf = { changelog_title = "Performance" }
test = { changelog_title = "Tests" }
build = { changelog_title = "Build" }
ci = { changelog_title = "CI/CD" }
style = { changelog_title = "Style" }
chore = { changelog_title = "Miscellaneous" }
revert = { changelog_title = "Reverts" }

[git_hooks.commit-msg]
script = """#!/bin/sh
set -e
cog verify --file $1
"""
```

### Step 2: Handle existing version tags

**If the repo has NO existing tags:** Skip this step. Cog will start at `v0.1.0`.

**If the repo has existing tags (e.g., from a previous CI system):** You MUST tag the current HEAD at the correct version before the first pipeline run. Otherwise cog will ignore the old tags and reset to `v0.1.0`.

```bash
# Check existing tags
git tag -l

# Tag current HEAD at the next version
git tag v2.3.6   # whatever comes after the latest existing version
git push origin v2.3.6
```

### Step 3: Add the template reference

Create `.woodpecker/woodpecker-template.yaml` (NOT `.woodpecker.yml`):

**For a Go library** (lint + test + release):
```yaml
template: release-go-library
data:
  go_version: "1.25"
```

**For a Go binary/Terraform provider** (lint + test + cross-compile + GPG + release):
```yaml
template: release-go-binary
data:
  go_version: "1.25"
  go_platforms: "linux/amd64,linux/arm64,darwin/amd64,darwin/arm64,windows/amd64"
  go_binary_name: your-binary-name
  gpg_sign: true
  terraform_manifest: true
  pihole_test: false
```

**For a Docker project** (lint + test + Docker build + release + optional k8s deploy):
```yaml
template: release-docker
data:
  test_image: "python:3.12-slim"
  image_name: your-image-name
  setup_commands:
    - "pip install uv"
    - "uv sync --frozen"
  lint_commands:
    - "uv run ruff check src/"
  test_commands:
    - "uv run pytest"
  k8s_deploy: true
  k8s_namespace: default
  k8s_deployment: your-deployment
  k8s_container: your-container
```

**For a .NET library** (build + test + optional conformance suite + release + NuGet publish):
```yaml
template: release-dotnet-library
data:
  sdk_image: "mcr.microsoft.com/dotnet/sdk:10.0"
  test_project: "tests/MyLib.Tests"
  test_filter: "Category!=Performance"
  pack_project: "src/MyLib"
  nuget_publish: true
  # optional:
  # setup_commands: ["apt-get update && apt-get install -y some-tool"]
  # conformance_project: "tests/MyLib.Conformance"
  # conformance_setup: ["tests/MyLib.Conformance/build.sh"]
```
> Requires the `nuget_api_key` secret when `nuget_publish: true`. The Release is
> created as a **draft** and flipped public only after the package is on
> nuget.org — nuget.org versions can be unlisted but never deleted, so a public
> Release must never claim a version that failed to publish.
>
> The repo's `cog.toml` needs `pre_bump_hooks` that stamp the version into its
> project files; see the .NET example in `onboarding/cog.toml`.

**For a Terraform module** (validate + lint + security scan + test + release):
```yaml
template: release-terraform
data:
  terraform_version: "1.14"
  python_version: "3.12"
  docs_check: true
```

**For a macOS / Swift app** (Xcode test + archive, Developer ID sign, notarize + staple, .dmg/.zip, release):
```yaml
template: release-macos-app
data:
  app_name: "Miggy Draw"
  scheme: "Miggy Draw"
  project: "RetroDraw.xcodeproj"
  team_id: "74E8LUBSW9"
  signing_identity: "Developer ID Application: Barry Walker (74E8LUBSW9)"
  artifact_base: "MiggyDraw"
  # optional:
  # notary_team_id: "Z4M6ST45N5"   # if the notary team differs from team_id
  # export_options: "Scripts/ExportOptions.plist"
  # dmg_script: "Scripts/create-dmg.sh"
  # keychain_setup: "Scripts/setup-keychain-ci.sh"
  # test_destination: "platform=macOS"
```
> Runs on the self-hosted `darwin/arm64` runner. The runner must have Xcode,
> `cog`, `gh`, and `jq` installed, plus the `Scripts/` helpers referenced above
> (export-options plist, create-dmg, keychain setup) in the repo.

**For a static / marketing site** (kaniko → GHCR → k8s rollout → Cloudflare purge):
```yaml
template: release-static-site
data:
  site: novuslang          # image/namespace/deployment stem
  k8s_namespace: novus     # defaults to `site`
  # optional:
  # cloudflare_zone: cloudflare_zone_id   # name of the zone-id secret
  # deploy_path: deploy/                  # kustomize dir (kubectl apply -k)
  # website_context: website             # kaniko build context
  # dockerfile: website/Dockerfile
  # image_name: novuslang-website        # defaults to <site>-website
  # deployment_name: novuslang-website   # defaults to <site>-website
  # container_name: website
```

**For a simple library** (just validate commits + release, no build):
```yaml
template: release-tag-only
```

**For a repo that needs more than one pipeline** (e.g. a macOS app **and** its
marketing site deployed from the same repo) use the `templates:` list form
instead of the single `template:` field. Each entry is rendered and the
generated configs are namespaced (`<template>-pipeline.yaml`) so they don't
collide:
```yaml
templates:
  - template: release-macos-app
    data:
      app_name: "Miggy Draw"
      scheme: "Miggy Draw"
      project: "RetroDraw.xcodeproj"
      team_id: "74E8LUBSW9"
      signing_identity: "Developer ID Application: Barry Walker (74E8LUBSW9)"
      artifact_base: "MiggyDraw"
      notary_team_id: "Z4M6ST45N5"
  - template: release-static-site
    data:
      site: miggydraw
      k8s_namespace: miggydraw
```
The single `template:` form is unchanged and still produces a `pipeline.yaml`
config. (An unknown template name in the `templates:` list is rejected rather
than silently dropped, so a typo can't quietly remove a pipeline.)

### Step 4: Remove old pipeline files

Delete any existing `.woodpecker.yml`, `.woodpecker/*.yml` files. The config service generates the pipeline from the template.

### Step 5: Add Woodpecker secrets

The repo needs these secrets in Woodpecker (Settings → Secrets):

| Secret | Required | Used for |
|---|---|---|
| `github_token` | Yes (unless `mint_token`) | Git push, GitHub Release creation |
| `gh_app_id` / `gh_app_installation_id` / `gh_app_private_key` | Only if `mint_token: true` | Mint a short-lived GitHub App installation token in place of the PAT (org-level secrets, WAL-70) |
| `nuget_api_key` | Only if `nuget_publish: true` | Publishing packages to nuget.org |
| `gpg_private_key` | Only if `gpg_sign: true` | Signing checksums |
| `gpg_fingerprint` | Only if `gpg_sign: true` | GPG key ID |
| `ci_keychain_password` | `release-macos-app` | Unlock signing keychain on the runner |
| `apple_id` / `apple_id_password` | `release-macos-app` | notarytool credentials |
| `ghcr_username` / `ghcr_token` | `release-static-site` | Push site image to GHCR |
| `cloudflare_api_token` + zone-id secret | `release-static-site` | Purge Cloudflare cache |

#### Minted App tokens (`mint_token: true`)

By default the release step authenticates with the shared `github_token` PAT.
Set `mint_token: true` in the template `data:` to instead mint a short-lived,
down-scoped **GitHub App installation token** (profile `product-ci`,
`contents=write,metadata=read`) at the start of the release step. The plugin
vendors `mint-installation-token.sh` and mints on demand — pipelines are
short-lived, so the ~1h token is a natural fit with no rotation. This needs the
org-level `gh_app_id` / `gh_app_installation_id` / `gh_app_private_key` secrets.
The PAT remains wired as a fallback until it is retired (WAL-69 step 4).

**`release-macos-app` (native darwin/arm64 runner) — WAL-73.** The local backend
runs commands straight on the host with no plugin image, so the minter cannot be
baked into a container. Instead vendor the two files into the product repo's
`Scripts/` (they are committed alongside the existing `Scripts/` helpers):

```bash
# from barryw/woodpecker-release/plugin/ (keep in sync with the canonical copy)
cp plugin/mint-installation-token.sh  <repo>/Scripts/mint-installation-token.sh
cp plugin/profiles.env                <repo>/Scripts/whi-token-profiles.env
```

Both the `version` (git push) and `release` (`gh release create`) steps then
mint a fresh token (re-minting in `release` because the build/notarize wait can
outlast the ~1h token). `openssl`, `curl`, and `jq` are already documented runner
deps. Optional overrides — point at a runner-image-vendored copy once one exists:

| Param | Default | Purpose |
|---|---|---|
| `minter_path` | `Scripts/mint-installation-token.sh` | path to the minter on the runner / in the checkout |
| `minter_profiles` | `Scripts/whi-token-profiles.env` | path to the `profiles.env` the minter reads |
| `minter_profile` | `product-ci` | named profile to mint (repos + permission scope) |

### Step 6: Commit and push

```bash
git add cog.toml .woodpecker/woodpecker-template.yaml
git rm .woodpecker.yml .woodpecker/*.yml  # remove old pipeline files
git commit -m "feat: add woodpecker-release CI pipeline"
git push
```

The pipeline will run automatically. On `feat:` or `fix:` commits to main, it will bump the version, create a GitHub Release, and build/deploy artifacts.

## How It Works

### Version Bumping

Cog reads conventional commit messages and decides the bump:
- `feat:` → minor bump (v1.2.0 → v1.3.0)
- `fix:` → patch bump (v1.2.0 → v1.2.1)
- `feat!:` or `BREAKING CHANGE` → major bump (v1.2.0 → v2.0.0)
- `docs:`, `chore:`, `refactor:`, `test:`, `ci:` → no bump

The bump commit includes `[skip ci]` to prevent infinite pipeline loops.

### Plugin Modes

| Mode | Image Tag | What it does |
|---|---|---|
| `release-tag` | `:latest` | Bump + changelog + GitHub Release (no build artifacts) |
| `release-go` | `:go` | Bump + Go cross-compile + optional GPG sign + GitHub Release with binaries |
| `bump` | `:latest` | Bump only (no release, no changelog) |

### Available Templates

| Template | Steps | Use for |
|---|---|---|
| `release-tag-only` | validate-commits → release | Simple libraries, no tests |
| `release-go-library` | validate-commits → lint → test → release | Go libraries |
| `release-go-binary` | validate-commits → lint → unit-test → [acceptance-test] → release (cross-compile + GPG) | Go binaries, Terraform providers |
| `release-docker` | validate-commits → lint → test → release → docker-build → [deploy] | Docker projects |
| `release-dotnet-library` | validate-commits → build → test → [conformance] → release (draft) → nuget-publish → finalize-release | .NET libraries published to NuGet |
| `release-terraform` | validate-commits → tf-validate → tflint → trivy → [checkov] → [pytest] → [tf-test] → [tofu-validate] → [docs-check] → release | Terraform modules |
| `release-macos-app` | validate-commits → version → test → build-sign → package → notarize-staple → release → restore-keychain (always) | Swift/macOS apps (darwin runner) |
| `build-macos-app` | build-test (every push + PR) | macOS Swift build/test GATE (darwin runner) |
| `release-static-site` | build-push → deploy → purge-cache | Marketing/product/hub sites |

### Template Parameters

**release-go-library:**
| Parameter | Default | Description |
|---|---|---|
| `go_version` | `1.25` | Go image version |

**release-go-binary:**
| Parameter | Default | Description |
|---|---|---|
| `go_version` | `1.25` | Go image version |
| `go_platforms` | `linux/amd64,...` | Cross-compilation targets |
| `go_binary_name` | `app` | Binary name prefix |
| `gpg_sign` | `false` | Enable GPG signing |
| `terraform_manifest` | `false` | Generate Terraform Registry manifest |
| `pihole_test` | `false` | Enable PiHole acceptance test service |

**release-dotnet-library:**
| Parameter | Default | Description |
|---|---|---|
| `sdk_image` | `mcr.microsoft.com/dotnet/sdk:10.0` | .NET SDK image for build/test/conformance/nuget-publish steps |
| `setup_commands` | — | Commands to run before `dotnet build`/`dotnet test` (e.g. installing extra tools) |
| `test_project` | — | Path passed to `dotnet test`; empty runs the default test discovery |
| `test_filter` | — | `--filter` expression for `dotnet test`, only added if set |
| `conformance_project` | — | If set, adds a `conformance` step running `dotnet test <project>` |
| `conformance_setup` | — | Extra setup commands run only in the `conformance` step, after `setup_commands` |
| `pack_project` | — (**required** if `nuget_publish: true`) | Project path passed to `dotnet pack`. The config service does not enforce `missingkey=error` — a typo here silently renders empty, so `dotnet pack` packs the wrong (or no) project with a green pipeline. |
| `nuget_publish` | `false` | Enables the `nuget-publish` and `finalize-release` steps and switches `PLUGIN_DRAFT` to `"true"`. A typo in this key (e.g. `nuget_pubish`) is read as unset: it silently drops both steps **and** flips `PLUGIN_DRAFT` back to `"false"`, producing a public GitHub Release for a version whose package was never published — with a green pipeline. |

**release-terraform:**
| Parameter | Default | Description |
|---|---|---|
| `terraform_version` | `1.14` | hashicorp/terraform image tag |
| `python_version` | `3.12` | Python image tag for pytest step |
| `python_test_deps` | `["pytest", "boto3", "botocore"]` | pip packages for tests |
| `python_test_dir` | `tests/python/` | Path passed to pytest |
| `tflint_version` | `v0.61.0` | tflint image tag |
| `trivy_version` | `0.69.3` | trivy image tag |
| `checkov` | `true` | Enable checkov security scan |
| `checkov_version` | `3` | checkov image tag |
| `pytest` | `true` | Enable pytest step |
| `terraform_test` | `true` | Enable `terraform test` step |
| `opentofu_validate` | `true` | Enable OpenTofu validation + test |
| `opentofu_version` | `1.9` | OpenTofu image tag |
| `docs_check` | `false` | Enable terraform-docs drift check |
| `docs_version` | `0.18.0` | terraform-docs image tag |
| `release_branch` | `main` | Branch that triggers releases |

**release-docker:**
| Parameter | Default | Description |
|---|---|---|
| `test_image` | `python:3.12-slim` | Docker image for lint/test steps |
| `image_name` | — | Docker image name (without `ghcr.io/barryw/`) |
| `setup_commands` | — | Commands to run before lint and test |
| `lint_commands` | — | Linting commands |
| `test_commands` | — | Test commands |
| `test_environment` | — | Environment variables for test step |
| `dockerfile` | `Dockerfile` | Path to Dockerfile |
| `docker_context` | `.` | Docker build context |
| `k8s_deploy` | `false` | Enable k8s deployment after build |
| `k8s_namespace` | `default` | Kubernetes namespace |
| `k8s_deployment` | — | Kubernetes deployment name |
| `k8s_container` | image_name | Container name in the deployment |

**release-macos-app:**
| Parameter | Default | Description |
|---|---|---|
| `app_name` | — | Display name; the built `<app_name>.app` and Release title |
| `scheme` | — | Xcode scheme to test/archive |
| `project` | — | `.xcodeproj` (or pass an `.xcworkspace` path) |
| `team_id` | — | Developer ID team for signing |
| `signing_identity` | — | `Developer ID Application: …` identity |
| `artifact_base` | — | Base name for `<base>-<version>-macos.dmg`/`.zip` |
| `notary_team_id` | `team_id` | notarytool team, if it differs from `team_id` |
| `export_options` | `Scripts/ExportOptions.plist` | `-exportOptionsPlist` path |
| `dmg_script` | `Scripts/create-dmg.sh` | Script that builds the `.dmg` |
| `keychain_setup` | `Scripts/setup-keychain-ci.sh` | Sourced to unlock the signing keychain (snapshots the original default keychain + search list for the restore step — WAL-101) |
| `keychain_restore` | `Scripts/restore-keychain-ci.sh` | Sourced by the final `restore-keychain` step (runs on success AND failure) to reset the host default keychain + search list (WAL-101) |
| `test_destination` | `platform=macOS` | `xcodebuild -destination` value |

**build-macos-app:** (per-push/PR build+test gate — no signing/release)
| Parameter | Default | Description |
|---|---|---|
| `project` | — | `.xcodeproj` (or pass an `.xcworkspace` path) |
| `scheme` | — | Xcode scheme to build/test |
| `test_destination` | `platform=macOS` | `xcodebuild -destination` value |
| `configuration` | `Debug` | `xcodebuild -configuration` value |

> Resolves private SwiftPM deps (e.g. PixelCanvasKit) via a workspace-local
> `insteadOf` token rewrite (`github_token` secret, contents:read). Pair it with
> `release-macos-app` in a repo's `templates:` list so every push/PR is gated
> while signed releases stay on the version-bump path.

**release-static-site:**
| Parameter | Default | Description |
|---|---|---|
| `site` | — | Image/namespace/deployment stem |
| `k8s_namespace` | `site` | Kubernetes namespace |
| `cloudflare_zone` | `cloudflare_zone_id` | Name of the Woodpecker secret holding the zone id |
| `deploy_path` | `deploy/` | Kustomize dir for `kubectl apply -k` |
| `website_path` | `website/**` | Push path glob that auto-triggers a deploy (plus `deploy/**`). Set to `web/**` for the house hub, whose content lives under `web/`. |
| `website_context` | `website` | kaniko build context |
| `dockerfile` | `website/Dockerfile` | Dockerfile path |
| `image_name` | `<site>-website` | GHCR image name (under `ghcr.io/barryw/`) |
| `deployment_name` | `<site>-website` | k8s deployment name |
| `container_name` | `website` | Container name in the deployment |

## Updating Templates

Templates are baked into the config service Docker image. To update:

```bash
cd ~/woodpecker-release
# Edit templates in config-service/templates/
docker build -t ghcr.io/barryw/woodpecker-config-service:latest -f config-service/Dockerfile config-service/
docker push ghcr.io/barryw/woodpecker-config-service:latest
kubectl rollout restart deployment/woodpecker-config-service -n woodpecker
```

All repos using templates will get the changes on their next pipeline run.

## Updating the Plugin

```bash
cd ~/woodpecker-release
# Edit scripts in plugin/
docker build --target base -t ghcr.io/barryw/woodpecker-release:latest -f plugin/Dockerfile plugin/
docker build --target go -t ghcr.io/barryw/woodpecker-release:go -f plugin/Dockerfile plugin/
docker push ghcr.io/barryw/woodpecker-release:latest
docker push ghcr.io/barryw/woodpecker-release:go
```

All repos will pull the new image on their next pipeline run (templates include `pull: true`).

## Architecture

```
woodpecker-release repo
├── plugin/                    → ghcr.io/barryw/woodpecker-release:{latest,go}
│   ├── Dockerfile
│   ├── entrypoint.sh
│   └── lib/*.sh
└── config-service/            → ghcr.io/barryw/woodpecker-config-service:latest
    ├── Dockerfile
    ├── templates/
    │   ├── release-tag-only/
    │   ├── release-go-library/
    │   ├── release-go-binary/
    │   └── release-docker/
    └── k8s/                   → deployed to woodpecker namespace on k3s
        ├── deployment.yml
        └── secret.yml

Per-repo config (3-18 lines):
.woodpecker/woodpecker-template.yaml  →  picked up by config service
cog.toml                              →  conventional commit config
```

## Troubleshooting

**Pipeline doesn't trigger:** Check that the repo is activated in Woodpecker and has the `github_token` secret.

**"unable to get any tag" error:** The cog check step can't find tags. This is handled gracefully in templates — it falls back to checking all commits.

**Version reset to v0.1.0:** Cog ignored existing tags. See "Handle existing version tags" in the onboarding steps.

**"Release already exists" message:** The plugin handles this gracefully — it continues with asset upload if the release exists.

**Stale plugin image:** Templates include `pull: true` to always pull the latest image. If you're using the plugin directly (not via template), add `pull: true` to your step.

**Config service not generating pipeline:** Check that the file is at `.woodpecker/woodpecker-template.yaml` (not `.woodpecker.yml`). Check config service logs: `kubectl logs -n woodpecker -l app=woodpecker-config-service`.
