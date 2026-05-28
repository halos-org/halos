---
title: "npm prunes Signal K plugin symlinks not registered as file: dependencies"
date: 2026-04-23
last_updated: 2026-05-13
repo: signalk-halpi
pr: https://github.com/hatlabs/signalk-halpi/pull/12
tags: [npm, debian, symlink, signalk, system-plugins, pi-gen]
---

# Problem

Deb-packaged Signal K plugins installed via symlink into `node_modules/` disappear after any `npm install` operation (e.g., prestart.sh installing signalk-to-influxdb2). npm treats symlinks not tracked in `package.json` as extraneous and prunes them.

# Root Cause

The postinst created a symlink `node_modules/signalk-halpi -> ../system-plugins/signalk-halpi` but never registered the dependency in Signal K's `package.json`. npm's dependency resolver only preserves entries it knows about.

# Solution

Register the plugin as a `file:` dependency in Signal K's `package.json`:

```json
"signalk-halpi": "file:system-plugins/signalk-halpi"
```

With npm 11+, `file:` dependencies create symlinks (not copies) and survive subsequent `npm install` operations.

## Implementation

1. **postinst**: Create symlink AND add `file:` entry to `package.json` (create minimal `package.json` if it doesn't exist yet)
2. **postrm**: Remove symlink AND remove `file:` entry from `package.json`
3. **build-deb**: Strip `devDependencies` from shipped `package.json` — otherwise npm installs ~160 unnecessary packages when resolving the `file:` dependency

## Gotchas

- **YAML block scalars**: Inline Python in GitHub Actions composite action `run: |` blocks must not have content at column 0 — it terminates the YAML block scalar. Use one-liner `python3 -c` instead of heredocs or multi-line strings.
- **Missing package.json**: On fresh installs, `package.json` may not exist when postinst runs. Must handle this case or the `file:` dep is never registered and the symlink gets pruned on first npm operation.
- **postinst error handling**: Use `set -e` (fail loudly) in postinst but `|| true` in postrm — a broken registration should block install, but partial cleanup shouldn't block uninstall.

# Applies To

Any Node.js module installed via symlink (or extract-in-place) into a `node_modules/` directory that is also managed by npm — regardless of how it got there. The install channel does not matter; only the lack of a `file:` registration does. The pattern is not Signal K-specific.

# Recurrence: ais-forwarder in halos-pi-gen-custom (2026-05-13)

The same failure mode bit a different repo before the pattern had been generalized across the workspace. `halos-pi-gen-custom/stage-custom-selene/00-install-sk-plugins/00-run.sh` was installing `ais-forwarder` directly into `${SK_DATA}/node_modules/ais-forwarder/` at pi-gen build time via `wget | tar`, with no symlink-via-`system-plugins/` indirection and no `file:` dependency. The container's `prestart.sh` runs `npm install` on first boot (for `signalk-to-influxdb2` provisioning), and that prune removed the plugin silently — Selene units would have shipped without working AIS forwarding.

Fix in [hatlabs/halos-pi-gen-custom#4](https://github.com/hatlabs/halos-pi-gen-custom/pull/4) and [halos-org/halos-pi-gen-template#3](https://github.com/halos-org/halos-pi-gen-template/pull/3) (the public template variant) was to adopt the same three-part pattern as signalk-halpi, just adapted from a Debian postinst into a pi-gen stage script:

1. Extract tarball under `${SK_DATA}/system-plugins/<plugin>/`
2. Strip `devDependencies` from the plugin's `package.json`
3. Symlink `${SK_DATA}/node_modules/<plugin>` → `../system-plugins/<plugin>`
4. Merge `<plugin>: file:system-plugins/<plugin>` into `${SK_DATA}/package.json`

**Workspace rule**: any new code path that places a Signal K plugin into the SK data directory by means other than `npm install <pkg>` must use this pattern. That includes deb postinst, pi-gen stages, container prestart scripts, manual `scp + extract` workflows, and any future install channel. Verify by running `npm install` in the SK data dir after install — if the symlink survives, the registration is correct.
