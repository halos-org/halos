---
title: "Custom pi-gen stages need a prerun.sh that calls copy_previous"
date: 2026-04-27
repo: halos-pi-gen-template
pr: https://github.com/halos-org/halos-pi-gen-template/pull/2
tags: [pi-gen, halos-pi-gen-template, custom-stages, prerun, layered-build]
---

# Problem

A new custom stage (`stage-custom-waveshare-can`) added to `halos-pi-gen-template` failed at build time with:

```
./00-run.sh: line 7: /pi-gen/work/<IMG_NAME>/stage-custom-waveshare-can/rootfs/boot/firmware/config.txt: No such file or directory
[Build failed]
```

The script tried to append a `dtoverlay` line to `${ROOTFS_DIR}/boot/firmware/config.txt`, but the path did not exist — `${ROOTFS_DIR}` was empty.

# Root Cause

pi-gen runs each stage against its own per-stage rootfs under `work/<IMG_NAME>/<stage>/rootfs/`. That rootfs is **not** automatically populated from the previous stage. Each stage that wants to build on the previous one must declare so via a top-level `prerun.sh` that calls the `copy_previous` helper:

```bash
#!/bin/bash -e

if [ ! -d "${ROOTFS_DIR}" ]; then
	copy_previous
fi
```

Without this, `${ROOTFS_DIR}` is created empty and any task that expects files placed by earlier stages (e.g. `/boot/firmware/config.txt` from `stage1`, anything under `/etc/` from package installs) hits a missing-path error.

The reference `stage-custom-ais` example in the same template repo includes this `prerun.sh`, but the file is easy to miss when copying or scaffolding a new stage from scratch — it sits at the stage root, not inside any numbered task directory.

# Solution

Add `prerun.sh` at the top level of the new stage directory:

```
stage-custom-<name>/
├── prerun.sh             ← REQUIRED: copies rootfs from previous stage
└── 00-<task>/
    ├── 00-run.sh
    └── files/...
```

Make it executable (`chmod +x prerun.sh`). Contents are the standard `copy_previous` guard shown above.

# Prevention

- **When scaffolding a new custom stage**, copy the entire reference stage directory (including `prerun.sh`) rather than only the numbered task subdir.
- **When reviewing a PR that adds a custom stage**, check that `prerun.sh` is present at the stage root.
- The failure mode is a hard build error at the new stage's first task, so this surfaces immediately on a local build — but the error message ("`config.txt: No such file or directory`") points at a path inside the rootfs and reads like a config issue, not a rootfs-initialization issue. Recognizing that empty `${ROOTFS_DIR}` is the real cause is the diagnostic shortcut.

# Applies To

`halos-pi-gen-template` (and any layered pi-gen setup) when adding a new `stage-custom-*` directory. Stages that genuinely want to start from an empty rootfs (rare for customization stages) can omit `prerun.sh`, but anything that touches files already installed by `halos-pi-gen` or upstream `pi-gen` needs it.

# Related

- [Custom pi-gen STAGE_LIST drifts from upstream when layering on halos-pi-gen](2026-04-27-pi-gen-custom-stage-list-drift.md) — sister gotcha for the same layered-build setup, different failure mode (silent miss vs hard error).
