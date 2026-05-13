---
title: Encode a shared decision in a shared predicate, not parallel if-chains with a "stay in lock-step" comment
date: 2026-05-13
category: best-practices
module: code-organization
problem_type: best_practice
component: tooling
severity: medium
applies_when:
  - Two or more call sites must answer the same question about the same input ("does this satisfy <condition>?")
  - The condition is non-trivial — multiple fields, AND/OR logic, or domain-specific semantics
  - The call sites live in different modules and can be modified independently
  - The consequence of the predicates drifting is a silent failure rather than a loud one
tags:
  - code-organization
  - shared-predicate
  - drift
  - silent-failure
  - generator-pipelines
  - halos
related:
  - 2026-05-13-prefer-breaks-over-depends-for-partial-upgrade-gating.md
---

# Encode a shared decision in a shared predicate, not parallel if-chains with a "stay in lock-step" comment

## Context

Two call sites need to answer the same question about the same input. Examples surface across the workspace:

- A code generator's "emit shape A vs shape B" branch and a separate "register a constraint that only applies to shape A" branch.
- A serializer's "include this field" decision and a validator's "require this field" decision on the same payload type.
- A migration's "rewrite rows matching condition C" decision and a backfill's "include rows matching C" decision.

The naïve implementation duplicates the condition at each site. The duplication is held together by maintainer discipline: a comment that says *"keep this in sync with X"*, or *"mirrors the precondition in Y"*, or *"the two stay in lock-step"*. A comment is not a contract. As soon as one site evolves without the other being updated, the two drift — and the failure mode is whatever the duplicated condition was guarding against.

PR halos-org/container-packaging-tools#203 surfaced this pattern in the wild. The generator had two call sites asking the same question — *"does this app emit a path-only Homarr-card URL?"*:

- `registry.generate_registry_toml` used the answer to pick the URL form (`/app_id/` vs `https://{{domain}}/app_id/`).
- `template_context._compute_homarr_stack_breaks` used the answer to decide whether to inject Debian `Breaks:` clauses.

Both implementations had a `routing is not None AND web_ui.enabled` shape. But the second one also gated on `web_ui.visible`. The first did not. The drift was 2-3 commits old; the CE review caught it before merge. The silent failure mode the drift exposed: a routed but hidden web app shipped a path-only TOML without the matching `Breaks:` line, so an older `homarr-container-adapter` would silently skip the TOML's ping-coverage entry with no apt-level signal to the operator.

The plan's docstring on the duplicated function literally said *"the trigger condition mirrors `registry.generate_registry_toml`'s routed-branch precondition so the two stay in lock-step."* The comment had already failed.

## Guidance

**When two or more call sites answer the same non-trivial question about the same input, extract that question into a named predicate consumed by every site.**

```python
# Wrong — parallel if-chains, drift-prone, comment is the only safety net.

# registry.py
if routing is not None and web_ui.get("enabled"):
    url = f"/{app_id}/"           # path-only form
else:
    url = f"https://{{domain}}/..."

# template_context.py
def _compute_homarr_stack_breaks(metadata):
    if metadata.get("routing") is None: return []
    if not (metadata.get("web_ui") or {}).get("enabled"): return []
    if not (metadata.get("web_ui") or {}).get("visible"): return []   # <-- DRIFT
    return [...]


# Right — shared predicate, single source of truth.

# registry.py
def emits_path_only_url(metadata):
    web_ui = metadata.get("web_ui") or {}
    if not web_ui.get("enabled"): return False
    if metadata.get("routing") is None: return False
    return True

def generate_registry_toml(metadata, ...):
    ...
    if emits_path_only_url(metadata):
        url = f"/{app_id}/"
    else:
        ...

# template_context.py
from generate_container_packages.registry import emits_path_only_url

def _compute_homarr_stack_breaks(metadata):
    if not emits_path_only_url(metadata):
        return []
    return [...]
```

**Name the predicate after the question it answers, not after the answer it produces.** `emits_path_only_url(metadata)` reads as the question both call sites need answered. `is_routed_visible_web_app(metadata)` would be implementation-flavoured; `should_inject_homarr_breaks(metadata)` would couple to one of the two consumers.

**Place the predicate near its primary semantic owner.** In PR #203 the path-only URL emission is the canonical surface (it determines the TOML content that all the other decisions key off); the predicate lives next to it in `registry.py`. The Breaks-injection site imports from there. The general rule: put the predicate where the most-load-bearing call site lives, then have other sites import from it.

**Keep predicates pure.** No I/O, no logging, no side effects. The signature is `metadata -> bool`. Testing in isolation should be trivial — a single parameterised test feeding the full trigger matrix is the canonical coverage.

## Why This Matters

The cost of duplicating a non-trivial condition is paid silently and over time:

- **Drift is invisible at write time.** When you copy a condition from one site to another, your assertion that they agree is correct *right then*. The drift accrues across subsequent commits that touch one site without the author noticing the other.
- **Maintainer-discipline comments don't compose with reviews.** A reviewer looking at a one-site change won't see the duplicated site unless they grep for it. The "stay in lock-step" comment is invisible to the reviewer's tooling. PR #203's reviewer caught the drift only because they followed an explicit instruction to *verify the trigger condition mirrors the other site* — which is exactly the kind of high-cost manual check that a shared predicate eliminates.
- **The failure mode is silent.** Drift produces incorrect output without any error. In PR #203, drift would have shipped routed-but-hidden web apps with no `Breaks:` line; the consequence on older adapters is a `tracing::warn` and a skipped registry entry. No apt error, no test failure, no log line in the producer.
- **Future contract evolutions multiply the bookkeeping.** If the trigger condition gets a new clause (e.g., the contract needs to gate on `web_ui.path` as well), every duplicated site needs the new clause. A shared predicate absorbs the change in one place.

