# focusd — Phase 2

Empty on purpose. Focus enforcement is Phase 2 (build plan section 4) and the
phase order is strict, so nothing here is built until Phase 1's acceptance
criteria pass.

What lands here:

| File | Installed to | Owner |
|---|---|---|
| `syos-focusd` | `/usr/local/sbin` | root |
| `syos` | `/usr/local/bin` | root, run by the user |
| `profiles.conf` | `/etc/syos/` | root, 0600 |
| `syos-focusd.service` | systemd | root |

This is the only root-owned part of SyOS. Everything else is user-space, and
the user CLI reaches the daemon over a Unix socket at `/run/syos/focusd.sock`
with an allow-listed command set: `start`, `status`, `extend`.

There is deliberately **no stop command**. Sessions end on their timer;
escaping early requires a reboot. That residual escape is documented honestly
rather than papered over — you own the machine, so the goal is friction that
outlasts an impulse, not a literal prison.

See design doc 4.5 for the three levels and build plan section 4 for the task
list and acceptance criteria.
