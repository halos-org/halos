---
title: "feat: Path-only icon URLs for Signal K-discovered Homarr cards"
type: feat
status: active
date: 2026-05-14
origin: docs/plans/2026-04-29-001-feat-homarr-path-only-card-urls-plan.md
---

# feat: Path-only icon URLs for Signal K-discovered Homarr cards

## Overview

Continue Phase 4 of the multi-hostname Homarr work by converting dynamically-discovered Signal K webapp `icon_url`s from absolute (`https://<host>.local/signalk-server/<pkg>/<icon>`) to path-only (`/signalk-server/<pkg>/<icon>`). Adapter-only change in `homarr-container-adapter/src/signalk.rs::build_icon_url`. No Homarr fork or upstream PR amendment required — verified that `appManageSchema.iconUrl` is `z.string().trim().min(1)` with no URL validation, and every consumer feeds the value straight into a browser `<img src>` / `<Avatar src>` where relative paths resolve against the current origin natively.

## Problem Frame

The path-only-card-urls plan ([2026-04-29-001](2026-04-29-001-feat-homarr-path-only-card-urls-plan.md)) explicitly scoped out icon URL conversion (Scope Boundaries §53; Implementation Unit 4 §406) under the assumption that "same-origin browser loading makes path-only icons code-cleanliness-only." That assumption fails the moment a user reaches the dashboard via a non-`.local` hostname:

- Dashboard SPA loads from `https://halosdev.hal/`.
- Card `<img src="https://halosdev.local/signalk-server/.../icon.png">` is cross-origin.
- `halosdev.local` doesn't resolve in the user's network context (or hits a cert SAN mismatch), so all dynamic Signal K card icons render broken.

Verified on `halosdev.local` after deploying the current Selene image:

```
App Dock           /signalk-server/@signalk/app-dock/         https://halosdev.local/signalk-server/@signalk/app-dock/app-icon.svg
Freeboard-SK       /signalk-server/@signalk/freeboard-sk/     https://halosdev.local/signalk-server/@signalk/freeboard-sk/assets/icons/icon-72x72.png
Instrumentpanel    /signalk-server/@signalk/instrumentpanel/  https://halosdev.local/signalk-server/@signalk/instrumentpanel/icons/instrumentpanel-72x72.png
KIP Instrument MFD /signalk-server/@mxtommy/kip/              https://halosdev.local/signalk-server/@mxtommy/kip/assets/icon-72x72.png
```

Statically-registered cards (Cockpit, Signal K Server) already use Homarr-internal `/icons/...` paths and work everywhere — only the dynamic Signal K discovery path is affected.

## Requirements Trace