The cost of extraction is negligible: one function definition, one import. The cost of *not* extracting is "the review catches the drift this time" — and you cannot rely on that catching it next time, when the reviewer's instructions are different.

## When to Apply

Apply this when **all three** signals are present:

1. **Non-trivial condition.** The shared question involves at least 3 fields, or non-obvious AND/OR/negation logic, or domain-specific semantics ("is this a path-only URL emission?", "is this an enabled scheduled job that hasn't run yet?", "is this a public route under the auth boundary?"). A 1-2 field check (`if user.active and user.confirmed`) duplicated across two sites doesn't earn extraction.
2. **Independent modification.** The call sites are in different modules, owned by potentially different reviewers, modifiable in separate PRs. If the two sites are 30 lines apart in the same function, duplication is fine — drift is unlikely.
3. **Silent failure on drift.** The consequence of the predicates returning different answers is incorrect output, not a loud error. If drift would produce a `ValueError` or a failing test, drift will surface on its own and you don't need preemptive extraction.

**Don't apply when:**

- The two call sites are tightly co-located (same function, same module section).
- The condition is structurally similar but semantically different (one site asks "is the user authenticated?", the other asks "is the request from an authenticated user?" — these can drift correctly).
- The "shared" appearance is incidental (today's two sites happen to use the same fields, but the contract for each is independent and could legitimately diverge).
- Extraction would require a new module with no other content — wait until a second extraction earns the boundary.

**Signal to grep for:** comments in your own code containing *"keep in sync with"*, *"mirrors X"*, *"must match Y"*, *"the two stay in lock-step"*. Each one is a duplicated decision that the author already recognised as drift-prone. Treat the comment as a TODO to extract.

## Examples

**The drift caught in PR #203.** Before extraction:

```python
# src/generate_container_packages/registry.py — the path-only branch
if routing is not None:
    url = f"/{app_id}/"                # only checks routing + enabled (via outer guard)

# src/generate_container_packages/template_context.py — the Breaks injection
def _compute_homarr_stack_breaks(metadata):
    if metadata.get("routing") is None: return []
    if not web_ui.get("enabled"): return []
    if not web_ui.get("visible"): return []   # <-- drifts from registry.py
    return [...]
```

A routed app with `web_ui.visible: false` ships a path-only TOML (per `registry.py`'s decision) but no `Breaks:` line (per the `_compute_homarr_stack_breaks` gate). On an older `homarr-container-adapter` the TOML's URL fails validation and the entry is skipped silently — ping coverage for that app is broken with no signal.

**After extraction:**

```python
# src/generate_container_packages/registry.py
def emits_path_only_url(metadata):
    """Single source of truth — both URL emission and Breaks injection key off this."""
    web_ui = metadata.get("web_ui") or {}
    if not web_ui.get("enabled"): return False
    if metadata.get("routing") is None: return False
    return True

def generate_registry_toml(metadata, ...):
    if emits_path_only_url(metadata):
        url = f"/{app_id}/"
    else:
        url = f"https://{{domain}}/..."

# src/generate_container_packages/template_context.py
from generate_container_packages.registry import emits_path_only_url

def _compute_homarr_stack_breaks(metadata):
    if not emits_path_only_url(metadata):
        return []
    return [...]
```

The two sites cannot drift. A future contract evolution adding a new clause (e.g., a path-only emission for some `web_ui.path` shape) is a single diff. The original docstring comment ("mirrors registry.generate_registry_toml's routed-branch precondition") becomes unnecessary — the predicate *is* the contract.

**The general shape.** Any time you have:

```python
# Module A
if (cond1 and cond2 and not cond3):
    do_A_thing()

# Module B — must agree
def should_B_thing(input):
    return cond1 and cond2 and not cond3   # comment: "keep in sync with A"
```

Extract:

```python
# Module shared (or wherever the most load-bearing site lives)
def is_<the_question>(input):
    return cond1 and cond2 and not cond3
```

…and have both A and B call it. Then write the test that exercises the predicate's truth table once, not the call sites.

## Related

- [Prefer `Breaks: peer (<< X)` over `Depends: peer (>= X)` when gating against a partial-upgrade contract minimum](2026-05-13-prefer-breaks-over-depends-for-partial-upgrade-gating.md) — when a code generator auto-injects `Breaks:`, the injection trigger must share its predicate with the contract-affected output trigger. This learning is the structural pattern that makes that sharing safe.
- Worked example: [halos-org/container-packaging-tools#203](https://github.com/halos-org/container-packaging-tools/pull/203) — the CPT change where CE review caught the predicate drift and the fix extracted `registry.emits_path_only_url`.
- Related cross-repo learning ([halos-org/homarr-container-adapter](https://github.com/halos-org/homarr-container-adapter/blob/main/docs/solutions/best-practices/2026-05-04-ship-cross-format-identity-helper-before-url-migration.md)): when a contract shape changes, the consumer must accept both shapes during the transition. Both are forms of "encode contract semantics in one place, not many."
