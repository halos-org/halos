---
title: "feat: Bootstrap public halos-pi-gen-template repo"
type: feat
status: completed
date: 2026-04-27
---

# feat: Bootstrap public halos-pi-gen-template repo

**Target repo:** `halos-pi-gen-template` (new public repo in `halos-org`, to be created). Source material lives in the private `halos-pi-gen-custom` repo, which remains untouched. All paths in this plan are relative to the new template repo's root unless explicitly noted.

## Overview

Create a new public repository `halos-org/halos-pi-gen-template` that serves as a worked example and starting point for downstream users who want to build their own custom HaLOS images. The template is bootstrapped from a snapshot of `halos-pi-gen-custom` (private), with the proprietary "selene" naming replaced by a generic "ais" example variant. Repository is initialized with a single fresh commit — no history import.

## Problem Frame

`halos-pi-gen-custom` proves the three-layer build pattern works (`pi-gen` → `halos-pi-gen` → custom stages) but lives in a private repo and carries an internal customer name (`selene`). External users and integrators have no public reference for how to layer their own pi-gen stages on top of HaLOS. A public template fills that gap without exposing private history or customer references, and demonstrates the pattern with a non-proprietary example (the public `ais-forwarder` Signal K plugin).

## Requirements Trace

- R1. Public repo `halos-org/halos-pi-gen-template` exists with a clean single-commit history (no selene-era authorship in commit messages or trees).
- R2. The example variant is named `ais` everywhere `selene` previously appeared (config filename, `IMG_NAME`, `PI_GEN_RELEASE`, `STAGE_LIST` entry, `CONTAINER_NAME`, stage directory name, CI matrix entry, README copy).
- R3. The template builds a working image end-to-end via `./run build config.halos-desktop-marine-halpi2-ap-ais` and via the GitHub Actions matrix.
- R4. README explains the three-layer customization model, links to upstream `pi-gen` docs and `halos-org/halos-pi-gen`, and walks a new user through forking, adding a stage, and triggering a build.
- R5. All config env vars from the source repo are preserved with explanatory comments inline in the config file.
- R6. `.gitignore` excludes `build.log`, `pi-gen/` (clone target), and image artifacts (`*.img`, `*.xz`).
- R7. CI workflow URL/repo references point at the new template repo (no leftover `halos-pi-gen-custom` references in `PI_GEN_REPO`, README, or workflow comments).
- R8. The private `halos-pi-gen-custom` repo is unchanged by this work.

## Scope Boundaries

- Not modifying `halos-pi-gen-custom` in any way.
- Not creating additional example variants beyond the renamed `ais` one.
- Not changing the build mechanics in `run` or the workflow's disk-cleanup/build steps — only string-level rename and URL updates.
- Not pinning a specific `ais-forwarder` version policy (template inherits the existing `0.4.1` pin; downstream users decide their own policy).
- Not adding tests for shell scripts — pi-gen stage scripts are not unit-tested in source repos either.
- Not setting up branch protection, CODEOWNERS, or repo settings beyond what `gh repo create` provides — out of scope for this plan; can be added post-creation if needed.
- Not publishing release artifacts — the template builds on push to main but releases stay as drafts (matches source behavior; downstream consumers decide their own release policy).

## Context & Research

### Relevant Code and Patterns

Source files in `halos-pi-gen-custom/` (private repo, snapshotted, not modified):

