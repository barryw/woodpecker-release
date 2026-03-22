# woodpecker-release

Reusable Woodpecker CI release infrastructure. Semantic versioning with [Cocogitto](https://docs.cocogitto.io/), conventional commits, and GitHub Releases — done once, shared everywhere.

Two components:
- **Plugin** (`ghcr.io/barryw/woodpecker-release`) — Docker image that handles cog bump, tag push, changelog, GitHub Release, Go cross-compilation, GPG signing
- **Config Service** — generates full pipeline YAML from templates so repos only need a 3-line config file

## Onboarding a New Repo

### Step 1: Add `cog.toml`

Copy this to the repo root:

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
repository = "YOUR_REPO_NAME"
owner = "barryw"

[commit_types]
feat = { changelog_title = "Features" }
fix = { changelog_title = "Bug Fixes" }
docs = { changelog_title = "Documentation" }
refactor = { changelog_title = "Refactoring" }
test = { changelog_title = "Tests" }
chore = { changelog_title = "Miscellaneous" }
perf = { changelog_title = "Performance" }
ci = { changelog_title = "CI/CD" }

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

**For a Terraform module** (validate + lint + security scan + test + release):
```yaml
template: release-terraform
data:
  terraform_version: "1.14"
  python_version: "3.12"
  docs_check: true
```

**For a simple library** (just validate commits + release, no build):
```yaml
template: release-tag-only
```

### Step 4: Remove old pipeline files

Delete any existing `.woodpecker.yml`, `.woodpecker/*.yml` files. The config service generates the pipeline from the template.

### Step 5: Add Woodpecker secrets

The repo needs these secrets in Woodpecker (Settings → Secrets):

| Secret | Required | Used for |
|---|---|---|
| `github_token` | Yes | Git push, GitHub Release creation |
| `gpg_private_key` | Only if `gpg_sign: true` | Signing checksums |
| `gpg_fingerprint` | Only if `gpg_sign: true` | GPG key ID |

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
| `release-terraform` | validate-commits → tf-validate → tflint → trivy → [checkov] → [pytest] → [tf-test] → [docs-check] → release | Terraform modules |

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
