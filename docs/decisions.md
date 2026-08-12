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

### Corrected after first VM boot: greetd must not share VT 1

The first bootstrap put greetd on `vt = 1`, which is the greetd default and
what most examples show. On Debian that VT already belongs to `getty@tty1`.
The two contend for it and greetd loses quietly: `systemctl status greetd`
reports `active (running)`, the cgroup contains only `greetd` with no greeter
child, the journal says nothing beyond `Started greetd.service`, and the
machine sits at a plain `debian login:` prompt looking like bootstrap failed.

**Decision:** `vt = 7`. It is free on a netinstall, it is where display
managers have historically lived, and leaving tty1 to agetty preserves a
working text console to recover from when the graphical session breaks — which
is worth more than matching the upstream default.

---

## Phase 1

### The palette is neutral grey with a violet accent

The Phase 0 palette was deliberately blue-tinted (`BG=0d0f12`) with a
grey-green foreground. On a real panel it read as blue, which is not the
intent of design doc 4.4 ("near-black, one accent").

**Decision:** every surface value is now strictly neutral — R, G and B are
equal in `BG`, `BG_ALT`, `BG_SEL`, `FG`, `FG_DIM` and `BORDER` — so nothing in
the chrome carries a color cast. The single accent is violet (`a878f0`),
replacing the desaturated green the design doc suggested. `BAR_HEIGHT` went
from 24 to 28 to give the bar's buttons a real click target.

Because the accent is now also the launcher's resting color, it is the one
saturated thing on screen, which is the effect design doc 4.4 asked for.

### The calendar is Google Calendar in a Chrome app window

**Deviation from the design doc**, which specifies `calcurse` as the v1
calendar and a custom scheduler later.

`syos-calendar` runs `google-chrome --app=<url>`. The `--app` flag drops the
omnibox, tab strip and bookmarks bar, so the page fills a sway tab like a
native window.

**Why:** the requirement is a full-page view you can actually schedule events
in. calcurse is a TUI agenda — it lists and it edits, but it is keyboard-driven
and does not give the month-grid, drag-to-create surface that "schedule
events" implies. Rendering the real thing is the honest version of this
feature until the custom scheduler exists.

`SYOS_CALENDAR_URL` in `~/.config/syos/env.conf` overrides the URL, so a
self-hosted or work calendar is a one-line change and nothing about the
approach is Google-specific.

### Bar buttons focus rather than launch duplicates

Every tool button routes through `syos-summon`, which searches the sway tree
for a matching window, focuses it by `con_id` if found, and otherwise execs
the command. Without this, a bar button is a trap: it looks like a tab
switcher and behaves like a spawner, so five clicks give five terminals.

Windows are matched on app_id *or* class (one helper then covers native
Wayland and XWayland clients alike) and, crucially, **also on title**.

The title tests exist because of Chrome. A second `google-chrome` invocation
does not start a second browser — it hands the request to the running one
("Opening in existing browser session") and exits. Flags that configure the
process, `--class` among them, are therefore ignored whenever Chrome is
already open, so the calendar window's class depends on the accident of
whether you had a browser window up. Its *title* is `Google Calendar ...`
either way. Hence `-t` to find the calendar, and `-x` so the browser button
does not grab the calendar window instead.

Focusing by `con_id` rather than re-running the criteria through `swaymsg`
keeps one regex dialect in play. sway's criteria and jq's `test()` are
different engines, and a match decided in one but executed in the other is a
bug waiting for an unusual window title.

### Reverted: there is one workspace, not five

The five named rooms below were built, used, and removed after the first
session with them.

They failed for a reason worth recording: the bar ended up with two rows of
clickable labels that meant different kinds of thing. `Board Work Web Comms
Ops` sat immediately above sway's real tab strip, so `Web` read as a tab that
already had a browser in it. Clicking it showed an empty screen, which looks
like a bug rather than an empty room.

**Deviation from design doc 3.2.** One frame, one strip of tabs, everything
you open joins it. The workspace concept is not exposed in the interface at
all; sway still has workspaces, SyOS just never shows or uses more than one.

### Sway cannot put a close button on a tab

Requested: an `x` on each tab, as in Chrome or VS Code, so closing something
does not require focusing it first.

