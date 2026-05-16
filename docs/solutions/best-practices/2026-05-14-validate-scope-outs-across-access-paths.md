---
title: Validate scope-out decisions against every supported access path, not just the validation environment
date: 2026-05-14
category: best-practices
module: multi-hostname-access
problem_type: best_practice
component: tooling
severity: medium
applies_when:
  - A plan scopes out a concern based on an assumption that holds under one set of conditions but not all supported conditions
  - A fix narrows or widens an input-classification function (URL validator, path parser, content sniffer, etc.)
  - A fix's migration story depends on existing-but-incidental behavior that the change is now actively requiring
tags:
  - scope-out
  - assumption-trap
  - same-origin
  - multi-hostname
  - input-classification
  - migration-mechanism
  - homarr
  - traefik
  - halos
---

# Validate scope-out decisions against every supported access path, not just the validation environment

## Context

The [path-only-card-urls plan (2026-04-29)](../../plans/2026-04-29-001-feat-homarr-path-only-card-urls-plan.md) made Homarr card `href`s hostname-agnostic so cards work under every hostname a HaLOS device answers on (mDNS `.local`, VPN FQDN, DHCP-DNS short name). It explicitly scoped out icon URLs (Scope Boundaries §53; Implementation Unit 4 §406):

> Out of scope: converting Signal K icon URLs to path-only. `build_icon_url` is unchanged […]; same-origin browser loading makes path-only icons code-cleanliness-only and out of scope.

That call held under the access path the plan was validated against (`.local` only). Under any other hostname the device served — `https://halosdev.hal`, VPN FQDN, etc. — `<img src="https://halosdev.local/signalk-server/.../icon.png">` is cross-origin and fails to load. Two weeks later, every dynamic Signal K card on `halosdev` had broken icons under `.hal` access. The fix lived where the plan had said it didn't need to go: in `homarr-container-adapter` (PR halos-org/homarr-container-adapter#69), converting `build_icon_url` to path-only and widening `transform_icon_url` to pass any `/`-prefixed string through.

Three patterns from that work compound into general guidance for adjacent future decisions.

## Guidance

### 1. When a plan scopes out a concern, name the assumption *and* enumerate the access paths it depends on

If the rationale for scoping something out is "X is already safe because of Y", treat Y as a load-bearing assumption and write down the contexts under which Y holds. For the icon-URL case, the implicit "Y" was *"browser fetches are same-origin"* — true under same-hostname access, false under multi-hostname access. The plan validated against `halosdev.local`, where Y was trivially true, and never enumerated the other supported access paths.

A useful test before locking a scope-out:

> "What access paths, deployment topologies, or environment shapes must this assumption hold in? List them. For each, does the assumption hold today, and would a foreseeable change break it?"

If the answer is "I only validated under one shape," the scope-out is at most a deferral, not a closed decision. Document it as deferred and link the followup ticket — don't claim it's "out of scope."

### 2. When you widen an input-classification function, audit the previously-rejected set

`transform_icon_url` originally accepted only `http(s)://...`, `/icons/...`, and `/usr/share/pixmaps/...`. The icon-URL fix widened it to accept any `/`-prefixed input. The new generic branch:

```rust
if icon_path.starts_with('/') {
    return icon_path.to_string();
}
```

…also accepts `//host/path` — a protocol-relative URL that the browser fetches over the current scheme, leaking request metadata cross-origin. The CE review caught this; the fix is one extra clause:

```rust
if icon_path.starts_with('/') && !icon_path.starts_with("//") {
    return icon_path.to_string();
}
```

The general practice: when an accept-or-reject classifier moves a boundary, enumerate inputs that crossed the boundary in either direction and decide each one explicitly. Don't infer the new accept set from the new code — read it off the diff of the *old* and *new* sets. A widening commit and a test case for *each* newly-accepted input shape is cheaper than a security review catching the omission downstream.

### 3. When a fix's migration relies on existing behavior, that behavior becomes a constraint on future work

PR #69's migration story is: "the existing `update_registry_app` call pushes the full payload every sync, so absolute icon URLs get rewritten to path-only on the next pass — no migration code needed." That's correct, and it worked on rollout. But the pre-existing full-payload overwrite also silently destroys any admin-edited `iconUrl` (and `name`, `description`, `href`, `pingUrl`) every 5 minutes. PR #69 didn't introduce that — but it now actively *relies* on it.