- **R1.** `build_icon_url` emits path-only (`/signalk-server/<pkg>/<icon>`), same scheme as the existing `build_webapp_url` and `build_ping_url`.
- **R2.** Existing dynamic Signal K cards stored with absolute `icon_url` are rewritten in place on next adapter sync (no duplicates, no orphans).
- **R3.** Admin-edited `icon_url` values are preserved (consistent with the parent plan's R11 admin-respect rule).
- **R4.** Static `icon_url` values shipped via `webapps.d/*.toml` are unchanged (they are already path-only `/icons/...`).

Success criteria:

- After upgrade, all four dynamic Signal K cards on a `halosdev` test device show path-only `icon_url` values in the Homarr DB.
- Card icons render correctly under both `https://halosdev.local` and `https://halosdev.hal` simultaneously.
- No duplicate apps; existing apps rewritten in place.
- Cards with an admin-edited icon URL (`type.external` semantics — TBD whether icon edits are tracked separately from href edits in the existing migration) keep the admin value.

## Scope Boundaries

In scope:
- `homarr-container-adapter/src/signalk.rs::build_icon_url` and its callers/tests.
- Adapter version bump and changelog entry.
- Verification that the existing adapter-side migration (Unit 6 of the parent plan) catches dynamic Signal K cards along with the static registry cards it already migrates.

Out of scope:
- Any Homarr fork or upstream PR change. Verified clean.
- Changes to `webapps.d/*.toml` icon paths (already path-only).
- Changes to `build_webapp_url` / `build_ping_url` (parent plan already converted these).
- IP-literal and single-label hostname access (out per parent plan §47).
- Admin-created cards outside the Signal K discovery path (out per parent plan §47).
- Cross-origin SSO across hostnames (out per parent plan §47).

## Verification recorded during planning (2026-05-14)

- **Homarr `iconUrl` validation accepts path-only.** `homarr/packages/validation/src/app.ts:75` defines `iconUrl: z.string().trim().min(1)`. No URL parsing, no scheme requirement, no leading-slash check. Any non-empty string is accepted, including `/signalk-server/.../icon.png`. Confirmed across both `appManageSchema` and `appCreateManySchema` (line 88 — nullable variant; same minimal validation).
- **All `iconUrl` consumers are browser-side `<img src>` / `<Avatar src>`.** Audited `homarr/packages/widgets/src/app/component.tsx:39,115`, `packages/widgets/src/bookmarks/component.tsx:220,260`, `packages/widgets/src/bookmarks/app-select-modal.tsx:88-89,108`, `packages/widgets/src/bookmarks/index.tsx:35`, `packages/widgets/src/bookmarks/add-button.tsx`. No server-side consumer of `iconUrl` exists in Homarr today; the value never gets `URL.parse`d server-side. Path-only resolves against page origin via standard HTML semantics.
- **Upstream PR [homarr-labs/homarr#5595](https://github.com/homarr-labs/homarr/pull/5595) does not need amendment.** The PR scope is `appHrefSchema`, `resolveServerUrl`, ping widget, integration middleware, bookmarks sub-label — none of which touch `iconUrl`. Adding icon-URL scope to that PR would expand a single-purpose PR with unrelated changes; rejected.
- **Adapter migration path covers dynamic cards.** Existing migration code in `homarr-container-adapter/src/homarr.rs` keys cards by `apps_by_url` (the path-only `href`), not by `icon_url`. Since dynamic Signal K cards already have path-only `href` values shipped by the parent plan, the next sync's `app.update` call will rewrite `icon_url` along with any other drift. To be re-confirmed in Unit 2 — if `app.update` is currently elided when only `icon_url` drifts (e.g., a hash-based dirty check), the migration logic needs a narrow extension.

## Key Technical Decisions

- **Adapter-only fix; no Homarr changes.** The parent plan's icon-out-of-scope decision was based on an assumption (same-origin browser loading) that holds only on the access path the plan was originally validated against (`.local` only). Multi-hostname access invalidates that assumption. The fix lives in the same code that the parent plan touched for `build_webapp_url` — natural co-location.
- **Migration relies on existing `app.update` semantics, not new code.** The parent plan's Unit 6 already migrates dynamic cards by `apps_by_url` keying. If `icon_url` drift alone doesn't trigger an update, we extend the dirty-check rather than write a new migration. Avoids double-coverage.
- **No iconUrl schema relaxation needed.** Homarr already accepts arbitrary non-empty strings — verified above. This means no fork patch, no upstream review wait, no risk of upstream rejection blocking deployment.

## High-Level Technical Design

### `build_icon_url` change

Current: `build_icon_url(domain, package, icon_path) -> https://<domain>/signalk-server/<package>/<icon>`

New: `build_icon_url(package, icon_path) -> /signalk-server/<package>/<icon>`

The `domain` parameter is dropped (no longer needed). All callers in `signalk.rs` lose the `get_domain(&self)` call when constructing icon URLs; the per-request hostname disappears from the icon emit path entirely. Matches the shape of `build_webapp_url` and `build_ping_url` already in this file.

### Migration coverage

On adapter restart after upgrade:
1. Sync runs against Signal K's discovery endpoint as today.
2. For each discovered webapp, a candidate card record is built — now with path-only `icon_url`.
3. Existing card lookup keyed by `apps_by_url` finds the stored card (`href` is already path-only post-parent-plan).
4. The card is compared against the candidate. If `icon_url` differs, `app.update` is invoked.
5. Stored card is rewritten in place. No duplicate.

The unknown: whether step 4's diff includes `icon_url` today. If it doesn't (e.g., only `name`/`description`/`href` are compared), we add `icon_url` to the diff. This is the single open question to resolve during Unit 2.

## Implementation Units

### Unit 1: Adapter code change + unit tests

**Goal:** `build_icon_url` returns path-only; tests updated to match.

**Files modified:**
- `homarr-container-adapter/src/signalk.rs` — `build_icon_url` signature and body; all in-file callers.
- `homarr-container-adapter/src/signalk.rs` test module — update expected values from `https://<domain>/...` to `/...`.

**Test expectations:**
- Existing `signalk.rs` test that asserts the icon URL shape now asserts path-only.
- A new test case exercising the build helper with a representative Signal K package name and icon path, asserting exact path-only output.
- No test should reference `<domain>` for icon construction after this unit.

**Pattern to follow:** `build_webapp_url` and `build_ping_url` in the same file. Their existing path-only forms are the model.

**Verification:** `cargo test` in `homarr-container-adapter` passes; no other test file touches `build_icon_url` (verified by grep).

### Unit 2: Verify and (if needed) extend migration dirty-check

**Goal:** Confirm that on next sync after upgrade, existing cards with absolute `icon_url` get rewritten via `app.update`. Extend the dirty-check if not.

**Files inspected:**
- `homarr-container-adapter/src/homarr.rs` — locate the per-card diff/dirty-check that decides whether to invoke `app.update`.

**Possible outcomes:**
- **A.** `icon_url` already participates in the diff. No code change; document the result in this plan's "Resolved during implementation" section.
- **B.** `icon_url` is not in the diff. Add it; add a unit test covering the icon-only-drift case.

**Test expectations (case B):**
- Unit test: stored card with absolute `icon_url`, candidate with path-only `icon_url`, all other fields identical → diff returns dirty.
- Integration-style test (if one exists for the sync path): assert `app.update` is invoked with the path-only `icon_url`.

**Verification on test device after rollout:** ssh to `halosdev.local`, copy out the Homarr DB, sqlite-query the `app` table for the four dynamic Signal K cards, confirm `icon_url` is path-only. Then load the dashboard via `https://halosdev.local` *and* `https://halosdev.hal`, visually confirm icons render in both.

### Unit 3: Version bump + ship

**Goal:** Standard adapter version bump and package release flow.

**Files modified:**
- `homarr-container-adapter/VERSION`
- `homarr-container-adapter/debian/changelog` — via `bumpversion`, not direct edit (per workspace AGENTS.md).

**Verification:** PR opens; CI passes; APT pipeline publishes; device upgrade rewrites cards on next sync.

## Open Questions

### Resolved during planning

- **Does icon URL conversion require a Homarr / upstream PR change?** No. Verified `iconUrl` schema is `z.string().trim().min(1)` and all consumers are browser-side `<img>` sources. Adapter-only fix.
- **Does PR #5595 need amendment?** No. Scope is `href` and ping/integration plumbing; icons were never in scope. Adding icon scope would broaden a focused PR with no upstream-correctness benefit.

### Deferred to implementation

- **Does the existing adapter migration dirty-check include `icon_url`?** Resolved in Unit 2.
- **Are there admin-edit-preservation semantics for `icon_url` that mirror the existing href edit-preservation?** Inspect during Unit 2; if `icon_url` admin edits are not tracked today, decide whether to track them now or accept overwrite for HaLOS-discovered cards (the latter matches today's behavior for other fields, so probably fine).

## Risks

- **Risk:** Adapter migration overwrites an admin-customized `icon_url` on first sync after upgrade. **Mitigation:** Unit 2 inspects the existing edit-preservation semantics and either inherits them or documents the behavior. If admin icon edits aren't tracked today, this is a no-regression change. If they are, we inherit the same gate.
- **Risk:** A Signal K webapp's icon is served only via the absolute URL form (e.g., behind a different reverse-proxy path). **Mitigation:** Inspect Signal K's webapp manifest spec — icons are conventionally relative to the package root and served by Signal K through its standard `/signalk-server/<pkg>/...` mount. The same Traefik route that handles `build_webapp_url` carries icon requests.
- **Risk:** Future Homarr upstream version tightens `iconUrl` validation to require absolute URLs. **Mitigation:** Track via the docs PR planned in the parent plan; if upstream tightens, the schema relaxation pattern from PR #5595 transfers cleanly to `iconUrl`. Not a blocker for this work.
