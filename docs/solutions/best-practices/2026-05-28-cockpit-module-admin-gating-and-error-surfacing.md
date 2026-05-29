---
title: Cockpit modules — gate admin-required actions against Limited Access mode and always surface spawn errors
date: 2026-05-28
category: best-practices
module: cockpit-container-apps
problem_type: best_practice
component: cockpit-module-frontend
severity: medium
applies_when:
  - Building or modifying a HaLOS Cockpit module's React/TypeScript frontend
  - A button or interactive element triggers `cockpit.spawn(..., { superuser: 'require' })` or `'try'`
  - A user-facing async action returns a Promise that can reject (spawn channel errors, backend error JSON, network failures)
  - A Python backend prints error responses using `json.dumps(..., indent=2)` consumed by a per-line frontend parser
tags:
  - cockpit
  - frontend
  - typescript
  - patternfly
  - permissions
  - admin
  - error-handling
  - async
  - silent-failure
  - ux
---

# Cockpit modules — gate admin-required actions against Limited Access mode and always surface spawn errors

## Context

A user reported that clicking **Install** on a marine container app in `cockpit-container-apps` showed a spinner for ~1 second, then nothing happened. No error, no install, no log line in the browser. The same symptom turned out to be **three independent silent-failure paths** all hitting the same destination — an unhandled promise rejection — and each of them is a copy-pastable mistake when bootstrapping a new Cockpit module. This pattern affects every Cockpit module we ship (`cockpit-apt`, `cockpit-authelia-users`, `cockpit-networkmanager-halos`, `cockpit-container-apps`, plus our forks of `cockpit-dockermanager-debian`); the cross-module audit is tracked in halos-org/halos#121, and the pilot fix landed in halos-org/cockpit-container-apps#80.

The three bugs all look identical to the user. Treat them as a single class: **"the button does nothing visible"**.

## Root cause #1 — admin-required button enabled in Limited Access mode

Cockpit's permission model is two-tiered. By default, a module runs without admin access; the top bar shows a yellow "Limited access" badge. Privileged actions are gated by a per-spawn `superuser: 'require'` option that fails immediately with `problem: 'access-denied'` if the user hasn't elevated.

The mistake is rendering the button as fully enabled in Limited Access mode anyway. The button looks identical to the elevated case, the user clicks, and `cockpit.spawn(..., { superuser: 'require' })` rejects with `access-denied` *before* hitting the backend. apt's history log is empty; the sudo log shows nothing; the network tab shows nothing — because the spawn never made it past Cockpit's bridge.

**The fix is `cockpit.permission({ admin: true })`** as the reactive source of truth. It exposes an `allowed: boolean | null` property and a `'changed'` event that fires when the user elevates or drops privileges via the top bar. Wire that into a small hook and feed an `isAdminRequired` flag into the button.

Two non-obvious details:

- **Treat the `null` (loading) state as gated**, not enabled. Cockpit resolves `permission.allowed` asynchronously over the bridge; for the first ~100-300ms after the page renders, `allowed === null`. If you write `isAdminRequired = isAdminAllowed === false`, the button is enabled during the load window and a click in that window guarantees a backend `access-denied`. Use `isAdminAllowed !== true` instead, which correctly defaults to "gated until proven otherwise".
- **PatternFly v6's `<Button isAriaDisabled>` DOES suppress `onClick` and `onKeyPress`**. Three independent reviewers in the tiered review flagged this as "the click handler still fires" — verified against `@patternfly/react-core/dist/js/components/Button/Button.js`, the prop replaces both handlers with `preventDefault` no-ops. Use `isAriaDisabled` (not `isDisabled`) so a `<Tooltip>` can wrap the button — PatternFly hides tooltips on truly-disabled elements. Click suppression is preserved.

## Root cause #2 — promise rejection swallowed at the click-handler boundary

The typical Cockpit module pattern:

```tsx
const handleInstall = async (pkg: Package) => {
  setActionInProgress(true);
  try {
    await installPackage(pkg.name, onProgress);
    await actions.refresh();
  } catch (error) {
    console.error('Install failed:', error);
    throw error;
  } finally {
    setActionInProgress(false);
  }
};

<Button onClick={() => handleInstall(pkg)}>Install</Button>
```

This catches the rejection, logs it to console, clears the in-progress spinner, and **re-throws**. The re-throw bubbles out of `handleInstall` back to the `() => handleInstall(pkg)` arrow. That arrow returns a `Promise<void>` that no one awaits or `.catch()`es — it's an unhandled promise rejection. React 18 doesn't break the UI; `console.error` is the only trace; the user sees the spinner appear and disappear with no error UI.

**The fix is at the click site.** Wrap the action call with an inline catch and put the formatted message into a piece of component state that drives an `<Alert>`:

