---
title: Prefer `Breaks: peer (<< X)` over `Depends: peer (>= X)` when gating against a partial-upgrade contract minimum
date: 2026-05-13
category: best-practices
module: debian-packaging
problem_type: best_practice
component: tooling
severity: medium
applies_when:
  - A HaLOS package contract change requires a newer version of a sibling package
  - The packages do not always upgrade in cohort (Cockpit App Store installs, manual `apt install <one-package>`, partial-upgrade scenarios)
  - The consumer side fails silently when the contract is violated (the workspace policy doc names this as a Keep-the-pin condition)
  - The peer is optional on devices that don't need the consumer surface (e.g., a marine device with container apps but no Homarr dashboard)
  - Choosing between `Depends:` and `Breaks:` in `debian/control`
tags:
  - apt
  - debian-packaging
  - breaks
  - depends-pin
  - partial-upgrade
  - package-coupling
  - halos
related:
  - 2026-04-30-skip-apt-depends-pins-sibling-halos-packages.md
---

# Prefer `Breaks: peer (<< X)` over `Depends: peer (>= X)` when gating against a partial-upgrade contract minimum

## Context

[`2026-04-30-skip-apt-depends-pins-sibling-halos-packages.md`](2026-04-30-skip-apt-depends-pins-sibling-halos-packages.md) defines a three-layer test for when to drop a `Depends:` pin between sibling HaLOS packages (cohort upgrade + graceful skip + runtime probe — drop the pin if at least two are present). It also lists Keep-the-pin conditions: *"Failure mode is silent (data corruption, security bypass, irreversible migration)"* and *"Manual partial upgrades are an expected operational pattern."*

The Keep clauses fire whenever a HaLOS package is installable à la carte — via the Cockpit App Store, a direct `apt install <one-package>`, or any flow that doesn't run a full `apt upgrade`. The original policy doc names the condition but stops short of recommending the Debian primitive that fits it. This doc is the companion: **when the Keep clauses fire, reach for `Breaks: peer (<< X)`, not `Depends: peer (>= X)`.**

The two primitives produce very different behaviour for the same goal of "the contract requires peer ≥ X":

| Primitive | When peer is installed at < X | When peer is installed at ≥ X | When peer is NOT installed |
|---|---|---|---|
| `Depends: peer (>= X)` | apt auto-upgrades the peer to satisfy | install succeeds | apt installs the peer first, even if the user didn't want it |
| `Breaks: peer (<< X)` | apt auto-upgrades the peer to satisfy *or* refuses with a clear message | install succeeds | install succeeds — no constraint applies |

The bottom-right cell is the decisive difference. `Depends:` over-constrains: a device that legitimately runs the producer without the consumer (e.g., Signal K-only marine box with no Homarr dashboard) is forced to install the consumer stack. `Breaks:` is conditional: it constrains the relationship only when the peer is already on the system. Debian Policy §7.4 documents `Breaks:` as exactly this — "this package cannot be installed at the same time as that older version of the named package."

## Guidance

**Use `Breaks: peer (<< MIN_VERSION)` when all of these are true:**

