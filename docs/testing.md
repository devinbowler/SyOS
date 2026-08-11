# Testing SyOS

Everything here runs from Windows against a VirtualBox VM. The point is that
the VM exercises the *exact* install path the laptops will get (design doc 8),
so a passing VM run is real evidence and not a simulation.

What the VM cannot prove: HiDPI scaling on the actual panels, GPU behaviour,
battery and suspend, webcam and microphone in a real screen share. Those are a
separate on-metal checklist and only block sign-off on hardware, never
iteration here.

---

## 1. One-time setup

### Create the VM

1. Install VirtualBox on Windows.
2. Download the Debian 13 (trixie) **netinst** ISO for amd64 from
   <https://www.debian.org/distrib/netinst>.
3. New VM, type Linux / Debian (64-bit), with:

| Setting | Value | Why |
|---|---|---|
| RAM | 4096 MB or more | Chrome plus a compositor |
| CPUs | 2 or more | |
| Disk | 25 GB | |
| EFI | **Enabled** | Matches how the laptops boot |
| Graphics controller | VMSVGA | The one wlroots gets along with |
| Video memory | 128 MB | |
| 3D acceleration | Enabled | |
| Network | NAT | Bootstrap downloads packages, Chrome and the font |

### Install Debian

Run the installer normally, and at **Software selection** untick everything
except **standard system utilities** and **SSH server**. No desktop
environment — SyOS is what gets installed on top, and installing one here
would invalidate the test.

Create your user, finish, reboot, log in at the text console.

### Snapshot immediately

```
VBoxManage snapshot "syos-test" take fresh-debian --description "Minimal Debian 13, pre-SyOS"
```

This snapshot is the whole point of the loop: it is what makes bootstrap
cheap to re-test. Restoring takes seconds; reinstalling Debian does not.

---

## 2. The loop

Run this for every phase, and again whenever `bootstrap.sh` changes.

```
# 1. Back to a clean machine
VBoxManage snapshot "syos-test" restore fresh-debian
VBoxManage startvm "syos-test"

# 2. Inside the VM
sudo apt update && sudo apt install -y git
git clone https://github.com/devinbowler/SyOS.git syos
cd syos
./bootstrap.sh
```

Answer the three machine questions. In VirtualBox the detected output is
usually `Virtual-1`; scale `1` and the default font size are correct there.

Reboot when prompted. You should land on the tuigreet login screen, and after
logging in, in Sway with a foot terminal open and a bar across the top.

### Then prove it is idempotent

```
cd ~/syos && ./bootstrap.sh
```

The summary must read **`no changes - this machine already matches the repo`**.
Anything else is a bug in bootstrap, not a quirk. The most common cause is a
step that writes a file unconditionally instead of comparing content first.

---

## 3. Phase 0 acceptance

Restore the snapshot, run the loop, then check each of these.

- [ ] `./bootstrap.sh` completes with no errors on a clean VM.
- [ ] Reboot lands at tuigreet, and logging in starts Sway.
- [ ] A foot terminal is open, using Iosevka Term on the near-black
      background. Confirm the font resolved rather than fell back:
      `fc-match "Iosevka Term"` should name an Iosevka file, not Hack or
      DejaVu.
- [ ] Waybar is across the top: workspace numbers left, window title centre,
      network / volume / clock right. Colors match the palette.
- [ ] **Clicking** a workspace button switches workspace. Scrolling over the
      workspace module cycles. No keyboard involved.
- [ ] `google-chrome` from the foot shell opens Chrome as a **tab beside**
      foot, not as a floating window and not as a tiled split. Both tab labels
      are visible in one strip.
- [ ] The mouse cursor is visible and tracks correctly (this is what
      `WLR_NO_HARDWARE_CURSORS=1` buys; if the pointer is invisible or offset,
      check `~/.config/syos/env.conf` was written).
- [ ] Second `./bootstrap.sh` reports zero changes.
- [ ] `tools/lint.sh` is clean.

### If Sway does not start

The greeter drops you back to the login screen with no explanation, which is
the worst possible error message. The real one is here:

```
cat ~/.local/state/syos/sway.log
```

`syos-session` writes every session there and keeps the previous run as
`sway.log.1`.

---

## 4. Checks that do not need a VM

From the repo on Windows, with WSL available:

```
# Line endings and shellcheck
wsl -d Ubuntu -- env SHELLCHECK=~/.local/bin/shellcheck bash tools/lint.sh

# Theme generation, twice: the second run must report every file unchanged
wsl -d Ubuntu -- bash theme/generate.sh
wsl -d Ubuntu -- bash theme/generate.sh
```

`shellcheck` is not packaged for Windows; the static Linux binary from the
[shellcheck releases](https://github.com/koalaman/shellcheck/releases) works
inside WSL without root.

---

## 5. On-metal checklist (Phase 1 sign-off, Zenbook)

Tracked separately because none of it blocks VM iteration.

- [ ] Fractional scaling looks right on the 16:10 HiDPI panel; text is sharp,
      not upscaled.
- [ ] Suspend and resume, with the cursor and outputs intact afterwards.
- [ ] Brightness keys and `brightnessctl`.
- [ ] Audio output and microphone.
- [ ] Webcam in Chrome.
- [ ] Screen sharing: Chrome to a meeting test page, portal picker appears,
      the shared screen actually updates.
- [ ] Battery module shows real values and warns at the right thresholds.
