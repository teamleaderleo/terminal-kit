#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
  printf 'Usage: tk duo [directory]\nOpen Claude and Codex side by side in a new cmux workspace.\n'
  exit 0
fi
[[ $# -le 1 ]] || { printf 'Usage: tk duo [directory]\n' >&2; exit 1; }
for tool in cmux claude codex; do
  command -v "$tool" >/dev/null || { printf 'Missing required command: %s\n' "$tool" >&2; exit 1; }
done
project_dir="$(cd -- "${1:-.}" && pwd -P)"
exec cmux new-workspace --name "${project_dir##*/} · Claude + Codex" \
  --cwd "$project_dir" --focus true \
  --layout '{"direction":"horizontal","split":0.5,"children":[{"pane":{"surfaces":[{"type":"terminal","command":"claude"}]}},{"pane":{"surfaces":[{"type":"terminal","command":"codex"}]}}]}'
