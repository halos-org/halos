---
title: Skip APT Depends pins between sibling HaLOS packages when graceful skip and cohort upgrade cover the failure mode
date: 2026-04-30
category: best-practices
module: debian-packaging
problem_type: best_practice
component: tooling
severity: medium
applies_when:
  - A HaLOS package contract change requires a newer version of a sibling package
  - Both sibling packages publish to the same APT repository and upgrade in the same cohort
  - The consumer fails gracefully on an unrecognized contract (logs and skips, does not crash)
  - A runtime probe or version detection makes the consumer self-correcting on next sync
  - Considering adding `Depends: <sibling> (>= X.Y.Z)` to debian/control
tags:
  - apt
  - debian-packaging
  - depends-pin
  - package-coupling
  - graceful-degradation
  - halos
  - cohort-upgrade
---

# Skip APT Depends pins between sibling HaLOS packages when graceful skip and cohort upgrade cover the failure mode

## Context

Cross-package contract changes between sibling HaLOS packages — where one package's data format or API now requires a newer version of another — invite a reflexive `Depends: <sibling> (>= X.Y.Z)` line in `debian/control`. The instinct is sound when failure means crashes or corrupted state, but it is overkill when the system already has built-in defences against version skew. PR halos-org/halos-cockpit-config#30 surfaced this: the planned pin on `homarr-container-adapter (>= 0.4.6)` was dropped after re-analysis showed all three protective layers were already in place, making the pin pure coupling without safety benefit.

## Guidance

Before adding a `Depends: <sibling> (>= X.Y.Z)` pin to `debian/control`, evaluate these three layers of defence:

1. **Cohort upgrade** — both packages publish to the same APT repo (`halos-org/apt.halos.fi` or `hatlabs/apt.hatlabs.fi`) and upgrade together in a single `apt upgrade` run. A version-skew window exists only for seconds inside one dpkg transaction.
2. **Graceful skip in older consumers** — the consumer encounters the unrecognized form (e.g., parse error), logs a clear warning, and continues. The visible effect is a temporary, recoverable degradation (a missing tile, a deferred feature) — not a crash, data loss, or broken device.
3. **Runtime probe / capability detection** — the consumer can detect at runtime whether its peer supports the new contract and self-correct on the next sync.

**If at least 2 of 3 layers are present, the pin is redundant. Drop it.**

The shipped form:

```
Package: halos-cockpit-config
...
Depends: ${misc:Depends},
         cockpit
```

No `homarr-container-adapter` line. The version requirement lives in the package's PR description, not in metadata.

## Why This Matters

An unnecessary pin imposes durable costs:

- **Metadata coupling** — two packages that were otherwise independently releasable now ship together. A bugfix-only release of the producer is blocked behind any unrelated stale pin.
- **Bookkeeping debt** — every future contract evolution must be reflected in the dependent's `debian/control`, or the pin drifts out of sync with reality and either over-constrains (rejecting compatible versions) or under-constrains (failing to gate breaking changes).
- **Loss of cohort flexibility** — the implicit assumption that "everything in this APT repo upgrades together" is broken; one package now waits on another's version bump even when the change doesn't affect the contract.

When a pin is genuinely needed and missing, the failure mode is typically a brief, visible degradation in cohort scenarios. Outside cohort scenarios (mixed channels, manual partial upgrades), a missing pin can cause prolonged broken state — that is when pins earn their cost.

## When to Apply

**Drop the pin when:**

- All 3 layers present, or any 2 of cohort upgrade + graceful skip + runtime probe.
- Consumer fails gracefully on unrecognized input — warn-and-continue, not crash or corrupt.
- Consumer and producer ship from the same APT cohort (`halos-org/apt.halos.fi` or `hatlabs/apt.hatlabs.fi`).
- The degradation window is short, visible, and recoverable.

**Keep the pin when:**

- Consumer crashes, deadlocks, or corrupts state on unrecognized input.
- Failure mode is silent (data corruption, security bypass, irreversible migration).
- Packages ship through different channels (one APT, one Docker image, one tarball) — APT-level pinning doesn't even reach the actual peer in this case; use a runtime probe instead.
- The producer is deliberately released independently of the consumer (e.g., emergency patch trains).
- Manual partial upgrades are an expected operational pattern.

## Examples

**Originally planned (per implementation plan):**

```
Package: halos-cockpit-config
...
Depends: ${misc:Depends},
         cockpit,
         homarr-container-adapter (>= 0.4.6)
```

**Shipped in PR halos-org/halos-cockpit-config#30:**

```
Package: halos-cockpit-config
...
Depends: ${misc:Depends},
         cockpit
```

The consumer's graceful-skip behaviour lives in `homarr-container-adapter`'s `src/registry.rs::load_all_apps`:

```rust
match load_app_file(&path) {
    Ok(app) => entries.push(RegistryEntry { file_path: path, app }),
    Err(e) => {
        tracing::warn!("Failed to load app from {:?}: {}", path, e);
        // Continue loading other files
    }
}
```

When `homarr-container-adapter < 0.4.6` encounters `url = "/cockpit/"`, `Url::parse` fails, the warning is logged, and the adapter continues. The visible effect: the Cockpit tile briefly disappears from the Homarr dashboard until the adapter package upgrades. Cockpit itself remains reachable at `:9090` and via the desktop shortcut. The runtime-probe layer (Unit 6 of the path-only-card-URLs plan) provides a third backstop for the adapter↔Homarr-container axis — relevant because that axis crosses APT and Docker channels, where APT pinning would not help anyway.

The PR description carries the version requirement (`requires homarr-container-adapter >= 0.4.6`) as documentation, not as a metadata constraint — operators see it during PR review and in the package's own release notes.

## Related

- [`2026-05-13-prefer-breaks-over-depends-for-partial-upgrade-gating.md`](2026-05-13-prefer-breaks-over-depends-for-partial-upgrade-gating.md) — companion guidance: when this doc's Keep-the-pin conditions fire (silent failure mode OR manual partial upgrades are an expected operational pattern), reach for `Breaks: peer (<< X)` rather than `Depends: peer (>= X)`. PR halos-org/container-packaging-tools#203 is the worked example.
- [`2026-05-13-shared-predicate-over-parallel-if-chains.md`](2026-05-13-shared-predicate-over-parallel-if-chains.md) — when a code generator auto-injects `Breaks:` lines (as CPT does for routed visible apps), the injection trigger must share its predicate with the contract-affected output trigger. Same review surfaced the drift.
- `docs/plans/2026-04-29-001-feat-homarr-path-only-card-urls-plan.md` — the multi-PR plan whose implementation surfaced this question; Unit 5 covers the `cockpit.toml` change, and Unit 6 (the adapter migration with version probe) is the runtime-probe layer.
- Workspace `AGENTS.md`, "APT Package Publishing Pipeline" section in MEMORY.md / "GitHub Organizations and APT Repositories" — describes the cohort-upgrade contract for `halos-org/apt.halos.fi` and `hatlabs/apt.hatlabs.fi`, which underwrites layer 1 of the test.
- PR halos-org/halos-cockpit-config#30 — the concrete case where the pin was added per plan, then dropped after re-analysis.
