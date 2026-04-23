---
title: "npm prunes deb-installed Signal K plugin symlinks"
date: 2026-04-23
repo: signalk-halpi
pr: https://github.com/hatlabs/signalk-halpi/pull/12
tags: [npm, debian, symlink, signalk, system-plugins]
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

Any deb-packaged Node.js module installed via symlink into a `node_modules/` directory that is also managed by npm. The pattern is not Signal K-specific.