- `config.halos-desktop-marine-halpi2-ap-selene` — pi-gen config file, 14 env vars, references `https://github.com/hatlabs/halos-pi-gen-custom` (must be rewritten).
- `stage-custom-selene/prerun.sh` — boilerplate `copy_previous` guard, no selene-specific content.
- `stage-custom-selene/00-install-sk-plugins/00-run.sh` — downloads `ais-forwarder` v0.4.1 from npmjs.org, extracts into Signal K data dir, chowns to uid 1000. Already AIS-themed; only directory name needs to change.
- `README.md` — minimal (one variant table row, a "How It Works" paragraph mentioning selene, an "Adding New Variants" section). Needs full rewrite to template style.
- `run` — bash task runner. The `build` function is fully generic (takes config name as arg). No selene references. Will be carried over verbatim.
- `.github/workflows/build.yml` — single matrix entry hardcodes `Halos-Desktop-Marine-HALPI2-AP-Selene` and the config filename; release notes body lists the same name.
- `.gitignore` — currently `pi-gen/`, `artifacts/`, `build.log`. Needs `*.img` and `*.xz` added.

### Institutional Learnings

None directly applicable in `docs/solutions/`. Relevant workspace patterns from `AGENTS.md`:
- HaLOS repos in `halos-org` use `halos-org/shared-workflows` as the default; this template's CI does *not* call shared workflows (it builds an image, not a deb), so no `apt-repository` setting is needed.
- New `halos-org` repos do not need APT publishing wiring.

### External References

- pi-gen upstream: `https://github.com/RPi-Distro/pi-gen` — README documents stage layout, `STAGE_LIST`, `SKIP`/`SKIP_IMAGES` markers, `prerun.sh` and numbered `NN-run.sh` scripts. Link from template README.
- HaLOS pi-gen layer: `https://github.com/halos-org/halos-pi-gen` — provides `stage-halos-base`, `stage-halos-marine`, etc. Link from template README.
- `ais-forwarder` Signal K plugin: `https://www.npmjs.com/package/ais-forwarder` — public npm package, no licensing concerns for a template.

## Key Technical Decisions

- **Bootstrap by file copy + `git init`, not by `git clone --depth 1` of source.** Even with `--depth 1`, the resulting repo carries the source's commit metadata. A fresh `git init` in a clean working tree gives a single self-authored "Initial template" commit with no link to selene history. Rationale: minimizes leak surface, makes the public history obviously clean.
- **"ais" used as the example name in all renamed positions.** Confirmed by the user. The variant continues to demonstrate the same `ais-forwarder` install, so the name is descriptive rather than arbitrary.
- **Config env vars preserved verbatim, documented inline with `#` comments.** Each var gets a one-line comment explaining its role and whether the user is expected to change it when forking. Avoids a separate docs file that would drift.
- **README rewritten from scratch.** The source README (1KB, three short sections) is too thin for a public template. Target: ~150–250 lines covering concepts, quick start, variant authoring, three-layer model, troubleshooting basics, and links.
- **CI workflow kept structurally identical** to the source — only matrix entry name, config path, and release-notes string change. Same draft-release behavior. Rationale: anyone who copies the workflow gets a working build pipeline; we don't reinvent it.
- **No license file decision baked in.** Add `LICENSE` (MIT) by default since the template is meant to be forked. Flagged below as a decision the user can override.

## Open Questions

### Resolved During Planning

- Should `halos-pi-gen-custom` history be preserved in the public repo? **No** — fresh init with one commit (user-confirmed).
- Should we generalize variants to multiple examples? **No** — single `ais` example keeps the template focused (user-confirmed; out of scope).
- Should env vars be moved to a separate doc? **No** — inline `#` comments in the config file (decision above).

### Deferred to Implementation

- Final wording/structure of the README — drafted during execution, reviewed before commit.
- Whether to add a `CODEOWNERS` or repo-level branch protection — out of scope for this plan; revisit after first external use.
- Exact LICENSE choice (MIT assumed; user may pick Apache-2.0 or other at execution time).

## Implementation Units

- [ ] **Unit 1: Initialize the new local repo from a clean snapshot**

**Goal:** Produce a working tree on disk for `halos-pi-gen-template` that mirrors `halos-pi-gen-custom`'s tracked content with no `.git/` directory carried over, ready for in-place renames.

**Requirements:** R1, R8

**Dependencies:** None.