1. The producer-side change forces a contract minimum on a sibling package.
2. The sibling is operationally optional (some HaLOS variants don't ship it; users can install the producer without it).
3. The packages are installable individually (Cockpit App Store, raw `apt install`, etc.).
4. The consumer-side failure mode on contract violation is silent — a missing card, a dropped tile, a skipped registry entry — rather than a loud apt error.

**Use `Depends: peer (>= MIN_VERSION)` only when** the sibling is part of the minimum HaLOS install on every device that uses this producer. If the peer is always present anyway, `Depends:` and `Breaks:` produce identical apt behaviour; prefer `Depends:` only because it documents the structural relationship more obviously to a reader of `debian/control`.

**Use `Conflicts: peer` (no version) when** the relationship is fundamental incompatibility — two packages can never coexist regardless of version. `Conflicts:` is the wrong tool for a contract minimum because it would refuse the install forever, not just until the peer reaches the minimum.

**When the trigger is generator-driven, inject the `Breaks:` automatically.** If a code generator emits the contract-affected output (e.g., `container-packaging-tools` writes the Debian control file), drive both the contract-affected output and the `Breaks:` injection from the same predicate. PR halos-org/container-packaging-tools#203 uses `registry.emits_path_only_url(metadata)` as the shared predicate — same function gates both the path-only URL emission and the Breaks injection, so they cannot drift. (See the companion learning [`2026-05-13-shared-predicate-over-parallel-if-chains.md`](2026-05-13-shared-predicate-over-parallel-if-chains.md).)

## Why This Matters

The Keep-the-pin Skip-Depends-pins doc names the condition this guidance addresses but doesn't disambiguate the available tools. Three concrete costs of getting it wrong:

- **`Depends:` instead of `Breaks:`** forces the peer onto every device that touches the producer, even minimal installs. The peer's footprint (disk, services, attack surface) is now imposed system-wide. For HaLOS, this means a Signal K-only device gets the full Homarr stack just because it installed a Signal K plugin .deb.
- **`Conflicts:` instead of `Breaks:`** permanently refuses co-installation. Apt cannot resolve it by upgrading the peer; the user is stuck. The relationship gets harder to evolve as the peer's release train moves forward.
- **No constraint at all** (the pre-`Breaks:` state in PR #203) lets the install succeed onto a too-old peer. The consumer side encounters an unrecognised contract shape and fails silently — the failure is invisible to apt and to operators. This was the original silent missing-card bug that motivated this learning.

`Breaks:` is the right tool because it matches the actual contract semantics: "older versions of peer cannot coexist with this version of producer." The peer's presence is independent; only the version relationship is constrained.

## When to Apply

Apply this when adding or revising a `debian/control` clause that pins a sibling HaLOS package's minimum version:

- ✅ **Use `Breaks: peer (<< X)`** for partial-upgrade gating, contract minimums on optional peers, and any silent-failure mode.
- ❌ **Skip the `Breaks:`** when all three Skip-Depends-pins conditions hold (cohort upgrade + graceful skip + runtime probe). The Skip-Depends-pins doc's three-layer test still applies; this guidance is what to use when that test fails.
- ❌ **Don't use `Depends:`** for "minimum version of an optional peer." `Depends:` forces installation.
- ❌ **Don't use `Conflicts:`** for "minimum version" relationships. `Conflicts:` is for fundamental incompatibility, not temporal contract drift.

For generator-injected `Breaks:` (the producer's `debian/control` is generated, not hand-edited), drive the injection from the same predicate that triggers the contract-affected output. Don't duplicate the trigger condition in two places — see [`2026-05-13-shared-predicate-over-parallel-if-chains.md`](2026-05-13-shared-predicate-over-parallel-if-chains.md) for the failure mode and the fix.

## Examples

**Wrong — over-constraining `Depends:`** (hypothetical version of PR #203):

```
Package: marine-signalk-server-container
Depends: ${misc:Depends},
         docker-compose | docker-compose-plugin,
         homarr-container-adapter (>= 0.4.6),
         halos-core-containers (>= 0.3.2)
```

Installing this onto a Signal K-only device with no Homarr dashboard pulls in the entire Homarr stack — over-imposed footprint, services the user doesn't want running.

**Right — conditional `Breaks:`** (what PR #203 actually does):

```
Package: marine-signalk-server-container
Depends: ${misc:Depends}, docker-compose | docker-compose-plugin
Breaks: homarr-container-adapter (<< 0.4.6),
        halos-core-containers (<< 0.3.2)
```

Installing this onto a Signal K-only device: succeeds, no peer pulled in. Installing onto a device with `homarr-container-adapter 0.4.5`: apt either auto-upgrades the adapter to 0.4.6+ or refuses with `marine-signalk-server-container: Breaks: homarr-container-adapter (< 0.4.6) but 0.4.5-1 is installed`. Both outcomes are correct.

**Generator-injected `Breaks:`** (the CPT v0.6.0 pattern). The Debian relationship string lives in one place — a generator helper consumed by every routed app's `debian/control` template:

```python
# In container-packaging-tools/src/generate_container_packages/template_context.py
HOMARR_ADAPTER_MIN_VERSION = "0.4.6"
HALOS_CORE_CONTAINERS_MIN_VERSION = "0.3.2"

def _compute_homarr_stack_breaks(metadata):
    if not emits_path_only_url(metadata):
        return []
    return [
        f"homarr-container-adapter (<< {HOMARR_ADAPTER_MIN_VERSION})",
        f"halos-core-containers (<< {HALOS_CORE_CONTAINERS_MIN_VERSION})",
    ]
```

Bumping the contract minimum is one diff. Every CPT-generated .deb picks it up on the next rebuild.

## Related

- [Skip APT Depends pins between sibling HaLOS packages when graceful skip and cohort upgrade cover the failure mode](2026-04-30-skip-apt-depends-pins-sibling-halos-packages.md) — the policy doc this companion guidance extends. The Skip-Depends-pins doc names the Keep-the-pin conditions; this doc names the Debian primitive that fits them.
- [Encode a shared decision in a shared predicate, not parallel if-chains with a "stay in lock-step" comment](2026-05-13-shared-predicate-over-parallel-if-chains.md) — when the `Breaks:` is generator-injected, this is how to keep the injection trigger aligned with the contract-affected output trigger.
- Debian Policy Manual §7.4 — [Packages which break other packages](https://www.debian.org/doc/debian-policy/ch-relationships.html#packages-which-break-other-packages-breaks).
- Worked example: [halos-org/container-packaging-tools#203](https://github.com/halos-org/container-packaging-tools/pull/203) — the CPT change that auto-injects `Breaks:` for routed visible apps.
