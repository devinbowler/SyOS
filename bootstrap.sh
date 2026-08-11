#!/usr/bin/env bash
#
# SyOS bootstrap - the only entry point (design doc 3.4).
#
#   sudo apt install git && git clone <repo> syos && cd syos && ./bootstrap.sh
#
# Idempotent by contract: a second run on the same machine must report zero
# changes. Every step therefore inspects state before mutating it, and every
# mutation is recorded through changed() so the closing summary is a real
# audit of what happened rather than a guess.
#
# Usage:
#   ./bootstrap.sh                  install / update, prompt on first run
#   ./bootstrap.sh --reconfigure    re-ask the per-machine questions
#   ./bootstrap.sh --noninteractive accept detected defaults, never prompt
#   ./bootstrap.sh --no-reboot      never offer to reboot at the end

set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STOW_SRC="$REPO_DIR/stow"
PKG_LIST="$REPO_DIR/packages.list"
PALETTE="$REPO_DIR/theme/palette.conf"

SYOS_CONF_DIR="$HOME/.config/syos"
LOCAL_CONF="$SYOS_CONF_DIR/local.conf"
BACKUP_DIR="$HOME/.syos-backup/$(date +%Y%m%d-%H%M%S)"

# Iosevka is not in trixie, so it is vendored at a pinned version to keep
# the two laptops byte-identical. See docs/decisions.md.
IOSEVKA_VERSION="34.8.0"

# Phase 0 ships four stow packages; later phases append to this list.
STOW_PACKAGES=(sway foot waybar fuzzel)

NONINTERACTIVE=false
RECONFIGURE=false
ALLOW_REBOOT=true

CHANGES=()
APT_UPDATED=false
IS_VM=false

# --- output -------------------------------------------------------------

if [[ -t 1 ]]; then
	C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_GREEN=$'\033[32m'
	C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_DIM=$'\033[2m'
else
	C_RESET=""; C_BOLD=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_DIM=""
fi

log() { printf '\n%s==>%s %s%s%s\n' "$C_GREEN" "$C_RESET" "$C_BOLD" "$*" "$C_RESET"; }
info() { printf '    %s\n' "$*"; }
dim() { printf '    %s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }
warn() { printf '    %swarning:%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die() {
	printf '\n%serror:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2
	exit 1
}

changed() {
	CHANGES+=("$1")
	printf '    %s+%s %s\n' "$C_GREEN" "$C_RESET" "$1"
}

tilde() { printf '%s' "${1/#$HOME/\~}"; }

# --- small helpers ------------------------------------------------------

# packages.list and friends: drop comments, whitespace and blank lines.
strip_comments() {
	sed -e 's/#.*//' -e 's/[[:space:]]//g' -- "$1" | grep -v '^$' || true
}

# Look up a KEY=value from a simple config file, with a default.
conf_value() {
	local file="$1" key="$2" fallback="${3-}" line
	if [[ -r "$file" ]]; then
		line="$(grep -E "^[[:space:]]*${key}=" -- "$file" | tail -n 1 || true)"
		if [[ -n "$line" ]]; then
			line="${line#*=}"
			line="${line%%#*}"
			line="${line#"${line%%[![:space:]]*}"}"
			line="${line%"${line##*[![:space:]]}"}"
			printf '%s' "$line"
			return 0
		fi
	fi
	printf '%s' "$fallback"
}

# Write stdin to a user-owned path. Returns 0 if the file changed, 1 if it
# was already byte-identical, which is what keeps the change count honest.
write_user_file() {
	local target="$1" mode="$2" tmp
	tmp="$(mktemp)" || die "mktemp failed"
	cat >"$tmp"
	if [[ -f "$target" ]] && cmp -s "$tmp" "$target"; then
		rm -f "$tmp"
		return 1
	fi
	mkdir -p -- "$(dirname -- "$target")" || die "cannot create $(dirname -- "$target")"
	install -m "$mode" "$tmp" "$target" || die "cannot write $target"
	rm -f "$tmp"
	return 0
}

# Same, for root-owned paths. Note that `set -e` is suspended inside a
# function called in an `if` condition, so every step checks explicitly.
write_root_file() {
	local target="$1" mode="$2" tmp
	tmp="$(mktemp)" || die "mktemp failed"
	cat >"$tmp"
	if sudo test -f "$target" && sudo cmp -s "$tmp" "$target"; then
		rm -f "$tmp"
		return 1
	fi
	sudo install -D -o root -g root -m "$mode" "$tmp" "$target" \
		|| die "cannot write $target"
	rm -f "$tmp"
	return 0
}

apt_update_once() {
	if [[ "$APT_UPDATED" == false ]]; then
		info "refreshing apt indexes"
		sudo apt-get update -qq || die "apt-get update failed"
		APT_UPDATED=true
	fi
}

pkg_installed() {
	[[ "$(dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null || true)" == "installed" ]]
}

# --- argument parsing ---------------------------------------------------

# Print the header comment block (lines 2-16) as help text, so usage and the
# top-of-file documentation cannot drift apart.
usage() {
	sed -n '2,16p' -- "${BASH_SOURCE[0]}" | sed 's/^#\{1,2\} \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--noninteractive | -y) NONINTERACTIVE=true ;;
	--reconfigure) RECONFIGURE=true ;;
	--no-reboot) ALLOW_REBOOT=false ;;
	-h | --help)
		usage
		exit 0
		;;
	*) die "unknown option: $1 (try --help)" ;;
	esac
	shift