The general practice: when a fix takes a free ride on existing-but-incidental behavior, write down the dependency. The behavior is no longer incidental; future work that tries to change it (e.g., "respect admin edits across syncs") now has to either preserve the migration path or stage a deliberate transition. The fix's PR description is the right place for this. CLAUDE.md and AGENTS.md are the right place if the dependency is repo-wide.

## Why This Matters

Each of these is a missed reviewer-catchable issue paid for downstream:

- **Scope-out trap** — the icon-URL bug surfaced in production-equivalent use the moment a test device was reached via a non-`.local` hostname. Cost: re-merge cycle, re-CI on adapter and downstream rebuild, redeploy.
- **Input-classification widening** — caught in CE review before merge, but only because the adversarial reviewer was instructed to construct failure scenarios. A reviewer pattern-matching against the existing code would have missed it.
- **Load-bearing incidental behavior** — surfaces when someone (months later) wants to "respect admin edits" and discovers their cleanup PR silently regresses a different feature's migration. Found by symptom, not by intent.

The recurring shape: a decision was correct under the conditions the author had in mind, and silently wrong under conditions that exist in the deployment. The instrumentation is "name the conditions, not just the conclusion."

## When to Apply

- Reviewing a plan's Scope Boundaries section. Each "out of scope" bullet either lists the conditions under which the deferral holds, or is suspect.
- Reviewing a diff that moves an accept/reject boundary in any classifier (URL validators, content type sniffers, ACL predicates, feature-flag evaluators). Look at the diff between *accepted inputs before* and *accepted inputs after*, not at the code shape.
- Reviewing a diff whose correctness or migration story includes "this works because [other component] already does X." Treat the other component's behavior as a load-bearing dependency and write down the coupling.
- Writing or reviewing a `ce:plan` document. Add a "Verifications" or "Assumptions" subsection that names the access paths / deployment shapes each decision validates against.

## Examples

### Scope-out with named conditions

Bad:

> Out of scope: converting icon URLs to path-only. Same-origin browser loading makes this code-cleanliness-only.

Better:

> Out of scope under same-hostname access (`.local` only). Holds because `<img src>` is same-origin in that case. **Deferred** for the multi-hostname access matrix (mDNS, VPN FQDN, DHCP-DNS) — tracked at [link]. Re-evaluate when multi-hostname Traefik lands.

### Input-classification widening audit

When `transform_icon_url` widened to `starts_with('/')`, the audit table that should have lived in the PR description:

| Input shape | Pre-widening | Post-widening | Decision |
|---|---|---|---|
| `/icons/foo.svg` | accept | accept | unchanged |
| `/signalk-server/X/icon.png` | reject (fallback to docker.svg) | accept | intentional widening |
| `/some/random.png` | reject (fallback) | accept | acceptable — 404 is no worse than placeholder |
| `//evil.com/x.png` | reject (fallback) | **accept** | **unintentional** — must reject explicitly |
| `bare-filename.png` | reject (fallback) | reject (fallback) | unchanged |

The `//evil.com` row is the one a generic "widen to accept paths" mental model loses.

### Load-bearing dependency in PR description

Bad:

> Migration is automatic via existing `update_registry_app` payload semantics.

Better:

> Migration depends on `update_registry_app` (`src/homarr.rs:966-1004`) unconditionally rewriting `iconUrl` every sync. That behavior is pre-existing but is now load-bearing for this change. Future work that introduces selective field preservation (e.g., respecting admin-edited `iconUrl` across syncs) must either keep the rewrite for app rows whose `iconUrl` is still an absolute legacy form, or stage a deliberate two-release migration.

## Related

- [Verify multi-repo release plans against actual repo state](2026-05-04-verify-plan-against-repo-state-before-execution.md) — same family of "validate the premise before acting on it" guidance, applied to plan-vs-reality drift rather than scope-out assumptions.
- [Skip APT Depends pins between sibling HaLOS packages](2026-04-30-skip-apt-depends-pins-sibling-halos-packages.md) — same family of "name the conditions under which the looser option is safe" reasoning, applied to package dependencies.
- PR [halos-org/homarr-container-adapter#69](https://github.com/halos-org/homarr-container-adapter/pull/69) — the fix that prompted this learning.
- Plan: [2026-05-14-001 path-only icon URLs](../../plans/2026-05-14-001-feat-homarr-path-only-icon-urls-plan.md).
- Original plan: [2026-04-29-001 path-only card hrefs](../../plans/2026-04-29-001-feat-homarr-path-only-card-urls-plan.md) (deleted in working tree as of 2026-05-14; check git history for the full scope-out wording).