Sway draws tab titles internally and exposes no mechanism for placing a
widget inside one. `title_format` accepts text and Pango markup, not buttons,
and there is no click region within a title beyond the title itself. This is
not a configuration gap; it is absent from the compositor.

**Decision:** `bindsym button2 kill` — middle-click any tab to close it.
Without `--whole-window` the binding is confined to the tab strip and window
border, so middle-click paste inside a terminal still works. It needs no
prior focus, which was the actual requirement, and it is the same gesture
that closes a tab in Chrome, Firefox and VS Code. The bar keeps an `x` for
the focused window, since a gesture with no visible affordance cannot be the
only path in a mouse-first system.

The alternative, replacing sway's tab strip with a waybar `wlr/taskbar`, was
rejected for now: it renders icons rather than titles and would mean the
frame's own titlebars say one thing while the bar above says another.

### Everything SyOS renders is lower case

Small, quiet, terminal-like. Capitals are reserved for content - the window
titles in the tab strip, which come from the applications themselves.

Two places resisted. Waybar's format strings cannot change case, so the clock
is a `custom` module piping `date` through `tr` rather than the built-in
`clock` module; the built-in's calendar tooltip is lost, which is acceptable
now that a calendar button exists. Application names in the launcher come
from their `.desktop` files and stay as their authors wrote them.

### Workspaces are named and persistent, but nothing is assigned to them

Named `0:Board`, `1:Work`, `2:Web`, `3:Comms`, `4:Ops` per design doc 3.2.
Sway destroys a workspace as soon as it empties, so waybar's
`persistent-workspaces` pins all five buttons to the bar permanently. The set
of rooms has to be visible to be clickable; a mouse-first system cannot ask
you to remember that workspace 3 exists.

**Deviation from design doc 3.2:** there are no `assign` rules. The first
version assigned Chrome to Web, and the result was a bar button that looked
broken — you clicked `web`, sway does not follow a window to the workspace it
was assigned to, and nothing appeared to happen. Filing windows away
invisibly also contradicts the one-frame promise in design doc 3.3: things
open as a tab where you are looking. The rooms remain as places you choose to
go.

### `exec swaybg --color $syos_bg` needed quotes

Sway expands config variables textually and passes the result to `sh`, so
`--color $syos_bg` became `--color #080808`, where `#080808` is a shell
comment. swaybg ran with a bare `--color`, printed its usage into
`~/.local/state/syos/sway.log` and exited, leaving the desktop unpainted.

Worth remembering generally: any palette value interpolated into an `exec`
line has to be quoted, because every color in this system starts with `#`.

### VMs also get `WLR_RENDERER=pixman`

`WLR_NO_HARDWARE_CURSORS=1` alone was not enough on VirtualBox. Dragging the
pointer smeared pixels across the screen and newly-mapped surfaces did not
appear at all: the GL path only repaints the damaged region, and the virtual
GPU never refreshes the rest of the frame. The failure is worse than ugly,
because a launcher that opens but is never drawn is indistinguishable from a
button that does nothing.

Rendering on the CPU with pixman sidesteps the whole damage-tracking path. For
a UI with no animation, no compositing effects and no transparency, at VM
resolutions, it is fast enough that the difference is not visible.

Written to `~/.config/syos/env.conf` only when `systemd-detect-virt` reports
virtualisation, alongside the cursor workaround. Real hardware keeps the GL
renderer.

### yazi is vendored from upstream, not from the community apt repo

yazi is not in trixie. There is one apt source for it, `deb.griffo.io`, an
unofficial repository maintained by a single person.

**Decision:** vendor the upstream release binary, pinned to v26.5.6, the same
pattern already used for Iosevka. Installed to `/usr/local/bin`, with the
version stamped at `/usr/local/share/syos/yazi-version` so re-runs are
no-ops. This keeps the trust boundary at the upstream project and keeps the
two laptops on an identical build.

Verified before shipping: the release URL resolves, the archive lays out as
`yazi-<target>/yazi` and `.../ya` so `unzip -j '*/yazi' '*/ya'` extracts both,
and the extracted binary reports 26.5.6.