done

# --- steps --------------------------------------------------------------

step_preflight() {
	log "Preflight"

	[[ $EUID -ne 0 ]] || die "run as your normal user, not root; bootstrap calls sudo where it needs to"
	command -v sudo >/dev/null || die "sudo is required"
	[[ -f "$PKG_LIST" ]] || die "packages.list not found; run this from inside the repo"

	local id="" version=""
	if [[ -r /etc/os-release ]]; then
		# os-release quotes values inconsistently: Debian ships ID=debian
		# but VERSION_ID="13". Strip quotes from both rather than relying
		# on which fields happen to be bare today.
		id="$(conf_value /etc/os-release ID)"
		version="$(conf_value /etc/os-release VERSION_ID)"
		id="${id//\"/}"
		version="${version//\"/}"
	fi
	if [[ "$id" != "debian" ]]; then
		warn "target is Debian 13; found '${id:-unknown}'. Continuing, but nothing is guaranteed."
	else
		dim "Debian ${version:-?}"
	fi

	if systemd-detect-virt --quiet 2>/dev/null; then
		IS_VM=true
		dim "virtualised ($(systemd-detect-virt 2>/dev/null)) - applying VM-safe defaults"
	fi

	# Ask for the password once, up front, rather than halfway through an
	# apt run where it is easy to miss.
	info "requesting sudo access"
	sudo -v || die "sudo authentication failed"
}

