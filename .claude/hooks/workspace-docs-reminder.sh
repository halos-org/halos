#!/usr/bin/env bash
# PostToolUse reminder for writes under the workspace's top-level docs/.
# Fires only for files at <workspace-root>/docs/...; skips sub-repo docs/.
# Non-blocking: always exits 0. Errors are silenced so a misbehaving hook
# never fails an agent's tool call.
#
# Requires: jq (silently no-ops if missing — install via `./run install-dev-deps`).

exec 2>/dev/null

input=$(cat)
[ -z "$input" ] && exit 0

file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // empty')
[ -z "$file_path" ] && exit 0

# Workspace root = two directories up from this script's location.
# Use `pwd -P` so a workspace cloned at a symlinked path matches the physical
# path the tool reports in file_path.
script_dir=$(cd "$(dirname "$0")" && pwd -P) || exit 0
workspace_root=$(cd "$script_dir/../.." && pwd -P) || exit 0

case "$file_path" in
  /*) abs_path=$file_path ;;
  *)  abs_path="$workspace_root/$file_path" ;;
esac

case "$abs_path" in
  "$workspace_root"/docs/*) ;;
  *) exit 0 ;;
esac

# Defensive: confirm the file's git root is the workspace, not a nested repo.
file_dir=$(dirname "$abs_path")
[ -d "$file_dir" ] || file_dir=$workspace_root
file_git_root=$(git -C "$file_dir" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ "$file_git_root" = "$workspace_root" ] || exit 0

reminder="Workspace docs/ reminder (file: $abs_path)
- This is the PUBLIC halos-org/halos repo. Do NOT leak names, designs, or even the existence of private repos here.
- Docs about a specific repo belong in THAT repo's docs/. The workspace docs/ is for cross-repo, public concerns only.
- If the just-written file violates either rule, undo it now (delete, or move into the right repo) before the user sees it."

jq -n --arg msg "$reminder" '{
  systemMessage: $msg,
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: $msg
  }
}'

exit 0
