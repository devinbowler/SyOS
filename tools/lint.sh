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
	# -I makes grep treat a binary file as non-matching, so a stray CR inside
	# a .pyc or a font is never "corrected" into a corrupted file.
	if grep -qUI $'\r' -- "$file" 2>/dev/null; then
		sed -i 's/\r$//' -- "$file"
		printf '  CRLF -> LF  %s\n' "${file#./}"
		converted=$((converted + 1))
	fi
done < <(
	find . -type f \
		-not -path './.git/*' -not -path '*/__pycache__/*' \
		\( -name '*.sh' -o -name '*.md' -o -name '*.conf' -o -name '*.ini' \
		-o -name '*.css' -o -name '*.jsonc' -o -name '*.list' -o -name '*.toml' \
		-o -name '.gitignore' -o -name '.gitattributes' \
		-o -name 'config' -o -name 'syos-*' \) \
		-print0
)
printf 'line endings: %d file(s) converted\n' "$converted"

# Discovered by shebang rather than listed by hand: the helpers in
# stow/syos/.local/bin have no extension, and a hard-coded list silently stops
# covering new scripts exactly when the repo grows enough to need linting.
mapfile -d '' scripts < <(
	find . -type f -not -path './.git/*' -print0 |
		while IFS= read -r -d '' file; do
			read -r line <"$file" || continue
			case "$line" in
			'#!'*sh) printf '%s\0' "${file#./}" ;;
			esac
		done
)

# Python, discovered by shebang for the same reason as the shell scripts.
mapfile -d '' pyfiles < <(
	find . -type f -not -path './.git/*' -print0 |
		while IFS= read -r -d '' file; do
			read -r line <"$file" || continue
			case "$line" in
			'#!'*python*) printf '%s\0' "${file#./}" ;;
			esac
		done
)

# Every file with a shebang must be executable in git's index.
#
# Windows has no executable bit, so a script authored here is committed 100644
# and arrives on Debian unrunnable. The failure is silent in the worst way: the
# bar button that calls it does nothing at all, with no error anywhere, because
# nothing is watching the exit status of a click. This has cost real debugging
# time once already, so it is fixed here rather than remembered.
if command -v git >/dev/null 2>&1 && [[ -d .git ]]; then
	fixed=0
	for file in "${scripts[@]}" "${pyfiles[@]}"; do
		mode="$(git ls-files -s -- "$file" | awk '{print $1}')"
		# Untracked, or already executable.
		[[ -z "$mode" || "$mode" == "100755" ]] && continue
		git update-index --chmod=+x -- "$file"
		printf '  chmod +x    %s\n' "$file"
		fixed=$((fixed + 1))
	done
	printf 'exec bits: %d file(s) corrected\n' "$fixed"
fi

# Override when shellcheck is not on PATH, e.g. a downloaded static binary:
#   SHELLCHECK=~/.local/bin/shellcheck tools/lint.sh
SHELLCHECK="${SHELLCHECK:-shellcheck}"

if command -v "$SHELLCHECK" >/dev/null 2>&1; then
	printf 'shellcheck: %s\n' "${scripts[*]}"
	"$SHELLCHECK" --shell=bash --external-sources "${scripts[@]}"
	printf 'shellcheck: clean\n'
else
	printf 'shellcheck not found (set SHELLCHECK=/path/to/shellcheck); skipping\n' >&2
fi

if [[ ${#pyfiles[@]} -gt 0 ]]; then
	# Override when ruff is not on PATH, e.g. a pip --user install:
	#   RUFF=~/.local/bin/ruff tools/lint.sh
	RUFF="${RUFF:-ruff}"
	if command -v "$RUFF" >/dev/null 2>&1; then
		printf 'ruff: %s\n' "${pyfiles[*]}"
		"$RUFF" check "${pyfiles[@]}"
		"$RUFF" format --check "${pyfiles[@]}"
		printf 'ruff: clean\n'
	else
		printf 'ruff not found (set RUFF=/path/to/ruff); skipping\n' >&2
	fi
fi

# A syntax error in the bar's config costs you the entire bar, and waybar
# reports it only to its own stderr inside the session - by which point the
# machine has no visible controls left to debug it with. jq cannot read the
# comments waybar allows, so strip whole-line comments first.
if command -v jq >/dev/null 2>&1; then
	for jsonc in stow/waybar/.config/waybar/*.jsonc; do
		[ -e "$jsonc" ] || continue
		if sed 's|^[[:space:]]*//.*$||' "$jsonc" | jq -e . >/dev/null 2>&1; then
			printf 'json: %s ok\n' "$jsonc"
		else
			printf 'json: %s FAILED to parse\n' "$jsonc" >&2
			exit 1
		fi
	done
fi
