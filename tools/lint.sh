#!/usr/bin/env bash
#
# tools/lint.sh - normalise line endings and run shellcheck.
#
# SyOS is authored on Windows and runs on Debian, so a stray CRLF is a real
# and recurring failure mode: bash reports "bad interpreter: /usr/bin/env
# bash^M" and the install dies before it prints anything useful. This
# converts every text file in the repo to LF, then lints the shell scripts.
#
# Run before committing. Requires shellcheck on PATH.

set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

converted=0
while IFS= read -r -d '' file; do
	if grep -qU $'\r' -- "$file" 2>/dev/null; then
		sed -i 's/\r$//' -- "$file"
		printf '  CRLF -> LF  %s\n' "${file#./}"
		converted=$((converted + 1))
	fi
done < <(
	find . -type f \
		-not -path './.git/*' \
		\( -name '*.sh' -o -name '*.md' -o -name '*.conf' -o -name '*.ini' \
		-o -name '*.css' -o -name '*.jsonc' -o -name '*.list' -o -name '*.toml' \
		-o -name '.gitignore' -o -name '.gitattributes' \
		-o -name 'config' -o -name 'syos-session' \) \
		-print0
)
printf 'line endings: %d file(s) converted\n' "$converted"

scripts=(bootstrap.sh theme/generate.sh system/syos-session tools/lint.sh)

# Override when shellcheck is not on PATH, e.g. a downloaded static binary:
#   SHELLCHECK=~/.local/bin/shellcheck tools/lint.sh
SHELLCHECK="${SHELLCHECK:-shellcheck}"

if ! command -v "$SHELLCHECK" >/dev/null 2>&1; then
	printf 'shellcheck not found (set SHELLCHECK=/path/to/shellcheck); skipping lint\n' >&2
	exit 0
fi

printf 'shellcheck: %s\n' "${scripts[*]}"
"$SHELLCHECK" --shell=bash --external-sources "${scripts[@]}"
printf 'shellcheck: clean\n'