**Files:**
- Create (locally): new directory `halos-pi-gen-template/` adjacent to `halos-pi-gen-custom/` in the workspace.
- Copy from `halos-pi-gen-custom/` (source, untouched): `config.halos-desktop-marine-halpi2-ap-selene`, `stage-custom-selene/`, `README.md`, `run`, `.gitignore`, `.github/workflows/build.yml`.
- Exclude: `.git/`, `build.log`, `pi-gen/`, any untracked files.

**Approach:**
- Use `git archive` from the source repo (or equivalent tracked-files-only copy) to materialize only checked-in content into the new directory. This guarantees no `.git/` and no untracked artifacts leak in.
- Do **not** run `git init` yet — that happens in the final unit after all renames are in place, so the initial commit is clean.

**Patterns to follow:** Standard "snapshot a repo without history" workflow.

**Test scenarios:**
- Verification: `ls -la halos-pi-gen-template/` shows no `.git/`, no `build.log`, no `pi-gen/`. Tracked files match `git ls-files` output of the source.
- Test expectation: none — file copy operation, no behavioral change.

**Verification:**
- New directory contains exactly the tracked file set from the source.
- No `.git/`, build artifacts, or untracked content present.

- [ ] **Unit 2: Rename `selene` → `ais` across the working tree**

**Goal:** All references to "selene" / "Selene" / "SELENE" replaced with the corresponding "ais" / "Ais" / "AIS" form in filenames, directory names, and file contents. After this unit, `grep -ri selene` returns no results.

**Requirements:** R2, R7

**Dependencies:** Unit 1.

**Files:**
- Rename: `config.halos-desktop-marine-halpi2-ap-selene` → `config.halos-desktop-marine-halpi2-ap-ais`
- Rename: `stage-custom-selene/` → `stage-custom-ais/`
- Modify: `config.halos-desktop-marine-halpi2-ap-ais` — `IMG_NAME`, `PI_GEN_RELEASE`, `STAGE_LIST` (the `stage-custom-selene` entry), `CONTAINER_NAME`, and `PI_GEN_REPO` (point at new template repo URL).
- Modify: `.github/workflows/build.yml` — matrix entry `name`, `config` path, and the `Included Images` line in the release notes body.
- Modify: `README.md` — will be fully replaced in Unit 4, but ensure no references survive interim edits in this unit.

**Approach:**
- Apply the renames as discrete, reviewable edits. Case-preserving substitution across the small fileset (5 files affected) is straightforward — no need for a bulk sed script.
- The new `PI_GEN_REPO` value is `https://github.com/halos-org/halos-pi-gen-template`.
- Verify with `grep -ri 'selene\|Selene\|SELENE'` returning empty before moving on.

**Patterns to follow:** Match exact casing patterns from the source (`Selene` in human-readable strings, `selene` in identifiers).

**Test scenarios:**
- Edge case: case-sensitive grep for all three casings returns no results post-rename.
- Edge case: filenames and directory names also contain no "selene" substring.
- Test expectation: rename-only change; behavioral verification deferred to Unit 6.

**Verification:**
- `grep -ri selene .` from the working tree root returns no matches.
- `find . -name '*selene*'` returns no matches.
- Diff vs. source shows only string substitutions and renames, no content drift.

- [ ] **Unit 3: Update `.gitignore` and add `LICENSE`**

**Goal:** Public repo hygiene — ignore build outputs and declare license.

**Requirements:** R6

**Dependencies:** Unit 1.

**Files:**
- Modify: `.gitignore` — add `*.img` and `*.xz` to existing entries (`pi-gen/`, `artifacts/`, `build.log`).
- Create: `LICENSE` — MIT license, copyright "Hat Labs Ltd" or equivalent (confirm at execution time).

**Approach:**
- Keep existing `.gitignore` lines; append the two new patterns.
- LICENSE is a verbatim MIT template with year `2026` and the appropriate copyright holder.

**Test scenarios:**
- Test expectation: none — config/declarative file additions, no runtime behavior.