step_packages() {
	log "Packages"

	local pkgs=() missing=() unknown=() pkg
	mapfile -t pkgs < <(strip_comments "$PKG_LIST")
	[[ ${#pkgs[@]} -gt 0 ]] || die "packages.list is empty"

	for pkg in "${pkgs[@]}"; do
		pkg_installed "$pkg" || missing+=("$pkg")
	done

	if [[ ${#missing[@]} -eq 0 ]]; then
		info "all ${#pkgs[@]} packages present"
		return 0
	fi

	apt_update_once

	# Report every bad package name at once. Dying on the first one turns a
	# manifest audit into a slow game of whack-a-mole.
	for pkg in "${missing[@]}"; do
		[[ -n "$(apt-cache policy -- "$pkg" 2>/dev/null)" ]] || unknown+=("$pkg")
	done
	if [[ ${#unknown[@]} -gt 0 ]]; then
		die "not available in apt: ${unknown[*]}"
	fi

	info "installing ${#missing[@]}: ${missing[*]}"
	sudo apt-get install -y "${missing[@]}" || die "package installation failed"
	changed "installed ${#missing[@]} apt package(s)"
}

step_chrome() {
	log "Google Chrome"

	local keyring="/usr/share/keyrings/syos-google-chrome.gpg"
	local list="/etc/apt/sources.list.d/google-chrome.list"
	local repo_changed=false arch
	arch="$(dpkg --print-architecture)"

	if ! sudo test -s "$keyring"; then
		info "adding Google signing key"
		curl -fsSL --retry 3 --connect-timeout 20 https://dl.google.com/linux/linux_signing_key.pub |
			sudo gpg --dearmor --yes --output "$keyring" ||
			die "could not fetch Google's signing key"
		sudo chmod 0644 "$keyring"
		changed "added Google Chrome signing key"
		repo_changed=true
	fi

	# Chrome's postinst writes its own copy of this sources file on every
	# upgrade. Turning that off keeps the repo definition ours, and stops a
	# duplicate-source warning on every subsequent apt run.
	if write_root_file /etc/default/google-chrome 0644 <<EOF
# Managed by SyOS bootstrap.sh. Chrome adds its own apt source on upgrade
# unless this is disabled; SyOS defines the repository itself instead.
repo_add_once="false"
repo_reenable_on_distupgrade="false"
EOF
	then
		changed "pinned Chrome's apt repo management to SyOS"
	fi

	if write_root_file "$list" 0644 <<EOF
deb [arch=$arch signed-by=$keyring] https://dl.google.com/linux/chrome/deb/ stable main
EOF
	then
		changed "added Google Chrome apt repository"
		repo_changed=true
	fi

	if [[ "$repo_changed" == true ]]; then
		APT_UPDATED=false
	fi

	if pkg_installed google-chrome-stable; then
		info "google-chrome-stable present"
		return 0
	fi

	apt_update_once
	info "installing google-chrome-stable"
	sudo apt-get install -y google-chrome-stable || die "Chrome installation failed"
	changed "installed google-chrome-stable"
}

step_fonts() {
	log "Fonts"

	local dir="$HOME/.local/share/fonts/syos-iosevka"
	local stamp="$dir/.syos-version"

	if [[ -f "$stamp" ]] && [[ "$(cat "$stamp")" == "$IOSEVKA_VERSION" ]]; then
		info "Iosevka Term $IOSEVKA_VERSION present"
		return 0
	fi

	local url tmp zip
	url="https://github.com/be5invis/Iosevka/releases/download/v${IOSEVKA_VERSION}/PkgTTF-IosevkaTerm-${IOSEVKA_VERSION}.zip"
	tmp="$(mktemp -d)" || die "mktemp failed"
	zip="$tmp/iosevka.zip"

	info "downloading Iosevka Term $IOSEVKA_VERSION"
	if ! curl -fsSL --retry 3 --connect-timeout 20 -o "$zip" "$url"; then
		rm -rf "$tmp"
		warn "could not download Iosevka; the Hack fallback in the palette applies"
		warn "re-run ./bootstrap.sh when online to get the intended typeface"
		return 0
	fi

	rm -rf "$dir"
	mkdir -p "$dir"

	# The release carries roughly a hundred weights; SyOS uses four.
	unzip -j -o -q "$zip" \
		'*IosevkaTerm-Regular.ttf' '*IosevkaTerm-Bold.ttf' \
		'*IosevkaTerm-Italic.ttf' '*IosevkaTerm-BoldItalic.ttf' \
		-d "$dir" 2>/dev/null || true

	if ! compgen -G "$dir/*.ttf" >/dev/null; then
		info "expected style names absent; extracting every TTF instead"
		unzip -j -o -q "$zip" '*.ttf' -d "$dir" 2>/dev/null || true
	fi

	if ! compgen -G "$dir/*.ttf" >/dev/null; then
		rm -rf "$tmp" "$dir"
		warn "Iosevka archive held no TTF files; keeping the Hack fallback"
		return 0
	fi

	printf '%s\n' "$IOSEVKA_VERSION" >"$stamp"
	rm -rf "$tmp"
	fc-cache -f "$dir" >/dev/null 2>&1 || warn "fc-cache failed; fonts may need a re-login"
	changed "installed Iosevka Term $IOSEVKA_VERSION"
}

step_theme() {
	log "Theme"
	local output
	# generate.sh reports per-file status; capture it so bootstrap can fold
	# the result into its own change count.
	output="$("$REPO_DIR/theme/generate.sh")" || die "theme generation failed"
	printf '%s\n' "$output" | grep -E '^\s+(wrote|unchanged)' | sed 's/^ */    /' || true
	if printf '%s' "$output" | grep -q 'regenerated'; then
		changed "regenerated theme fragments from palette.conf"
	else
		info "theme fragments up to date"
	fi
}

# Connected display outputs, named the way Sway names them. Read from DRM
# rather than `swaymsg` because on a first install there is no Sway running
# yet: /sys/class/drm/card0-eDP-1 -> eDP-1.
detect_outputs() {
	local status name
	for status in /sys/class/drm/card*-*/status; do
		[[ -r "$status" ]] || continue
		[[ "$(cat "$status")" == "connected" ]] || continue
		name="$(basename "$(dirname "$status")")"
		printf '%s\n' "${name#*-}"
	done
}

ask() {
	local prompt="$1" default="$2" reply=""
	local -n _answer="$3"
	if [[ -n "$default" ]]; then
		read -r -p "    $prompt [$default]: " reply || true
	else
		read -r -p "    $prompt (blank for auto): " reply || true
	fi
	_answer="${reply:-$default}"
}

step_local_conf() {
	log "Machine configuration"
	mkdir -p "$SYOS_CONF_DIR"

	if [[ -f "$LOCAL_CONF" && "$RECONFIGURE" == false ]]; then
		info "keeping $(tilde "$LOCAL_CONF") (--reconfigure to change it)"
	else
		local outputs=() output scale font_size mode=""
		mapfile -t outputs < <(detect_outputs)

		output="*"
		[[ ${#outputs[@]} -gt 0 ]] && output="${outputs[0]}"
		scale="1"
		font_size="$(conf_value "$PALETTE" FONT_SIZE_DEFAULT 10)"

		if [[ "$NONINTERACTIVE" == true ]]; then
			info "non-interactive: output=$output scale=$scale font=$font_size"
		else
			echo
			if [[ ${#outputs[@]} -gt 0 ]]; then
				info "connected outputs: ${outputs[*]}"
			else
				info "no outputs detected (expected over SSH); '*' matches every display"
			fi
			dim "these are the only per-machine settings; everything else is in git"
			echo
			ask "Output name" "$output" output
			ask "Scale (1 = 100%, 1.5 = 150% on HiDPI)" "$scale" scale
			ask "Font size in points" "$font_size" font_size
			ask "Mode, e.g. 2880x1800@60Hz" "" mode
			echo
		fi

		[[ "$scale" =~ ^[0-9]+(\.[0-9]+)?$ ]] || die "scale must be a number, got '$scale'"
		[[ "$font_size" =~ ^[0-9]+(\.[0-9]+)?$ ]] || die "font size must be a number, got '$font_size'"

		if write_user_file "$LOCAL_CONF" 0644 <<EOF
# SyOS per-machine configuration.
#
# The only file in the system that is not versioned (design doc 3.5).
# Everything else lives in the repo and is identical across the fleet.
# Regenerate with: ./bootstrap.sh --reconfigure

SYOS_OUTPUT=$output
SYOS_SCALE=$scale
SYOS_FONT_SIZE=$font_size
SYOS_MODE=$mode
EOF
		then
			changed "wrote $(tilde "$LOCAL_CONF")"
		fi
	fi

	render_machine_fragments
}

render_machine_fragments() {
	local output scale mode
	output="$(conf_value "$LOCAL_CONF" SYOS_OUTPUT '*')"
	scale="$(conf_value "$LOCAL_CONF" SYOS_SCALE 1)"
	mode="$(conf_value "$LOCAL_CONF" SYOS_MODE '')"

	if {
		echo "# GENERATED by bootstrap.sh from $(tilde "$LOCAL_CONF") - do not edit."
		echo "# Change it with: ./bootstrap.sh --reconfigure"
		echo
		if [[ -n "$mode" ]]; then
			printf 'output "%s" mode %s scale %s\n' "$output" "$mode" "$scale"
		else
			printf 'output "%s" scale %s\n' "$output" "$scale"
		fi
		if [[ "$IS_VM" == true ]]; then
			echo
			echo "# Virtualised host: the display name can change between boots, so"
			echo "# every other output gets a usable fallback rather than none."
			echo "output * scale 1"
		fi
	} | write_user_file "$SYOS_CONF_DIR/sway-local.conf" 0644; then
		changed "wrote $(tilde "$SYOS_CONF_DIR/sway-local.conf")"
	fi

	if {
		echo "# GENERATED by bootstrap.sh - do not edit."
		echo "# Sourced by /usr/local/bin/syos-session before Sway starts."
		echo
		if [[ "$IS_VM" == true ]]; then
			echo "# wlroots asks the GPU to draw the cursor on a hardware plane, which"
			echo "# virtual GPUs either lack or implement wrongly: the pointer goes"
			echo "# invisible or lands at the wrong position. Software cursors cost a"
			echo "# little latency and are correct everywhere."
			echo "export WLR_NO_HARDWARE_CURSORS=1"
		else
			echo "# Physical hardware: no workarounds needed."
		fi
	} | write_user_file "$SYOS_CONF_DIR/env.conf" 0644; then
		changed "wrote $(tilde "$SYOS_CONF_DIR/env.conf")"
	fi
}

# Files that stow would refuse to overwrite because a real file already sits
# in the target. Moving them aside keeps bootstrap re-runnable on a machine
# that was configured by hand first.
backup_conflicts() {
	local pkg="$1"
	local src="$STOW_SRC/$pkg"
	local file rel target
	while IFS= read -r -d '' file; do
		rel="${file#"$src"/}"
		target="$HOME/$rel"
		if [[ -e "$target" && ! -L "$target" ]]; then
			mkdir -p -- "$BACKUP_DIR/$(dirname -- "$rel")"
			mv -- "$target" "$BACKUP_DIR/$rel"
			changed "moved pre-existing $(tilde "$target") to $(tilde "$BACKUP_DIR/$rel")"
		fi
	done < <(find "$src" -type f -print0)
}

# How many files stow is about to (re)link. Counted here rather than parsed
# out of `stow --simulate`, which reports a full relink every time and would
# make an unchanged run look busy.
stow_pending() {
	local pkg="$1"
	local src="$STOW_SRC/$pkg"
	local file rel target count=0
	while IFS= read -r -d '' file; do
		rel="${file#"$src"/}"
		target="$HOME/$rel"
		if [[ -L "$target" ]] &&
			[[ "$(readlink -f -- "$target")" == "$(readlink -f -- "$file")" ]]; then
			continue
		fi
		count=$((count + 1))
	done < <(find "$src" -type f -print0)
	[[ "$count" -gt 0 ]] && printf '%s' "$count"
	return 0
}

step_stow() {
	log "Configuration (stow)"

	local pkg pending
	for pkg in "${STOW_PACKAGES[@]}"; do
		[[ -d "$STOW_SRC/$pkg" ]] || die "stow package missing: stow/$pkg"
		backup_conflicts "$pkg"
		pending="$(stow_pending "$pkg")"
		# --no-folding links individual files instead of symlinking whole
		# directories, so ~/.config/sway stays a real directory that other
		# things can write into without writing into the repo.
		stow --restow --no-folding --dir="$STOW_SRC" --target="$HOME" "$pkg" \
			|| die "stow failed for $pkg"
		if [[ -n "$pending" ]]; then
			changed "linked $pkg ($pending file(s))"
		else
			dim "$pkg already linked"
		fi
	done
}

step_session() {
	log "Login session"

	if write_root_file /usr/local/bin/syos-session 0755 <"$REPO_DIR/system/syos-session"; then
		changed "installed /usr/local/bin/syos-session"
	fi

	# Debian's greetd package creates the _greetd system user.
	local greeter_user="_greetd"
	id -u "$greeter_user" >/dev/null 2>&1 || greeter_user="greeter"
	id -u "$greeter_user" >/dev/null 2>&1 ||
		die "no greetd system user found; is the greetd package installed?"

	if write_root_file /etc/greetd/config.toml 0644 <<EOF
# Managed by SyOS bootstrap.sh - edits are overwritten on the next run.

[terminal]
vt = 1

[default_session]
command = "tuigreet --time --remember --asterisks --cmd /usr/local/bin/syos-session"
user = "$greeter_user"
EOF
	then
		changed "configured greetd"
	fi

	if ! systemctl is-enabled --quiet greetd.service 2>/dev/null; then
		sudo systemctl enable greetd.service >/dev/null 2>&1 ||
			die "could not enable greetd.service"
		changed "enabled greetd.service"
	fi

	# greetd is wanted by graphical.target, which a minimal netinstall does
	# not boot into by default.
	if [[ "$(systemctl get-default)" != "graphical.target" ]]; then
		sudo systemctl set-default graphical.target >/dev/null 2>&1 ||
			die "could not set the default systemd target"
		changed "set default boot target to graphical.target"
	fi
}

step_summary() {
	log "Summary"

	if [[ ${#CHANGES[@]} -eq 0 ]]; then
		info "no changes - this machine already matches the repo"
	else
		info "${#CHANGES[@]} change(s):"
		local change
		for change in "${CHANGES[@]}"; do
			printf '      %s-%s %s\n' "$C_GREEN" "$C_RESET" "$change"
		done
	fi

	if [[ -d "$BACKUP_DIR" ]]; then
		echo
		warn "pre-existing config was moved to $(tilde "$BACKUP_DIR")"
	fi

	echo
	dim "output   $(conf_value "$LOCAL_CONF" SYOS_OUTPUT '*') at scale $(conf_value "$LOCAL_CONF" SYOS_SCALE 1)"
	dim "font     $(conf_value "$PALETTE" FONT_FAMILY) $(conf_value "$LOCAL_CONF" SYOS_FONT_SIZE "$(conf_value "$PALETTE" FONT_SIZE_DEFAULT)")pt"
	dim "session  greetd -> tuigreet -> syos-session -> sway"
	[[ "$IS_VM" == true ]] && dim "hardware virtualised (software cursors enabled)"

	echo
	if [[ ${#CHANGES[@]} -eq 0 ]]; then
		info "Nothing to do. Reboot only if you want to."
		return 0
	fi

	info "SyOS is installed. Reboot to land in the session."
	if [[ "$ALLOW_REBOOT" == false || "$NONINTERACTIVE" == true ]]; then
		return 0
	fi

	local reply=""
	read -r -p "    Reboot now? [y/N]: " reply || true
	if [[ "$reply" =~ ^[Yy]$ ]]; then
		sudo systemctl reboot
	fi
}

main() {
	step_preflight
	step_packages
	step_chrome
	step_fonts
	# Order matters: the theme reads SYOS_FONT_SIZE out of local.conf, so the
	# machine questions have to be answered before fragments are rendered,
	# and the fragments have to exist before stow links them.
	step_local_conf
	step_theme
	step_stow
	step_session
	step_summary
}

# Only run when executed. Sourcing the script gives a test harness access to
# the parsing helpers without installing anything.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
