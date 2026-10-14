# HaLOS Workspace - Agentic Coding Hub

**LAST MODIFIED**: 2026-10-14

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

**Version Bumps**: The goal is that every build producing a `.deb` gets a strictly increasing version, valid under both semver and Debian version ordering. The increment lands at one of two levels: the `+N` build revision auto-increments on each merge (e.g. `v0.3.2+1`, `+2`, `+3`), or you bump a version element by hand when opening a release cycle. The hand bump is rare — default to not bumping.

Decision procedure for a feature PR:

1. **App metadata** (container repos with `apps/`): if you changed non-metadata files under `apps/<name>/`, bump the `version` field in that app's `metadata.yaml`. Per PR, per app, independent of everything below.
2. **Repo `VERSION`** (per release cycle, not per PR):
   - Find the latest stable release with `gh release list --exclude-drafts --exclude-pre-releases`. Stable tags look like `v0.3.2+4`; strip `+N` for the upstream version. Use the GitHub API, not `git tag` — draft releases leave tags that are not stable releases.
   - If `VERSION` already differs from that upstream version, a prior PR opened the cycle. Do **not** bump, regardless of how many package files this PR touches; CI walks `+N` on merge — *unless* this PR's change is a higher semver level than the bump that opened the cycle. `VERSION` must reflect the highest-impact change accumulated in the open cycle, so a minor-level change in a patch-opened cycle (or a major in a minor-opened one) re-bumps once with `./run bumpversion`. The check enforces only that *a* bump occurred, not that its level is correct — the level is an author/reviewer judgment.
   - If `VERSION` equals it **and** this PR changes package-affecting files, this PR opens the next cycle: bump once with `./run bumpversion patch|minor|major`.

"Package-affecting" means any file that ends up in a `.deb` — everything except docs, tests, CI config, and dev tooling. The exact set is non-obvious (root `docker-compose.yml` is payload for container repos and counts; `run`, `Makefile`, `tools/`, `store/`, `docker/`, and lockfiles do not), so treat `shared-workflows/.github/workflows/version-bump-check.yml` as the source of truth. Per-repo changelog schemes differ (committed vs CI-generated `debian/changelog`); see each repo's AGENTS.md.

## Worktree Location

Git worktrees live in a hidden `.worktrees/` directory **inside the clone they belong to**, at `<repo>/.worktrees/<branch>` — keeping each worktree co-located with its own repo. Never create them as siblings inside this workspace (e.g. a `cockpit-apt-203/` next to `cockpit-apt/`): this workspace root is itself a git repo, so a sibling shows up as untracked clutter in its `git status`, belongs to no repo in anyone's mental model, and rots unnoticed. Keep `.worktrees/` gitignored so it never clutters the owning repo's status either. Use the `git-worktree` skill, which defaults to this location; don't hand-run `git worktree add ../<name>`. The Agent tool's transient `<repo>/.claude/worktrees/agent-*` worktrees follow the same in-clone pattern and self-clean.

## Structure

```
halos/
├── brand/                         # HaLOS and Hat Labs logo sources
├── halos-pi-gen/                  # Image builder
├── halos-pi-gen-custom/           # Custom HaLOS builds with pre-installed plugins
├── halos-pi-gen-template/         # Template for layering custom stages on halos-pi-gen
├── pi-gen/                        # Raspberry Pi OS image tool (fork)
├── flash-live-system/             # Flash an SBC over the network while it runs
├── apt.halos.fi/                  # HaLOS APT repo
├── apt.hatlabs.fi/                # Hat Labs APT repo
├── cockpit/                       # Cockpit (fork)
├── cockpit-apt/                   # Cockpit APT package manager
├── cockpit-authelia-users/        # Authelia user management for Cockpit
├── cockpit-container-apps/        # Container app management UI
├── cockpit-dockermanager-debian/  # Docker manager Cockpit plugin
├── cockpit-networkmanager-halos/  # Cockpit NetworkManager with WiFi features
├── container-packaging-tools/     # Container package generator
├── halos-bridge-metapackage/      # Migration from apt.hatlabs.fi to apt.halos.fi
├── halos-browser-trust/           # Make Chromium and Firefox trust the system CA store
├── halos-cockpit-config/          # Cockpit HaLOS config and branding
├── halos-core-containers/         # Core app definitions (Homarr, Traefik, Authelia)
├── halos-desktop-branding/        # Branding and wallpaper for desktop variants
├── halos-halpi-desktop-branding/  # HALPI2 branding for desktop variants
├── halos-halpi2-desktop/          # HALPI2 desktop variant metapackage
├── halos-homarr-branding/         # Homarr HaLOS branding package
├── halos-imported-containers/     # Auto-imported apps from CasaOS, Runtipi, etc.
├── halos-marine-containers/       # Marine app definitions + store
├── halos-mdns-publisher/          # Advertises *.halos.local subdomains via Avahi
├── halos-metapackages/            # HaLOS metapackages (halos, halos-marine)
├── halos-ublox-config/            # u-blox GNSS receiver auto-configuration
├── homarr/                        # Homarr (upstream clone, reference)
├── homarr-container-adapter/      # Homarr first-boot setup and container discovery
├── authelia/                      # Authelia (upstream clone, reference)
├── avnav/                         # AvNav (upstream clone, reference)
├── opencpn-docker/                # OpenCPN Docker image
├── signalk-server-docker/         # Signal K server image with the marine plugin set
├── docs.halos.fi/                 # docs.halos.fi site
├── docs-tools/                    # Documentation checkers for the MkDocs sites
├── halos.fi/                      # HaLOS landing page
└── shared-workflows/              # Reusable GitHub Actions workflows
```

**Each repository has its own AGENTS.md** - read the appropriate one for detailed context.

Signal K webapps and plugins (Skip, KIP, the alert and history provider plugins) and the Signal K server fork are developed in a separate workspace, `hatlabs/signalk-workspace`.

## GitHub Organizations and APT Repositories

Repositories are split across two GitHub orgs:

- **`halos-org`** — Most HaLOS repos. APT packages deploy to `halos-org/apt.halos.fi`.
- **`hatlabs`** — Hardware-specific repos (`halos-pi-gen-custom`, `halos-halpi-desktop-branding`, `halos-halpi2-desktop`, `flash-live-system`), `halos-bridge-metapackage`, upstream forks (`homarr`), and `apt.hatlabs.fi`. APT packages deploy to `hatlabs/apt.hatlabs.fi`.

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
