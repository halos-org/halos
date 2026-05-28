# Runbook: Rebase the Homarr fork onto a new upstream release and promote it to production

**Audience**: Claude Code sessions (and humans) working in the HaLOS workspace who need to bump the production Homarr image to a new upstream release base while the upstream PR ([homarr-labs/homarr#5595](https://github.com/homarr-labs/homarr/pull/5595)) for path-only app hrefs is still in flight.

**When to run**: A new upstream Homarr release is out (e.g., `v1.61.0`), and HaLOS production should adopt it without losing the path-only-href patch. Or: a new fork-only iteration is needed on top of the *current* upstream base (e.g., follow-up patch lands on the fork).

**When NOT to run**: When upstream PR #5595 has merged AND a stable upstream release contains the patch — at that point the production pin can move back to `ghcr.io/homarr-labs/homarr:<tag>` and the fork is no longer needed. That migration is its own runbook (not yet written).

---

## Repos involved

| Repo | Role | Branches you'll touch |
|------|------|----------------------|
| `hatlabs/homarr` | Fork; carries the path-only-href patch + fork CI | `feat/path-only-app-hrefs` (production-build), `upstream/feat/path-only-app-hrefs` (upstream-PR-bound, separate concern) |
| `halos-org/halos-core-containers` | Ships the `docker-compose.yml` that pins the Homarr image | `main` (production pin), `dev/homarr-fork` (dev/test pin), feature branch off `main` for the promotion PR |
| `halos-org/halos` | Workspace; documentation lives here | usually `main` for runbook/plan updates |

The two repos are git submodules (or sibling clones) under the workspace root: `homarr/` and `halos-core-containers/`.

## Mental model

- **Two parallel branches in the fork**, easy to confuse:
  - `feat/path-only-app-hrefs` = production-build (4 commits: CI infra + path-only feat + 2 docs commits, has `FORK.md` and `deployment-fork-image.yml`). **This is what you rebase and tag.**
  - `upstream/feat/path-only-app-hrefs` = upstream-PR-bound (2 commits: feat + DeepSource test silencing). **Don't touch from this runbook.** It has its own life cycle synchronized with the upstream PR.
- **Single source-controlled `docker-compose.yml`** in `halos-core-containers`. The dev-vs-prod split is by **branch**, not by file. The deeper `debian/halos-core-containers/var/lib/.../docker-compose.yml` path you might see in a built tree is a build artifact created by `debian/rules`' `override_dh_auto_install`, which copies the single working-tree compose into the package staging directory.
- **Fork CI triggers on tag push** matching `v*-halos.*`. Workflow: `homarr/.github/workflows/deployment-fork-image.yml`. Output: `ghcr.io/hatlabs/homarr:<tag>` (multi-arch: `linux/amd64`, `linux/arm64`) plus the moving `latest-halos` tag.
- **Tag scheme** (per `FORK.md` in fork): `v<upstream>-halos.<n>`, where `<n>` resets on each upstream rebase. So a clean rebase onto `v1.61.0` produces `v1.61.0-halos.1`. A follow-up patch on the same upstream base would be `v1.61.0-halos.2`.

---

## Pre-execution verification

Run these checks **before** any externally-visible action. Any mismatch → halt, investigate, update plan/runbook before proceeding.

```bash
# Workspace root
cd ~/w/hatlabs/halos/halos

# 1. Fork repo structure is intact
git -C homarr branch -a | grep path-only-app-hrefs
# Expect: both feat/path-only-app-hrefs and upstream/feat/path-only-app-hrefs (and their hatlabs/ remotes)

# 2. Production-build branch is at the tip you expect
git -C homarr log --oneline -4 feat/path-only-app-hrefs
# Expect: 4 commits — last "docs(fork): capture widget conditional tRPC error-handling pattern",
# bottom "ci(fork): add hatlabs fork docker image build pipeline" — on top of the previous v<x.y.z>
# upstream release boundary.

# 3. Fork CI workflow exists and triggers on the right tag pattern
grep -A4 "^on:" homarr/.github/workflows/deployment-fork-image.yml
# Expect: tags include 'v*-halos.*'

# 4. Single source-controlled docker-compose.yml in halos-core-containers
find halos-core-containers -maxdepth 2 -name docker-compose.yml -not -path '*/node_modules/*'
# Expect: exactly one path: halos-core-containers/docker-compose.yml

# 5. debian/rules copies that single compose into the package
grep -n "docker-compose.yml" halos-core-containers/debian/rules
# Expect: install -D -m 644 docker-compose.yml debian/$(PKG_NAME)$(LIB_DIR)/docker-compose.yml

# 6. main branch has the upstream pin, dev/homarr-fork has the fork pin
git -C halos-core-containers fetch origin main dev/homarr-fork 2>&1 | tail -3
git -C halos-core-containers show origin/main:docker-compose.yml | grep -nE "homarr:|hatlabs/homarr|homarr-labs/homarr"
git -C halos-core-containers show origin/dev/homarr-fork:docker-compose.yml | grep -nE "homarr:|hatlabs/homarr|homarr-labs/homarr"
# Expect: main pins ghcr.io/homarr-labs/homarr:v<upstream>; dev/homarr-fork pins ghcr.io/hatlabs/homarr:v<upstream>-halos.<n>
```

If anything is off, do not proceed. The most common drift is the production-build branch advancing without the runbook reflecting new commits — re-read the actual `git log` and update the expected-state above.

---

## Step 1: Decide the new base and target tag

Pick the upstream release tag to rebase onto:

```bash
# Upstream release tags (released, not pre-release)
git -C homarr fetch origin --tags 2>&1 | tail -3
git -C homarr tag --list 'v[0-9]*' --sort=-creatordate | head
```

Decisions:

- Use a **release tag** (`vX.Y.Z`), not `origin/dev` and not a `-beta.` tag. Production wants the same release boundary other Homarr operators run.
- Skip beta tags unless a critical fix lives only there; revisit case-by-case if so.
- The new fork tag is `v<upstream>-halos.1` — counter resets on every upstream rebase per `FORK.md`.

Capture in your notes:

```
UPSTREAM_NEW=v1.61.0           # whatever you picked
HALOS_TAG=${UPSTREAM_NEW}-halos.1
```

---

## Step 2: Sanity-check the rebase will be clean

Before touching the branch, verify the patched feature files have no upstream changes between the current fork base and the new upstream tag.

```bash
# The four files the path-only-href patch touches
PATCH_FILES="packages/validation/src/app.ts
packages/widgets/src/bookmarks/component.tsx
packages/api/src/router/widgets/app.ts
packages/request-handler/src/lib/cached-request-integration-job-handler.ts"

# Find the current fork base (parent of the bottom halos commit)
CUR_BASE=$(git -C homarr log feat/path-only-app-hrefs --format='%H' | tail -5 | head -1)
echo "Current fork base: $CUR_BASE"

# Diff scope: feature files, between current base and new upstream tag
git -C homarr diff --stat $CUR_BASE..$UPSTREAM_NEW -- $PATCH_FILES
# Expect: empty output (no upstream changes to the patched files). If non-empty, inspect:
git -C homarr diff $CUR_BASE..$UPSTREAM_NEW -- $PATCH_FILES
```

Also pre-inspect what upstream changed in the CI workflow files, since the fork commit `ci(fork): add hatlabs fork docker image build pipeline` modifies two of them.

```bash
git -C homarr diff --stat $CUR_BASE..$UPSTREAM_NEW -- \
  .github/workflows/deployment-docker-image.yml \
  .github/workflows/deployment-weekly-release.yml
# Expect: small line counts. Inspect the diff if you want to know in advance whether
# the rebase will conflict on these two files. Often it will not — git's three-way merge
# resolves cleanly when upstream's edits and the fork's `if:` guard are on different lines.
```

---

## Step 3: Rebase the production-build branch

```bash
cd ~/w/hatlabs/halos/halos/homarr

# Pre-rebase backup tag (locally, not pushed) — lets you reset cleanly if anything goes wrong
git tag backup/feat-path-only-app-hrefs-pre-${UPSTREAM_NEW}-rebase feat/path-only-app-hrefs

git checkout feat/path-only-app-hrefs
git rebase $UPSTREAM_NEW
```

**If a conflict surfaces in `.github/workflows/deployment-docker-image.yml` or `deployment-weekly-release.yml`** (CI commit replaying):
- Accept upstream's version of the file in full.
- Re-add the fork's `if: github.repository == 'homarr-labs/homarr'` line at the same position (just under `runs-on: ubuntu-latest` for the relevant job in each file).
- `git diff` against the pre-rebase tip should show only that one line plus any upstream edits.
- `git add` the resolved files, `git rebase --continue`.

**If a conflict surfaces in any of the four feature files**: stop. Don't auto-resolve. Read the upstream change carefully — the path-only-href patch may need to adapt to upstream's restructure. This is the case where the runbook becomes "human judgment required".

After rebase succeeds, sanity-check:

```bash
# Exactly 4 halos commits on top of the new upstream base
git log --oneline ${UPSTREAM_NEW}..HEAD | wc -l
# Expect: 4

# Workflow guards survived
grep -nE "if: github.repository == 'homarr-labs/homarr'" \
  .github/workflows/deployment-docker-image.yml \
  .github/workflows/deployment-weekly-release.yml
# Expect: one match in each file

# Fork-specific files are present
ls .github/workflows/deployment-fork-image.yml FORK.md

# Feature files unchanged across rebase
git diff backup/feat-path-only-app-hrefs-pre-${UPSTREAM_NEW}-rebase HEAD -- $PATCH_FILES
# Expect: empty output
```

Run the path-only-href validation tests on the rebased tree (run from the **homarr repo root**, not the package dir):

```bash
cd ~/w/hatlabs/halos/halos/homarr
npx vitest run packages/validation/src/test/app.spec.ts
# Expect: 33 tests passed (or whatever the current count is — should match pre-rebase)
```

A workspace-level `pnpm install` against the new upstream lockfile may be required for full typecheck to run locally; the Docker image build does its own fresh install, so a stale local typecheck is not a blocker for the rebase itself.

---

## Step 4: Force-push the rebased branch

This is the first externally-visible action. **Get explicit human approval before running.**

```bash
cd ~/w/hatlabs/halos/halos/homarr
git push --force-with-lease hatlabs feat/path-only-app-hrefs
```

`--force-with-lease` is the right flavor of force-push: it refuses if someone else pushed to the branch since you last fetched, preventing accidental clobber.

---

## Step 5: Tag and trigger the fork image build

```bash
git tag -a $HALOS_TAG -m "halos.1 on top of upstream $UPSTREAM_NEW

Carries the path-only-href patch (plus fork CI infra and docs) for HaLOS
multi-hostname support while upstream PR homarr-labs/homarr#5595 is in flight."

git push hatlabs $HALOS_TAG
```

The push triggers `deployment-fork-image.yml`. Watch:

```bash
sleep 8
gh run list --repo hatlabs/homarr --limit 5 \
  --json databaseId,status,conclusion,name,event,createdAt
# Look for: "[Fork] Build & publish HaLOS image" with event=push, status=queued/in_progress/completed
```

Watch the run to completion (typical duration: 3–5 minutes for multi-arch build):

```bash
RUN_ID=<the databaseId from above>
gh run watch $RUN_ID --repo hatlabs/homarr --exit-status
```

Verify the published image:

```bash
docker manifest inspect ghcr.io/hatlabs/homarr:$HALOS_TAG | head -25
# Expect: schemaVersion 2, mediaType ...image.index..., manifests for amd64 and arm64
```

If the run failed: inspect with `gh run view $RUN_ID --repo hatlabs/homarr --log-failed`. Transient failures (registry/auth) → re-run via `workflow_dispatch`. Build failures → likely something in the rebased tree; iterate at Step 3, then re-tag (still `-halos.1` until something releases).

---

## Step 6: Smoke-test on a HaLOS device

Use the in-place compose-swap pattern, not a full `.deb` build. Full pattern is documented in `docs/solutions/best-practices/2026-05-04-image-swap-smoke-test-without-deb-rebuild.md`. Quick version:

```bash
cd ~/w/hatlabs/halos/halos/halos-core-containers

# Smoke-test branch off dev/homarr-fork (so any unmerged dev-only changes come along)
git fetch origin dev/homarr-fork
git checkout -b smoke/homarr-${HALOS_TAG} origin/dev/homarr-fork

# Edit the pin in the working tree
sed -i '' "s|ghcr.io/hatlabs/homarr:v[0-9.]*-halos\.[0-9]*|ghcr.io/hatlabs/homarr:${HALOS_TAG}|" docker-compose.yml
grep -n "hatlabs/homarr" docker-compose.yml

# Stage on device, back up the deployed compose, swap
DEV_HOST=halosdev.local
scp docker-compose.yml ${DEV_HOST}:/tmp/docker-compose.yml
ssh ${DEV_HOST} "
  sudo cp /var/lib/container-apps/halos-core-containers/docker-compose.yml \
          /var/lib/container-apps/halos-core-containers/docker-compose.yml.bak &&
  sudo cp /tmp/docker-compose.yml \
          /var/lib/container-apps/halos-core-containers/docker-compose.yml &&
  grep -n homarr: /var/lib/container-apps/halos-core-containers/docker-compose.yml
"

# Pre-pull (keeps the restart window short)
ssh ${DEV_HOST} "sudo docker pull ghcr.io/hatlabs/homarr:${HALOS_TAG}"

# Restart via systemd (NEVER docker restart directly — workspace memory)
ssh ${DEV_HOST} "sudo systemctl restart halos-core-containers.service"

# Wait for stack health
sleep 12
ssh ${DEV_HOST} "sudo docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}' | grep homarr"

# Confirm DB migration ran cleanly
ssh ${DEV_HOST} "sudo docker logs homarr 2>&1 | head -80"
# Look for: 'Running DB migrations', 'Migration complete', no errors, no 'Invalid URL', no TypeError

# Smoke-walk the path-only-href surface
ssh ${DEV_HOST} "
  curl -ks https://localhost/ -H 'Host: ${DEV_HOST}' -o /dev/null -w 'main host: HTTP %{http_code}\n'
  curl -ks https://localhost/ -H 'Host: ${DEV_HOST%.*}' -o /dev/null -w 'short host: HTTP %{http_code}\n'
  sudo apt-get install -y sqlite3 >/dev/null 2>&1 || true
  sudo sqlite3 /var/lib/container-apps/halos-core-containers/data/homarr/data/db/db.sqlite \
    'SELECT name, href FROM app ORDER BY name;'
"
# Expect: HTTP 200 from both hostnames; mix of path-only and absolute hrefs in the apps list,
# nothing rejected by the schema on read, no errors in the recent docker logs.
```

If the dataset has no bookmarks widgets, recommend the human do a quick browser walk-through to exercise that path. Optionally interactively confirm an admin-UI edit/save on a path-only-href app to exercise `appEditSchema` on the write path.

**Rollback** if anything looks wrong:

```bash
ssh ${DEV_HOST} "
  sudo cp /var/lib/container-apps/halos-core-containers/docker-compose.yml.bak \
          /var/lib/container-apps/halos-core-containers/docker-compose.yml &&
  sudo systemctl restart halos-core-containers.service
"
```

---

## Step 7: Open the production-promotion PR

Branch off **`main`** (not `dev/homarr-fork`).

```bash
cd ~/w/hatlabs/halos/halos/halos-core-containers
git checkout main
git pull --ff-only origin main

git checkout -b feat/homarr-promote-${HALOS_TAG}-to-prod

# Single-line pin edit
sed -i '' "s|ghcr.io/homarr-labs/homarr:v[0-9.]*|ghcr.io/hatlabs/homarr:${HALOS_TAG}|" docker-compose.yml
grep -n "hatlabs\|homarr-labs" docker-compose.yml

git add docker-compose.yml
git commit -m "$(cat <<EOF
feat(homarr): promote fork ${HALOS_TAG} to production

Switches the Homarr image from upstream ghcr.io/homarr-labs/homarr:<old>
to the hatlabs fork ghcr.io/hatlabs/homarr:${HALOS_TAG} as an interim
measure while upstream PR homarr-labs/homarr#5595 (path-only app hrefs)
is in flight.

Smoke-tested on ${DEV_HOST}: clean v1.X.Y DB migration, healthy
container, dashboard reachable across multiple Host headers, adapter
syncs successfully via tRPC.
EOF
)"
```

Bump the version (per workspace policy: package-affecting change requires a bump):

```bash
# Confirm clean tree first
git status -sb
bumpversion patch
# This commits the VERSION bump as a separate commit. Do NOT use --allow-dirty.
git log --oneline -3
```

Push the branch and open the PR via the authorized script:

```bash
git push -u origin feat/homarr-promote-${HALOS_TAG}-to-prod

~/.claude/scripts/create-pr \
  --repo halos-org/halos-core-containers \
  --base main \
  --head feat/homarr-promote-${HALOS_TAG}-to-prod \
  --title "feat(homarr): promote fork ${HALOS_TAG} to production" \
  --body "$(cat <<'EOF'
## Summary
[copy from prior PR halos-org/halos-core-containers#127, adjusting tag]
## Smoke test
[smoke-test evidence from Step 6]
## Post-Deploy Monitoring & Validation
[mandatory section — see PR #127 for shape]

⚠️ Production-impact: do not auto-merge. Explicit human approval gates merge.
EOF
)"
```

Past PR for reference: halos-org/halos-core-containers#127.

CI must be green; do not auto-merge — explicit human approval gates merge.

---

## Step 8: Watch APT publishing after merge

After the PR merges to `main`:

```bash
# halos-core-containers builds the .deb and dispatches to apt.halos.fi
gh run list --repo halos-org/halos-core-containers --limit 3 \
  --json databaseId,status,conclusion,name

# Then the apt-side workflows run
gh run list --repo halos-org/apt.halos.fi --limit 5 \
  --json databaseId,status,conclusion,name
# Wait for both "Update APT Repository" and "pages build and deployment" to complete green
```

Verify on a real device:

```bash
ssh ${DEV_HOST} "sudo apt update && sudo apt upgrade -y halos-core-containers"
ssh ${DEV_HOST} "sudo docker ps --format '{{.Image}}' | grep homarr"
# Expect: ghcr.io/hatlabs/homarr:${HALOS_TAG}
```

---

## Step 9: Catch up `dev/homarr-fork`

After production promotion lands, fast-forward (or rebase) `dev/homarr-fork` onto `main` so the dev/test branch matches the new production base. The branch-based dev/prod split re-establishes only when the *next* fork iteration lands.

```bash
cd ~/w/hatlabs/halos/halos/halos-core-containers
git fetch origin
git checkout dev/homarr-fork
git pull --ff-only origin dev/homarr-fork

# If dev/homarr-fork has additional dev-only commits not on main, rebase:
git rebase origin/main

# If dev/homarr-fork has nothing extra (it had only the prior fork pin which is now on main):
# the simplest thing is to reset dev/homarr-fork to main directly.
# This requires explicit user approval (force-push to a shared branch).
```

---

## Rollback (if a regression appears in production)

The production-promotion PR is reversible by a single revert PR:

```bash
cd ~/w/hatlabs/halos/halos/halos-core-containers
git checkout main
git pull --ff-only origin main

git checkout -b revert/homarr-promote-${HALOS_TAG}
sed -i '' "s|ghcr.io/hatlabs/homarr:${HALOS_TAG}|ghcr.io/homarr-labs/homarr:<previous-upstream-tag>|" docker-compose.yml
git add docker-compose.yml
git commit -m "revert(homarr): rollback to upstream <previous-upstream-tag>"
bumpversion patch
git push -u origin revert/homarr-promote-${HALOS_TAG}

# PR via authorized script, ship through APT
```

**Operational caveat documented in the original promotion plan**: rollback re-introduces the bookmarks-widget render crash for users with path-only entries (because the upstream image's `bookmarks/component.tsx` calls `new URL(app.href).hostname` which throws on path-only inputs), and the admin UI rejects path-only-href apps on edit/save. Rollback is therefore a production-stability action, not a transparent revert. Coupled rollback (also reverting the adapter to write absolute hrefs) is a much larger operation and is not covered by this runbook.

---

## When this runbook should be retired

When upstream PR [homarr-labs/homarr#5595](https://github.com/homarr-labs/homarr/pull/5595) merges AND a stable upstream Homarr release contains it:

1. The production pin can move back to `ghcr.io/homarr-labs/homarr:<that-stable-release>`.
2. The fork's path-only-href commits become redundant; the fork branch can be reset to upstream + (potentially) any *new* fork-only patch surface.
3. The `latest-halos` image tag can stop moving.

A separate "retire-the-fork" runbook should be written when that day comes. Until then, this runbook is the authoritative procedure for keeping production on a clean upstream release boundary while the upstream PR is in flight.

---

## Related docs

- `docs/plans/2026-05-04-001-feat-promote-homarr-fork-to-production-plan.md` — the original plan (corrected mid-execution); useful for reading the decision rationale.
- `docs/solutions/best-practices/2026-05-04-verify-plan-against-repo-state-before-execution.md` — the broader principle this runbook's pre-execution verification block embodies.
- `docs/solutions/best-practices/2026-05-04-image-swap-smoke-test-without-deb-rebuild.md` — full detail on the Step 6 smoke-test pattern.
- `docs/solutions/best-practices/2026-04-30-skip-apt-depends-pins-sibling-halos-packages.md` — adjacent decision on cross-package coupling, same plan family.
- Upstream PR: [homarr-labs/homarr#5595](https://github.com/homarr-labs/homarr/pull/5595).
- Reference PR: [halos-org/halos-core-containers#127](https://github.com/halos-org/halos-core-containers/pull/127) — the first execution of this procedure.
- Fork conventions: `FORK.md` in `hatlabs/homarr` — tag scheme, workflow guards, branch separation.