```tsx
const [actionError, setActionError] = useState<string | null>(null);

const runAction = async (action: () => Promise<void>) => {
  setActionError(null);
  try {
    await action();
  } catch (error) {
    if (isMountedRef.current) {
      setActionError(formatErrorMessage(error));
    }
  }
};

<Button onClick={() => void runAction(() => onInstall(pkg))}>Install</Button>
{actionError && <Alert variant="danger" title="Action failed" isInline>{actionError}</Alert>}
```

Three corollaries that bit us during review:

- **Guard `setState` after `await` with an `isMountedRef`.** If the user clicks Back or switches stores mid-install, the component unmounts before the promise settles. The late `setActionError(...)` then runs on an unmounted component — React 18 logs a warning and the update is discarded, but the warning is real and the orphaned promise leaks. A simple `useRef(true)` + `useEffect` cleanup setting it false is enough; don't reach for `AbortController` unless you actually need to cancel the spawn.
- **Apply the same guard to all `setState`-after-`await` sites in the component**, not just `runAction`. In our case `loadConfiguration` (called from `useEffect` when an app is installed) and `handleConfigSave` had the same shape and needed the same treatment.
- **Map Cockpit channel-level errors to user-actionable text**. `cockpit.spawn`'s `proc.fail` callback hands you an error object with `{ problem, exit_status, message }`. `String(error)` returns `"[object Object]"` because Cockpit overrides `.toString()` to return `.message` (often empty). Inspect `err.problem === 'access-denied'` and surface a real message like "Administrative access is required to perform this action." instead of falling through to a generic "Install command failed".

## Root cause #3 — pretty-printed backend JSON dropped by per-line frontend parser

Our Python Cockpit backends format errors with `json.dumps(error_dict, indent=2)` (see `cockpit_apt_utils/errors.py:format_error` and `cockpit_apt_utils/formatters.py:to_json`). That produces:

```json
{
  "error": "Failed to install package 'marine-avnav-container'",
  "code": "INSTALL_FAILED",
  "details": "E: Failed to fetch ... File has unexpected size. Mirror sync in progress?"
}
```

— a **multi-line** JSON object with newlines inside the braces, written to stderr and merged into stdout via `cockpit.spawn`'s `err: 'out'` option.

The natural frontend parser splits on `\n` and tries `JSON.parse` on each line:

```ts
proc.stream((data: string) => {
  stdout += data;
  const lines = stdout.split('\n');
  stdout = lines.pop() || '';
  for (const line of lines) {
    try {
      const parsed = JSON.parse(line);
      if (parsed.error) reject(new ContainerAppsError(parsed.error, parsed.code, parsed.details));
      ...
    } catch { /* ignore incomplete lines */ }
  }
});
```

Every line — `{`, `  "error": "..."`, `  "details": "..."`, `}` — fails `JSON.parse` individually. The error JSON is consumed by the per-line parser and dropped on the floor. `proc.fail` then fires with no useful data (Cockpit's error object has empty `message` and `null` `problem` when the backend exits non-zero but doesn't expose a structured channel error), and the user gets a fallback message — or nothing.

**The fix is a balanced-brace scanner that walks the *raw* accumulated stdout** (kept in a separate buffer from the line buffer, so it isn't consumed by the line splitter) and extracts each top-level `{...}` object. Track `depth`, `inString`, and `escape` to correctly skip braces inside JSON strings and escape sequences. Call this scanner from both `proc.done` (when no `success: true` marker was seen but the buffer contains an error) and `proc.fail` (as the first check before falling back to Cockpit's error object). Both compact progress lines and pretty-printed error blocks are now recovered cleanly.

A test corpus worth keeping:

- `{}` → 1 object
- `{"a":1}\n{"b":2}` → 2 objects in order
- `{"x":"{nope}"}` → 1 object; the `{`/`}` inside the string don't open/close a block
- `{"x":"a\"b"}` → 1 object; `\"` doesn't close the string
- `{"x":"a\\"}` → 1 object; `\\` is a literal backslash then `"` closes the string
- `{good}garbage{also good}` → 2 objects; garbage between is skipped
- `{good}{partial` (no closing brace) → 1 object; partial silently dropped

(See `frontend/src/api/index.ts:extractJsonObjects` and the corresponding tests in `frontend/src/api/__tests__/index.test.ts` for the implementation in cockpit-container-apps.)

## Cross-module pattern