**Verification:**
- `.gitignore` contains all five entries; no duplicates.
- `LICENSE` parses as a recognizable MIT license (GitHub will detect it post-push).

- [ ] **Unit 4: Annotate the config file with inline documentation**

**Goal:** Every env var in `config.halos-desktop-marine-halpi2-ap-ais` carries a comment explaining its purpose and whether forks should change it. Preserves R5 (vars unchanged) while improving discoverability for template users.

**Requirements:** R5

**Dependencies:** Unit 2.

**Files:**
- Modify: `config.halos-desktop-marine-halpi2-ap-ais`

**Approach:**
- Add a header comment block summarizing what this file is and how pi-gen consumes it.
- Group vars into logical sections with `# === Section ===` headers: Image identity, Build infrastructure, Stage list, User defaults, Localization, Services.
- Each var gets a single-line comment above it. Examples of intent (not exact wording):
  - `IMG_NAME` — "Output image filename prefix. Change when forking."
  - `PI_GEN_REPO` — "Used by pi-gen for build provenance metadata. Point at your fork."
  - `STAGE_LIST` — "Ordered list of pi-gen stages. The custom stage must come last (before stage-export)."
  - `FIRST_USER_PASS` — "Default first-boot password. CHANGE THIS for production images."
  - `WPA_COUNTRY` — "Two-letter ISO country code for WiFi regulatory domain. Change to match your region."
  - `DISABLE_FIRST_BOOT_USER_RENAME` — "Set to 1 to keep `pi` as the username on first boot; 0 lets the user rename via firstrun.sh."
- Values themselves do not change.

**Patterns to follow:** Standard `KEY="value"` shell config with `#` comments. Match existing pi-gen config commenting style (sparse but present in upstream `pi-gen/config.example`).

**Test scenarios:**
- Edge case: file is still a valid shell script (`bash -n config.halos-desktop-marine-halpi2-ap-ais` returns 0).
- Test expectation: comment-only change verified by Unit 6 build.

**Verification:**
- All 14 vars have an associated comment.
- Shell parse check passes.
- Diff vs. Unit 2 output is comment-only.

- [ ] **Unit 5: Write the public template README**

**Goal:** A comprehensive README that teaches the three-layer model and walks a new user from fork → custom stage → built image.

**Requirements:** R4

**Dependencies:** Unit 2 (so examples reference `ais`, not `selene`).

**Files:**
- Modify: `README.md` (full rewrite)