The file button opens it as `foot -a syos-files yazi`. `foot -a` sets the
Wayland app_id, which gives the file browser a tab identity distinct from a
plain terminal — otherwise the summon matcher cannot tell the two apart.

### Reverted: focus follows the click, not the pointer

`focus_follows_mouse yes` is actively hostile in a system whose controls live
on a bar at the top of the screen. Travelling to the close button drags focus
across every window the pointer crosses, so the button acts on whatever was
passed over last. The workaround people discover is an arc around the other
windows, which is not something an interface should teach.

`focus_follows_mouse no`. Clicking a tab focuses it; that is the only thing
that focuses it. This also let fuzzel's `exit-on-keyboard-focus-loss` be
turned back on, so the launcher dismisses when you click elsewhere, which was
impossible before: the menu vanished as the pointer crossed a window on the
way to it.

### Reverted: Obsidian removed, no third-party notes app

Installed, used, removed in the same evening. The objection was not the
software, it was that it is a world of its own — its own vault concept, its
own interface language, its own idea of what a window is — dropped into a
system whose entire premise is one coherent frame. It read as foreign because
it is foreign.

The flatpak machinery in `bootstrap.sh` stays, since it was the right answer
to a real question and the next app that Debian does not package will want
it. But `flatpak` moved out of `packages.list`: bootstrap now installs it on
demand, only when `packages-flatpak.list` has an entry, so an empty manifest
costs no disk.

### Notes are a SyOS application, not an installed one

The requirement was: select text and a formatting bar appears over it, small
terminal-like type, files on disk. Nothing packaged does all three. Every
editor with that selection toolbar is a large Electron or Flutter application
carrying its own visual world — the exact objection that removed Obsidian —
and every editor that looks right is keyboard-driven and has no toolbar
because it has no mouse-first concept at all. Notion itself has no Linux
build. MarkText and AppFlowy were the near misses; each drops one leg.

So `syos-notes` is ours: GTK4 and Python, both stock Debian, styled from
`theme/palette.conf` like everything else. This is a deliberate exception to
apt-first — the policy exists so we do not maintain what someone else already
maintains, and here nobody does.

Two design choices inside it are worth defending:

**The buffer holds literal markdown, not rich text with a serialiser behind
it.** Styling is applied over the real characters, so `**bold**` shows dimmed
asterisks around bold text. Saving is therefore lossless and trivial, the
cursor is never lying about where it is, and the files stay editable in nvim
and greppable from the terminal. Showing the markup is also the honest thing
for a system like this: you are editing a text file.

**No vault, no database, no index.** `~/notes/*.md`, sorted by mtime, with the
filename tracking the first heading. Nothing here owns your data.

Colour as a formatting option was cut from the first version. Markdown has no
colour, and every way of adding it — HTML spans, invented syntax — makes the
file worse to read as text. Highlight (`==like this==`) covers what colour was
actually wanted, which is making a line stand out.

### Superseded: notes were briefly Obsidian, over flatpak

**First use of flatpak**, and the first entry in `packages-flatpak.list`.
Debian ships no comparable markdown editor and Obsidian has no `.deb` at all.

The requirement was real formatting power — bold, colour, highlight, nested
bullets — over files that stay plain markdown and remain readable in nvim.
Native GTK options in Debian (Apostrophe) do the minimal-editor half well but
have no highlight or colour. The cost is honest: Electron, several hundred
megabytes, and a runtime download on first bootstrap.

Installed `--user` rather than system-wide, along with the flathub remote:
these are the person's applications, not the machine's, and after the first
run nothing about them needs root.

The bar button matches on the window title ending in `Obsidian` rather than on
a class, because a flatpak's window class is not reliably its application id.

Deliberately **not** done yet: theming Obsidian to match the palette. It takes
a CSS snippet plus an `appearance.json` inside the vault, and the vault does
not exist until the user creates one on first run.

### An icon theme was added

`papirus-icon-theme` from apt. fuzzel renders the icon from each `.desktop`
file, and with no theme installed the launcher is a plain text list. This is
the first half of the Phase 0 deferral on icons; the bar's own controls still
use text and ASCII-safe glyphs (`+`, `×`, `|`, `—`) so nothing on the bar
depends on Nerd Font coverage.