When bootstrapping a new HaLOS Cockpit module — or when reviewing an existing one (audit per halos-org/halos#121) — verify all four:

1. **Every UI element that triggers a `superuser: 'require'` spawn is gated.** Subscribe via `cockpit.permission({ admin: true })` once at the top of the component (or in a shared `useAdminPermission` hook). Use `allowed !== true` (not `=== false`) so the loading window is gated. Drive `isAriaDisabled` plus a `<Tooltip>` explaining elevation is needed.
2. **Every async action's promise rejection reaches a `<Alert>` (or toast) state**, not just `console.error`. Wrap the call at the click site with a try/catch that updates a piece of component state. Guard the `setState` against unmount with an `isMountedRef`.
3. **`proc.fail` extracts a useful message** from `{ rawOutput, error, data }` in that order, mapping known Cockpit problems (`access-denied`, `not-found`) to user-actionable text before falling back to a generic code.
4. **Pretty-printed backend JSON is recovered** by walking the raw stream buffer with a balanced-brace scanner, not by per-line `JSON.parse`. The progress line pattern is still per-line, but error objects must be recovered from the full buffer.

If any of these fail, you'll likely meet the "button does nothing visible" symptom in production.

## Implementation conventions (added 2026-05-30)

Two conventions that emerged from porting the pilot pattern to additional modules. Per-module specifics live in each module's own docs/; this section captures the cross-module rules.

### Canonical `AdminGatedButton` shape — spread PatternFly `ButtonProps`

Hand-enumerating Button props per module leads to drift (one consumer needs `size`, another adds `iconPosition`, the lists diverge). Spread `ButtonProps` so the wrapper exposes the full PatternFly Button surface without per-module shopping:

```tsx
import { Button, Tooltip } from "@patternfly/react-core";
import type { ButtonProps } from "@patternfly/react-core";

export const ADMIN_REQUIRED_TOOLTIP = "Administrative access required";

export interface AdminGatedButtonProps extends ButtonProps {
  isAdminRequired: boolean;
}

export function AdminGatedButton({
  isAdminRequired,
  isAriaDisabled,
  isDisabled,
  children,
  ...rest
}: AdminGatedButtonProps) {
  const button = (
    <Button {...rest} isAriaDisabled={isAdminRequired || isAriaDisabled || isDisabled}>
      {children}
    </Button>
  );
  if (isAdminRequired) {
    return <Tooltip content={ADMIN_REQUIRED_TOOLTIP}>{button}</Tooltip>;
  }
  return button;
}
```

Two semantic decisions baked in:

- **Every disable reason collapses to `isAriaDisabled`** on the underlying `Button` so click suppression composes with the admin tooltip and the consumer never has to think about "operational disable vs aria disable".
- **`isAdminRequired` is the only new prop.** Everything else flows through, so PatternFly Button changes don't break this component.

(In JSX modules without TypeScript, drop the type extension and use the same `...props` spread shape directly.)

### "Gated everywhere or nowhere" — enumerate every admin-required UI surface in the module

Drive-by gating — fixing only the buttons an audit listed and missing others — leaves a worse UX than no gating at all, because the user can't tell which clickable controls are gated and which aren't. **Before opening a gating PR, enumerate every admin-required UI surface in the module.** Two cheap checks:

1. Grep the module for `superuser: ['"]require['"]` and `superuser: ['"]try['"]` and confirm every callsite traces back to a gated UI element. The workspace `./run audit-admin-required` task does this across all Cockpit modules.
2. Walk the rendered UI in Limited Access mode and confirm there are no clickable admin-required controls left.

If any element fails check 1 *or* check 2, the gating PR isn't complete. Track the gap as a separate issue if you can't fix it in scope.

## Anti-patterns to recognize

- `cockpit.spawn(..., { superuser: 'require' })` invoked from a button that has no permission check above it. If the user is in Limited Access mode the spawn fails before reaching the backend.
- Click handlers shaped `onClick={() => handleX(...)}` where `handleX` is `async` and re-throws. The thrown rejection vanishes.
- `String(spawnError)` to display a Cockpit channel error. Cockpit overrides `.toString()` to return `.message`, which is often empty.
- Frontend assuming each newline in the stream is a complete JSON object. Compact progress lines fit that shape; pretty-printed error blocks don't.
- Using PatternFly's `isDisabled` on a button that needs a tooltip explaining why it's disabled. Tooltips don't render on truly-disabled elements; use `isAriaDisabled` instead — it still suppresses `onClick` and `onKeyPress` in PatternFly v6.

## References

- halos-org/cockpit-container-apps#80 — pilot implementation
- halos-org/halos#121 — cross-module audit tracker
- `cockpit-container-apps/frontend/src/hooks/useAdminPermission.ts` — the hook
- `cockpit-container-apps/frontend/src/api/index.ts` — `runStreamingCommand`, `extractJsonObjects`, `buildSpawnFailureError`
- `cockpit-container-apps/frontend/src/components/AppDetails.tsx` — `AdminGatedButton`, `runAction`, `isMountedRef`
- `./run audit-admin-required` — workspace grep helper for the "gated everywhere" check
- Cockpit upstream docs on `cockpit.permission()` — https://cockpit-project.org/guide/latest/cockpit-permission
- Cockpit upstream docs on `cockpit.spawn()` — https://cockpit-project.org/guide/latest/cockpit-spawn
