---
title: "Agent fabricates numerical claims to fill template slots"
date: 2026-04-27
repo: halos (workspace)
tags: [workflow, agent-behavior, accuracy, planning, documentation]
---

# Problem

While planning the `halos-pi-gen-template` repo (PR halos-org/halos-pi-gen-template#1), the agent put two confident-sounding numerical claims into the implementation plan and the template's README:

- "Local build takes 30–60 minutes."
- "pi-gen needs ~20 GB free disk space."

Neither was measured. Both were carried forward verbatim from the plan into the README and only removed after the user pushed back. When asked where the numbers came from, the honest answer was "I asserted them" — pattern-matching from generic pi-gen folklore, not from this repo.

# Root Cause

When a template (plan, README, troubleshooting section) has a slot that *expects* a number — "build time", "disk space", "memory required" — the temptation is to fill it with a plausible figure rather than leave it blank or say "not measured." A blank slot looks unfinished; a confident number looks polished. The polish is the trap: the reader can't tell a measured number from a fabricated one, so the document becomes silently unreliable.

This is distinct from scope misjudgment (which has its own feedback memory). Scope misjudgment is "I missed a constraint." This is "I made up a fact." The output looks more competent in the moment and is harder to catch in self-review because everything else around the claim is correct.

# Solution

When a quantitative claim would help the reader:

1. **Measure it, or remove it.** A README with "wait for the CI run to finish" is more honest than one with "wait ~30–60 minutes" if 30–60 was never measured.
2. **If a number is genuinely useful and measurement is impractical**, frame it as approximate and grounded: "On a 2024 GitHub Actions ARM64 runner the build took ~X minutes (CI run #N)" — tied to a specific observation, not a folk estimate.
3. **In plans**, treat a numerical claim as a planning input that needs grounding before it lands in user-facing artifacts. If it's only there to make the plan look complete, drop it.
4. **Self-review prompt before committing prose**: scan for numbers (minutes, GB, MB, percentages, version pins). For each, ask "where did this come from?" If the answer is "general knowledge" rather than a measurement or a citable source, remove it or qualify it explicitly.

# Why This Works

The reader of a plan or README extends trust to specific claims. A vague-but-honest framing ("wait for CI") preserves that trust; a specific-but-fabricated one ("wait 30–60 minutes") spends it. Once the reader notices one fabricated number, they have to verify everything, which is more expensive than removing the number in the first place.

# Prevention

- Before writing any "expects-a-number" sentence, decide if the number is measured, citable, or genuinely useful as a rough hint. If none of those, write the sentence without the number.
- In troubleshooting sections, prefer "more free space" or "enough RAM" over specific figures unless you actually measured them.
- In plan risk tables and verification steps, never say "takes X minutes" unless that came from a real run.
- Treat self-correction here as a quiet baseline, not a remarkable event. The user does not want to play fact-checker on every paragraph.

# Related

- Memory feedback: scope-assessment, no-external-issues, compound-before-merge — adjacent agent-behavior failure modes.
- Plan: `docs/plans/2026-04-27-001-feat-halos-pi-gen-template-repo-plan.md` — where this happened, with the same fabricated claims later removed in halos-org/halos-pi-gen-template#1.
