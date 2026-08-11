# SyOS

A single-window work environment on Debian.

One frame, always. Browser, editor, terminal, calendar — everything opens as a
**tab** in the same frame, never as a free-floating window. Dense, dark and
terminal-forward: small monospace type, 1px borders, no gaps, one accent
color. Every action is reachable with the mouse.

SyOS is not a distro. It is configuration, a few small programs and one
install script layered on stock Debian 13, which keeps the kernel, packages
and security updates.

```
┌──────────────────────────────────────────────┐
│  SyOS: sway config · bar · themed TUI tools  │
│        focus daemon · bootstrap.sh           │
├──────────────────────────────────────────────┤
│  Debian 13: sway/wlroots · pipewire ·        │
│             systemd · kernel · apt           │
└──────────────────────────────────────────────┘
```

## Install

On a minimal Debian 13 install (standard utilities and SSH only, no desktop):

```sh
sudo apt install git
git clone https://github.com/devinbowler/SyOS.git syos
cd syos
./bootstrap.sh
```

Bootstrap installs the package manifest, adds Chrome's apt repository, fetches
the pinned Iosevka release, renders the theme, links every config with GNU
stow, asks three questions about this specific machine, and sets up the login
session. Then reboot.

It is **idempotent**: run it again after `git pull` and it applies only what
changed. A second run on an unchanged machine reports `no changes`.

```sh
./bootstrap.sh --reconfigure      # re-ask output / scale / font size
./bootstrap.sh --noninteractive   # accept detected defaults, never prompt
./bootstrap.sh --help
```

## Status

**Phase 0 — Skeleton. Complete.** Debian boots into a themed, tabbed Sway
session with a working bar, foot and Chrome.

Not yet built: the mouse-first control bar and built-in tools (Phase 1), focus
enforcement and the dev-container wrapper (Phase 2), the custom scheduler
(Phase 3), a preseeded install ISO (Phase 4).

The roadmap is in [`docs/syos-design-doc.md`](docs/syos-design-doc.md#6-roadmap).

## Making it yours

Every color, and the typeface, come from one file:

```sh
$EDITOR theme/palette.conf
./bootstrap.sh
```

That regenerates the sway, foot, waybar and fuzzel fragments together, so
nothing drifts out of step. Per-machine settings — which output, what scale,
what font size — live in `~/.config/syos/local.conf`, the only configuration
file outside git. Everything else is identical across machines by design.

## Layout

| Path | |
|---|---|
| `bootstrap.sh` | The only entry point. Idempotent. |
| `packages.list` | apt manifest, verified against trixie |
| `theme/` | `palette.conf` and the generator that renders it |
| `stow/` | Config packages, mirroring `$HOME` |
| `system/` | Installed to `/usr/local/bin` (the session launcher) |
| `focusd/` | Focus daemon — Phase 2 |
| `tools/` | Lint and line-ending helpers |
| `docs/` | Design doc, build plan, decisions, testing |

## Documentation

- [Design doc](docs/syos-design-doc.md) — what SyOS is and why
- [Build plan](docs/syos-build-plan.md) — phases, conventions, acceptance
- [Decisions](docs/decisions.md) — where reality diverged from the plan
- [Testing](docs/testing.md) — the VirtualBox loop and acceptance checklists