**Approach:**
- Target structure (section order):
  1. **Title + one-line summary** — "Template for building custom HaLOS images by layering your own pi-gen stages."
  2. **What this is** — explain the three-layer model with a small diagram (text or mermaid):
     ```
     pi-gen (upstream Raspberry Pi OS builder)
        └── halos-pi-gen (HaLOS base + marine + halpi2 stages)
              └── this template (your custom stages)
     ```
  3. **The example variant** — describe the `ais` variant, what it produces, what stage it adds (`stage-custom-ais` installs `ais-forwarder` Signal K plugin), and what the resulting image is good for.
  4. **Quick start** — clone, install build deps, run `./run build config.halos-desktop-marine-halpi2-ap-ais`, find image in `pi-gen/deploy/`. Mention CI alternative (push to main → GitHub Actions builds and creates a draft release).
  5. **Customization guide** — step-by-step "how to make your own variant":
     - Copy `config.halos-desktop-marine-halpi2-ap-ais` to a new name.
     - Edit `IMG_NAME`, `PI_GEN_RELEASE`, `CONTAINER_NAME`, `STAGE_LIST` to reference your new stage.
     - Copy `stage-custom-ais/` to `stage-custom-<yours>/` and edit the install scripts.
     - Add a matrix entry to `.github/workflows/build.yml`.
     - Push and let CI build it.
  6. **How pi-gen stages work (briefly)** — `prerun.sh`, numbered `NN-run.sh` scripts, `${ROOTFS_DIR}`, `copy_previous`, `SKIP` / `SKIP_IMAGES` markers. Link to upstream pi-gen docs for full reference.
  7. **Configuration reference** — short table of env vars in the config file, mirroring the inline comments from Unit 4 but in tabular form for scannability.
  8. **Troubleshooting** — disk space (CI workflow already aggressively frees it; mention if running locally), Docker requirement, ARM64 host or qemu, signing/checksums.
  9. **Links** — upstream `pi-gen` (https://github.com/RPi-Distro/pi-gen), `halos-org/halos-pi-gen`, `ais-forwarder` plugin, HaLOS docs (https://docs.halos.fi).
  10. **License** — MIT, see `LICENSE`.
- Tone: instructive, concrete, snippet-heavy. Code blocks for shell commands. No emoji.
- Length target: 150–250 lines.

**Patterns to follow:** README style of `halos-org/halos-pi-gen` for tone consistency across the HaLOS family of repos.

**Test scenarios:**
- Test expectation: documentation-only; verified manually by reading and by following the Quick Start in Unit 6.

**Verification:**
- All 10 sections present.
- Every command shown is one a fresh user could actually run after cloning.
- All external links resolve (manual check).
- No leftover references to `selene` or `halos-pi-gen-custom`.

- [ ] **Unit 6: Verify the renamed template builds end-to-end**

**Goal:** Confirm the rename and annotations did not break the build before the repo goes public.

**Requirements:** R3

**Dependencies:** Units 2, 3, 4.

**Files:**
- No files modified. Build is run from the working tree.

**Approach:**
- From the new working tree, run `./run build config.halos-desktop-marine-halpi2-ap-ais` locally (Docker required; takes ~30–60 min).
- If local build is impractical (disk space, time), defer to CI verification on a PR-equivalent branch after the repo is created (Unit 7) — but flag this as a deferred check in the handoff, not as "done."
- Successful build produces an `.xz` image in `pi-gen/deploy/` matching the new IMG_NAME pattern.

**Execution note:** This is a verification step, not a code change. Failure here means rolling back to investigate before the repo is published.

**Test scenarios:**
- Happy path: build completes successfully and produces an image artifact named `Halos-Desktop-Marine-HALPI2-AP-Ais_<version>.img.xz`.
- Failure path: any stage error → halt before publishing the repo, fix, re-verify.

**Verification:**
- Build exits 0.
- Output `.xz` exists in `pi-gen/deploy/`.
- Image filename reflects the `ais` rename.

- [ ] **Unit 7: Create the GitHub repo, push, and verify CI**

**Goal:** Public repo `halos-org/halos-pi-gen-template` exists with the prepared snapshot as its initial state, and the build workflow runs green.

**Requirements:** R1, R3, R7

**Dependencies:** Units 2–6.

**Files:**
- No working-tree file changes. Operations are git/gh CLI commands against the new local repo and the remote.

**Approach:**
- In the prepared `halos-pi-gen-template/` working tree:
  - `git init` (default branch `main`).
  - `git add .` — verifies `.gitignore` excludes the right things (no `pi-gen/` or `build.log` should appear in `git status`).
  - Single commit with message along the lines of `feat: initial template release`.
- Create remote: `gh repo create halos-org/halos-pi-gen-template --public --source=. --description "..."`. Confirm remote URL matches what was written into `PI_GEN_REPO` in Unit 2.
- Push `main`.
- Watch the CI run via `gh run watch`. The first run should produce a draft release.
- If CI fails, fix on a branch, PR, merge.

**Execution note:** Per workspace policy, ask the user before pushing or creating the remote. Do not auto-create.

**Test scenarios:**
- Happy path: repo exists, `main` is pushed, CI run completes successfully, draft release created.
- Edge case: confirm `git log` shows exactly one commit, authored by the user, with no selene references in message or content.
- Error path: CI failure → fix-forward on a branch, do not force-push history.

**Verification:**
- `gh repo view halos-org/halos-pi-gen-template` succeeds.
- `git log --oneline` on the remote shows one commit.
- `gh run list` shows a green "Build Custom HaLOS Image" run.
- Draft release exists with the renamed image artifact attached.

## System-Wide Impact

- **Interaction graph:** None inside HaLOS — new standalone public repo. External: forkers and downstream consumers will derive from it; the `PI_GEN_REPO` URL becomes a stable public reference.
- **Error propagation:** N/A (no shared runtime).
- **State lifecycle risks:** Once public, history rewrites become user-hostile. The single-commit init means nothing to rewrite later, but any subsequent force-pushes to `main` would break forks — treat the published `main` as append-only from day one.
- **API surface parity:** The config env var contract is the public surface. Renaming or removing vars later is a breaking change for forks. Inline comments (Unit 4) become part of that contract.
- **Integration coverage:** Unit 6 covers the local build path; Unit 7's CI run covers the workflow path. Both must pass before the repo is considered ready.
- **Unchanged invariants:**
  - `halos-pi-gen-custom` is read-only for this work — no commits, branches, or pushes.
  - Build mechanics in `run` (the bash task runner) are unchanged from the source.
  - The shared workflow contract (`halos-org/shared-workflows`) is not touched — this template intentionally uses its own workflow because it builds an image, not a `.deb`.
  - `halos-org/halos-pi-gen` is unchanged; the template merely references it.

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Lingering "selene" reference slips into the public repo | Mandatory `grep -ri selene` check after Unit 2 and again before commit in Unit 7. CI logs and release notes also grepped. |
| Build breaks because of a missed rename in `STAGE_LIST` or stage directory | Unit 6 builds the image end-to-end before publishing. CI run in Unit 7 is a second gate. |
| Fresh `git init` accidentally includes `.git/` from the source | Unit 1 uses `git archive` (or equivalent tracked-files-only export); Unit 7 verifies `git log` shows exactly one commit. |
| `PI_GEN_REPO` URL points at a not-yet-existing repo during the first build | Unit 2 sets the correct future URL; the value is only used for image metadata, not for clone/fetch. Confirmed by inspecting `run` and the workflow — no operation depends on the URL being live. |
| Disk space failure on local Unit 6 build | Acceptable to defer to CI verification (Unit 7), explicitly flagged in handoff if local build skipped. |
| Public repo accidentally created in `mairas` or `hatlabs` instead of `halos-org` | Use explicit `halos-org/halos-pi-gen-template` in `gh repo create`; per `~/.claude/CLAUDE.md` and the gh-org-validator hook, this is enforced. |
| LICENSE mismatch with HaLOS family conventions | Confirm MIT is correct for this org at execution time before committing the LICENSE file. |

## Documentation / Operational Notes

- After repo creation, consider linking the template from `halos-org/halos-pi-gen` README and from `docs.halos.fi` as the canonical public starting point. Out of scope for this plan; track separately.
- No APT publishing wiring needed — this repo produces image artifacts, not Debian packages.
- No version-bump-check or shared-workflow CI integration — the build workflow is self-contained.

## Sources & References

- Audit performed against `halos-pi-gen-custom/` working tree (private; not modified).
- Selene-reference inventory: 5 files (`config.halos-desktop-marine-halpi2-ap-selene`, `stage-custom-selene/prerun.sh`, `stage-custom-selene/00-install-sk-plugins/00-run.sh`, `README.md`, `.github/workflows/build.yml`).
- Upstream pi-gen docs: https://github.com/RPi-Distro/pi-gen
- HaLOS pi-gen layer: https://github.com/halos-org/halos-pi-gen
- AGENTS.md (workspace) — GitHub org policy and `halos-org` vs. `hatlabs` mapping.
- `~/.claude/CLAUDE.md` — git workflow conventions, no auto-push policy.
