# HaLOS Workspace - Agentic Coding Hub

**LAST MODIFIED**: 2026-02-16

**Document Purpose**: Central workspace for agentic coding with Claude Code and other AI assistants. This workspace provides full context across all HaLOS repositories for optimal AI-assisted development.

## 🎯 For Agentic Coding: Use This Workspace

**IMPORTANT**: When using Claude Code or other AI assistants, always work from this workspace repository, not individual sub-repos. The full context enables better code understanding and implementation quality.

**Development Workflows**: See `docs/` folder:
- `docs/LIFE_WITH_CLAUDE.md` - Quick start for human developers
- `docs/IMPLEMENTATION_CHECKLIST.md` - Implementation checklist
- `docs/DEVELOPMENT_WORKFLOW.md` - Detailed Claude Code workflows
- `docs/PROJECT_PLANNING_GUIDE.md` - Project planning process
- `docs/HOSTNAME_POLICY.md` - Policy on hard-coded hostname references
- `docs/solutions/` - Documented solutions to past problems (bugs, best practices, workflow patterns), with YAML frontmatter for searchability; relevant when implementing or debugging in documented areas

## ⛔ Test Device Policy

**NEVER build on test devices.** Test devices (e.g., `halos.local`) are for **testing only**, not for compiling code.

All build operations MUST be performed locally on the development machine using the `./run` script commands provided by each repository. For example:
- `./run build` - Build debug binary
- `./run build-release` - Build release binary
- `./run test` - Run tests

For cross-compilation or architecture-specific builds, use the CI/CD pipeline or local cross-compilation toolchains. Do not SSH into test devices to compile code - this is slow, pollutes the test environment, and risks destabilizing the device.

**Allowed on test devices:**
- Deploying pre-built binaries/packages
- Running and observing services
- Checking logs and system state
- Testing functionality

**NOT allowed on test devices:**
- Installing compilers, build tools, or development dependencies
- Running `cargo build`, `npm install`, `make`, or similar build commands
- Cloning source repositories for building

## About HaLOS

Halos (Hat Labs Operating System) - custom Raspberry Pi OS distribution with web management.

**Documentation**: [docs.halos.fi](https://docs.halos.fi) | **Website**: [halos.fi](https://halos.fi)

This workspace manages multiple independent repositories. While each repository works independently from a code perspective, agentic coding requires the full workspace context.

## Git Workflow Policy

**MANDATORY**: PRs must ALWAYS have all checks passing before merging. No matter what.

**PR Reviews**: When reviewing pull requests, always post review comments directly on the PR itself using `gh pr comment`. This ensures feedback is visible to all stakeholders and preserved in the project history.

**Pre-commit Hooks**: Repositories use [lefthook](https://github.com/evilmartians/lefthook) for pre-commit hooks. After cloning, install hooks with `./run install-hooks`. See `docs/LIFE_WITH_CLAUDE.md` for details.

**Changelog Policy**: Never edit `debian/changelog` files directly. Always use `./run bumpversion` which uses the `dch` tool for proper RFC 2822 date formatting. Direct edits cause weekday/date mismatches that break Debian tools. See individual repository AGENTS.md for details.

**Version Bumps**: VERSION bumps are *per release cycle*, not per PR. Default: do NOT bump `VERSION` in feature PRs — CI auto-increments the `+N` revision in release tags (e.g., `v0.3.2+1`, `+2`, `+3`) between stable releases. Bump `VERSION` only when starting a new release cycle, i.e., when `VERSION` currently matches the latest stable tag and this PR is opening the next cycle. If `VERSION` already differs from the latest stable tag (a prior PR opened the cycle), no further bump is needed regardless of how many package-affecting files this PR touches. App-level versions in `apps/*/metadata.yaml` (container repos) bump per PR independently. CI enforces both rules conditionally — see `shared-workflows/.github/workflows/version-bump-check.yml`. Docs, tests, CI config, and dev tooling changes are excluded from the repo-level check.

## Structure

```
halos/
├── halos-pi-gen/                  # Image builder
├── apt.hatlabs.fi/                # Custom APT repo
├── cockpit-apt/                   # Cockpit APT package manager
├── cockpit-authelia-users/        # Authelia user management for Cockpit
├── cockpit-container-apps/        # Container app management UI
├── cockpit-dockermanager-debian/  # Docker manager Cockpit plugin
├── cockpit-networkmanager-halos/  # Cockpit NetworkManager with WiFi features
├── container-packaging-tools/     # Container package generator
├── halos-cockpit-config/          # Cockpit HaLOS config and branding
├── halos-core-containers/         # Core app definitions (Homarr, Traefik, Authelia)
├── halos-homarr-branding/         # Homarr HaLOS branding package
├── halos-imported-containers/     # Auto-imported apps from CasaOS, Runtipi, etc.
├── halos-marine-containers/       # Marine app definitions + store
├── halos-metapackages/            # HaLOS metapackages (halos, halos-marine)
├── homarr-container-adapter/      # Homarr first-boot setup and container discovery
├── opencpn-docker/                # OpenCPN Docker image
├── signalk-halpi/                 # Signal K plugin for HALPI2 monitoring (hatlabs org)
└── shared-workflows/              # Reusable GitHub Actions workflows
```

**Each repository has its own AGENTS.md** - read the appropriate one for detailed context.

## GitHub Organizations and APT Repositories

Repositories are split across two GitHub orgs:

- **`halos-org`** — Most HaLOS repos. APT packages deploy to `halos-org/apt.halos.fi`.
- **`hatlabs`** — Hardware-specific repos (`signalk-halpi`), upstream forks (`homarr`, `signalk-server`, `signalk-alert-manager`), and `apt.hatlabs.fi`. APT packages deploy to `hatlabs/apt.hatlabs.fi`.

When configuring CI workflows, always use the correct `apt-repository` input for the shared workflows. Repos in `hatlabs` must explicitly set `apt-repository: hatlabs/apt.hatlabs.fi` (the default is `halos-org/apt.halos.fi`).

**Important**: Each org has its own copy of `shared-workflows`. Repos in `hatlabs` should reference `hatlabs/shared-workflows` (which defaults to `hatlabs/apt.hatlabs.fi`), and repos in `halos-org` should reference `halos-org/shared-workflows` (which defaults to `halos-org/apt.halos.fi`). Using the correct org's shared-workflows avoids needing to override the `apt-repository` input.

## Quick Start

```bash
# Clone all component repositories
./run clone-repos

# Update all repositories
./run pull-all-main

# Build an image
cd halos-pi-gen
./run docker-build "Halos-Marine-HALPI2"
```

## Architecture Layers

1. **Base OS**: Debian-based Raspberry Pi OS (arm64, trixie) built with pi-gen
2. **Web Management** (all): Traefik (80/443) + Authelia (SSO) + Cockpit (9090) + Homarr (7575)
3. **Hardware** (HALPI2 only): HALPI2 drivers, CAN, RS-485, I2C
4. **Marine** (marine variants): Signal K (3000) → InfluxDB (8086) → Grafana (3001)

## Repository Management

```bash
# Update all repositories to latest main/halos branches
./run pull-all-main

# Check status of all repositories
./run show-status

# Work in a specific repository
cd halos-pi-gen
git pull origin main
# make changes, commit, push
cd ..
```

Each repository is managed independently. The halos workspace tracks only shared documentation and convenience scripts.
