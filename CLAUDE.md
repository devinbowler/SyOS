# CLAUDE.md — agent entry point

Read these before doing any work, in this order:

1. `docs/syos-design-doc.md` — **what and why**. Source of truth.
2. `docs/syos-build-plan.md` — **how**. Phase order, conventions, acceptance
   criteria.
3. `docs/decisions.md` — what already turned out to be wrong, and what was
   decided instead. Read it before re-litigating anything.

If the design doc and the build plan conflict, **the design doc wins** — and
say so rather than silently picking one.

## Current state

**Phase 0 is complete.** Phase 1 (the mouse-first panel) is next; its task
list is build plan section 3.

## The rules that get broken most often

- **Phase order is strict.** Do not start Phase N+1 until Phase N's acceptance
  criteria actually pass. Every phase must leave the system daily-drivable.
- **Idempotency is not optional.** `./bootstrap.sh` twice in a row must print
  `no changes` the second time. Compare content before writing; route every
  mutation through `changed()` so the summary stays truthful.
- **Nothing may require the keyboard.** Every action needs a click path. Sway's
  stock keybinds exist as a dormant recovery layer and nothing may depend on
  them. A designed keybind scheme is Phase 5.
- **No config outside the repo** except `~/.config/syos/local.conf` and the
  two fragments bootstrap generates next to it.
- **Plain, boring tech.** Bash for glue, Python 3 (stdlib first) for
  `syos-focusd` and the `syos` CLI. Shell passes `shellcheck`, Python passes
  `ruff`.
- **Do not fake acceptance.** If something cannot be verified from here, say
  which check is outstanding. Write real deviations into `docs/decisions.md`.

## Where things live

```
bootstrap.sh         the only entry point; idempotent
packages.list        apt manifest, verified against trixie
theme/palette.conf   every color in the system
theme/generate.sh    renders the palette into stow/ fragments
stow/<app>/          stow packages, mirroring $HOME
system/              installed to /usr/local/bin, not stowed
focusd/              Phase 2, root-owned
tools/lint.sh        line endings + shellcheck
```

Two conventions worth knowing before editing:

- **Generated fragments are gitignored.** `theme/generate.sh` writes
  `theme.conf` / `theme.ini` / `theme.css` into `stow/`. Editing those loses
  your work on the next run — edit `theme/palette.conf`.
- **This repo is authored on Windows and runs on Debian.** A CRLF in a shell
  script breaks it with `bad interpreter: ...bash^M`. Run `tools/lint.sh`
  (or `tools/normalize-eol.ps1` on Windows) before committing.

## Verifying work

`docs/testing.md` has the VirtualBox loop and the per-phase acceptance lists.
The parts that need no VM — `shellcheck`, and running `theme/generate.sh`
twice to confirm the second run changes nothing — should be run every time.
