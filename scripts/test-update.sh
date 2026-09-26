#!/usr/bin/env bash
set -euo pipefail
trap 'printf "terminal-kit: test-update.sh failed at line %s\n" "$LINENO" >&2' ERR

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export TERMINAL_KIT_NO_RELOAD=1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
home="$scratch/home"
mkdir -p "$home/Projects" "$scratch/bin" "$scratch/seed"
printf '#!/usr/bin/env bash\necho Darwin\n' > "$scratch/bin/uname"
chmod +x "$scratch/bin/uname"

git_quiet() { git -c user.name=t -c user.email=t@example.invalid -c init.defaultBranch=main "$@" >/dev/null 2>&1; }

# Build an origin from the current files (never from this checkout's .git).
rsync -a --exclude .git "$ROOT/" "$scratch/seed/"
git_quiet -C "$scratch/seed" init
git_quiet -C "$scratch/seed" add -A
git_quiet -C "$scratch/seed" commit -m base
git_quiet clone --bare "$scratch/seed" "$scratch/origin.git"
git_quiet clone "$scratch/origin.git" "$home/Projects/terminal-kit"
kit="$home/Projects/terminal-kit"

run() { HOME="$home" PATH="$scratch/bin:/usr/bin:/bin" "$kit/bin/terminal-kit" "$@"; }

[[ "$(run update)" == *'up to date'* ]]

git_quiet -C "$scratch/seed" remote add origin "$scratch/origin.git"
printf 'note\n' > "$scratch/seed/incoming.txt"
git_quiet -C "$scratch/seed" add incoming.txt
git_quiet -C "$scratch/seed" commit -m 'incoming change'
git_quiet -C "$scratch/seed" push origin main

before="$(git -C "$kit" rev-parse HEAD)"
check_output="$(run update --check)"
[[ "$check_output" == *'incoming change'* ]]
[[ "$(git -C "$kit" rev-parse HEAD)" == "$before" ]]
[[ ! -e "$home/.zshrc" ]]

run update >/dev/null
[[ "$(git -C "$kit" rev-parse HEAD)" == "$(git -C "$scratch/seed" rev-parse HEAD)" ]]
[[ -e "$kit/incoming.txt" ]]
grep -Fq '# >>> terminal-kit: zsh >>>' "$home/.zshrc"

# A diverged local branch is never merged or reset.
git_quiet -C "$kit" commit --allow-empty -m local
printf 'more\n' >> "$scratch/seed/incoming.txt"
git_quiet -C "$scratch/seed" commit -am 'second change'
git_quiet -C "$scratch/seed" push origin main
local_head="$(git -C "$kit" rev-parse HEAD)"
if run update >/dev/null 2>&1; then exit 1; fi
[[ "$(git -C "$kit" rev-parse HEAD)" == "$local_head" ]]

printf 'terminal-kit update tests passed\n'
