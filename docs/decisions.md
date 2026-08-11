# Decisions

A running log of places where reality diverged from the design doc, plus
choices the build plan explicitly left open. Newest phase last.

The rule (build plan ground rule 10): if a design-doc assumption turns out
wrong on real Debian 13, fix it, write it down here, and keep moving. Do not
quietly redefine what "done" means.

---

## Phase 0

### Iosevka is not packaged in Debian 13

**Open item:** build plan 9, "Iosevka packaging on trixie (package vs vendored
TTF download in bootstrap)."

`fonts-iosevka` exists only in `sid` and `experimental`. It is **not** in
trixie, so `apt install fonts-iosevka` fails on the target.

**Decision:** vendor it. `bootstrap.sh` downloads a pinned release from
GitHub (`PkgTTF-IosevkaTerm-34.8.0.zip`) into
`~/.local/share/fonts/syos-iosevka` and stamps the version in a dotfile so
re-runs are no-ops. Pinning rather than tracking latest is what keeps the two
laptops rendering identically.

Two follow-on choices:

- **IosevkaTerm, not plain Iosevka.** The Term variant fixes the advance
  width of arrows and box-drawing glyphs, which is what a terminal-forward UI
  actually needs. Family name is `Iosevka Term`.
- **Only four styles are extracted.** The release archive carries roughly a
  hundred weights; SyOS uses Regular, Bold, Italic and BoldItalic.

**Failure mode is soft.** If the download fails (offline install, GitHub
down), bootstrap warns and continues. `fonts-hack` comes from apt and is
listed as the fallback in `theme/palette.conf`, so every config emits
`Iosevka Term, Hack, monospace` and the system stays legible instead of
falling back to whatever fontconfig picks.

### greetd and tuigreet are both in trixie

**Open item:** build plan 9, "greetd/tuigreet availability on stable vs
backports; fallback = agetty autologin."

Both are in trixie (`greetd` 0.10.3-4, `tuigreet` 0.9.1-5). **The agetty
autologin fallback is not needed and was not built.** Login is
`greetd -> tuigreet -> /usr/local/bin/syos-session -> sway`.

Bootstrap also runs `systemctl set-default graphical.target`, because a
minimal netinstall boots to `multi-user.target` and greetd is ordered under
`graphical.target` — without this the machine reboots into a text console and
looks like the install failed.

### WLR_NO_HARDWARE_CURSORS is still the right VM workaround

Checked because ground rule 8 depends on it and the variable has been rumoured
removed. It is still read by wlroots 0.18 (which Sway 1.10.1 in trixie uses)
and still documented upstream. Sway 1.10 removed the `xwayland` build option
and disabled legacy `wl_drm`, but nothing about software cursors.

Applied only when `systemd-detect-virt` reports virtualisation, written to
`~/.config/syos/env.conf` and sourced by `syos-session`. Real hardware gets no
workaround and no cursor latency.

### A `system/` directory was added to the repo layout

Not in the layout in build plan 1. `system/syos-session` is installed to
`/usr/local/bin`, not stowed into `$HOME`.

**Why:** the greeter needs an absolute path that resolves before the user's
session exists, and `~/.local/bin` is the wrong place for something greetd
executes. Keeping it out of `stow/` also stops it being half-owned by two
deploy mechanisms. `focusd/` keeps the same shape in Phase 2 for the same
reason: things root or the greeter runs are not dotfiles.

### Generated theme fragments are gitignored build artifacts

`theme/generate.sh` writes four fragments into `stow/`:

| Fragment | Pulled in by |
|---|---|
| `stow/sway/.config/sway/theme.conf` | sway `include` |
| `stow/foot/.config/foot/theme.ini` | foot `include=` |
| `stow/waybar/.config/waybar/theme.css` | CSS `@import` |
| `stow/fuzzel/.config/fuzzel/theme.ini` | fuzzel `include=` |

All four programs support an include directive, so hand-written config and
generated color can stay in separate files. The alternative — templating
whole config files — would have made every config unreadable in the repo.

They are gitignored: committing them invites someone to edit the generated
copy and lose the change on the next run. `bootstrap.sh` always regenerates
before stowing, so a fresh clone is never missing them.

The palette also carries `BAR_HEIGHT`, which is why `config.jsonc` sets
`"height": 0` (auto) and lets CSS `min-height` drive the bar. Otherwise bar
height would be the one visual constant living outside `palette.conf`.

### Chrome's apt repository is managed by SyOS, not by Chrome

The Chrome package rewrites `/etc/apt/sources.list.d/google-chrome.list` on
every upgrade, which would fight bootstrap's copy and produce duplicate-source
warnings forever. Bootstrap writes `/etc/default/google-chrome` with
`repo_add_once="false"` before installing, and defines the repository itself
with an explicit `signed-by` keyring at
`/usr/share/keyrings/syos-google-chrome.gpg`.

### Deferred to Phase 1, deliberately

Phase 0 acceptance only asks that Chrome open as a themed tab next to foot.
These are Phase 1 work and are *not* done:

- **Chrome Wayland flags and forced dark.** Chrome runs under XWayland for
  now. It tabs correctly, which is what Phase 0 tests; it will be slightly
  soft on a HiDPI panel until the desktop-entry override lands with the rest
  of the theming pass.
- **Icon font for the bar.** Phase 0's bar uses text labels (`vol`, `bat`,
  `offline`) so nothing depends on glyph coverage. The window-control cluster
  in design doc 4.2 needs real symbols; choosing between a Nerd Font patch
  and `fonts-font-awesome` is a Phase 1 call.
- **GTK dark theming, VSCode, all built-ins** (calcurse, yazi, btop, nvim).

### Small additions beyond the Phase 0 task list

- **`bootstrap.sh --noninteractive`.** Build plan 6 wants this for the Phase 4
  preseed. Added now because the Phase 0 idempotency test wants an unattended
  second run, and building it later would mean retrofitting prompts.
- **`--reconfigure`** to re-ask the machine questions, since the first run is
  otherwise the only chance to set scaling.
- **`tools/lint.sh` and `tools/normalize-eol.ps1`.** The repo is authored on
  Windows and runs on Debian. A CRLF that reaches a shell script fails with
  `bad interpreter: /usr/bin/env bash^M` before anything useful is printed, so
  normalisation is a tool rather than a habit. `.gitattributes` pins `eol=lf`.
- **Sway keeps five stock keybindings** (`Mod+Return`, `Mod+d`, `Mod+Shift+q`,
  `Mod+Shift+c`, `Mod+Shift+e`). Writing our own config drops Sway's defaults
  entirely, which would leave no way to recover a session where the bar failed
  to start. They are undocumented in the UI and nothing depends on them, which
  is exactly the "dormant layer" of design doc 4.1.
