# iso — Phase 4

Empty on purpose. Portability is Phase 4 (build plan section 6).

What lands here: a Debian preseed that automates the minimal install and a
`build.sh` that remasters the official netinstall ISO with it (via `xorriso`),
producing `syos-install.iso`. First boot runs `bootstrap.sh --noninteractive`,
deferring only the per-machine scaling prompt to first login.

Until then the install path is the one in the README: stock Debian netinstall,
then clone and run `./bootstrap.sh`.
