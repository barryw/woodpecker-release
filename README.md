# woodpecker-release

Reusable Woodpecker CI release infrastructure. Semantic versioning with [Cocogitto](https://docs.cocogitto.io/), conventional commits, and GitHub Releases — done once, shared everywhere.

## Components

### Plugin (`ghcr.io/barryw/woodpecker-release`)

A Docker image that handles the entire release lifecycle:

- **`:latest`** — cog + gh + git + gpg (for tag-only and Docker releases)
- **`:go`** — adds Go toolchain for cross-compilation

#### Modes

| Mode | What it does |
|---|---|
| `bump` | cog bump + push commit + push tag |
| `release-tag` | bump + changelog + GitHub Release (no artifacts) |
| `release-go` | bump + Go cross-compile + optional GPG sign + GitHub Release |

#### Usage

```yaml
steps:
  - name: release
    image: ghcr.io/barryw/woodpecker-release:latest
    environment:
      PLUGIN_GITHUB_TOKEN:
        from_secret: github_token
    settings:
      mode: release-tag
```

#### Settings

| Setting | Default | Description |
|---|---|---|
| `mode` | `bump` | Plugin mode: `bump`, `release-tag`, `release-go` |
| `github_token` | — | GitHub token (from secret) |
| `git_name` | `Woodpecker CI` | Git committer name |
| `git_email` | `ci@woodpecker.local` | Git committer email |
| `git_branch` | `main` | Branch to push to |
| `git_remote` | `origin` | Git remote name |
| `bump_mode` | `auto` | Bump strategy: `auto`, `major`, `minor`, `patch` |
| `go_platforms` | `linux/amd64,...` | Comma-separated GOOS/GOARCH pairs |
| `go_binary_name` | repo name | Binary name prefix |
| `go_ldflags` | `-s -w -X main.version=...` | Go linker flags |
| `gpg_sign` | `false` | Enable GPG signing of checksums |
| `gpg_key` | — | ASCII-armored GPG private key (from secret) |
| `gpg_fingerprint` | — | GPG key fingerprint (from secret) |
| `terraform_manifest` | `false` | Generate Terraform Registry manifest |

### Config Service Templates

Pipeline templates served by the [Woodpecker Template Config Provider](https://github.com/RaphMad/woodpecker_template_config_provider). Repos reference a template instead of defining their own pipeline.

#### Available Templates

| Template | For |
|---|---|
| `release-tag-only` | Libraries (tag + changelog + GH release) |
| `release-go-binary` | Go projects (cross-compile + GPG + GH release) |
| `release-docker` | Docker projects (build + push to GHCR + GH release) |

#### Per-Repo Config

Each repo only needs a `.woodpecker.yml`:

```yaml
template: release-tag-only
```

Or with parameters:

```yaml
template: release-go-binary
params:
  go_platforms: "linux/amd64,linux/arm64,darwin/amd64,darwin/arm64,windows/amd64"
  gpg_sign: true
  terraform_manifest: true
```

## Repo Requirements

Every repo using this system needs:

1. A `cog.toml` with `skip_ci = "[skip ci]"` (the plugin verifies this)
2. Conventional commit messages
3. A `github_token` Woodpecker secret
4. (Optional) `gpg_private_key` and `gpg_fingerprint` secrets for signing
