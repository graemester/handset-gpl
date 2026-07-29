<!-- SPDX-License-Identifier: Apache-2.0 -->
# Security policy

## Reporting a vulnerability

**Please do not open a public issue for a security problem.**

Report privately through GitHub's [private vulnerability
reporting](https://github.com/graemester/shellphone/security/advisories/new) — the
**Security → Report a vulnerability** button on this repository. That creates a
private advisory only you and the maintainer can see.

If that is unavailable to you, open a public issue saying only *"security report,
please make contact"* with no detail, and you'll be given a private channel.

**What to include:** what you found, how to reproduce it, the device and iOS version,
which guest image, and what an attacker gets out of it. A rough proof of concept is
worth more than a careful description.

**What to expect:** an acknowledgement within **7 days** and an initial assessment
within **14**. ShellPhone is maintained by one person alongside other work, so those
are honest numbers rather than enterprise ones. You will be told what the assessment
is, including if the answer is "this is working as intended" and why.

**Disclosure:** please give 90 days before public disclosure, or less if we agree a
fix has shipped. You will be credited in the advisory and the changelog unless you
ask not to be.

## Supported versions

Pre-1.0: only the current `main` and the most recent release are supported. This will
be replaced with a real support table at 1.0.

## Scope

**In scope**

- The iOS application — `ShellPhone/Sources/`, `ShellPhone/UTM-Imported/`, the
  `ShellPhoneCore` package.
- The **native SSH client**: key handling, host-key verification, the Keychain
  integration, the crypto in `ShellPhoneCore`. This is the highest-value area — it
  handles private keys and talks to real machines.
- **Image download and verification** — the SHA-256 pinning in `DistroCatalog.swift`
  and the download path. A way to get an unverified or substituted image onto a device
  is a real vulnerability.
- The **guest TUI** (`tui/`), particularly command construction in `exec.rs` and
  `launch.rs`.
- **VM isolation failures** — anything letting guest code affect the host app or reach
  iOS APIs beyond the emulated hardware.
- Build and release scripts, where a compromise would affect what ships.

**Out of scope**

- **Vulnerabilities in QEMU, the Linux kernel, or the guest distributions.** Report
  those to their own projects — [QEMU
  security](https://www.qemu.org/contribute/security-process/),
  [kernel.org](https://www.kernel.org/doc/html/latest/process/security-bugs.html), or
  the relevant distribution. Tell us too if ShellPhone's configuration makes an
  upstream issue materially worse, and we will carry a fix until it lands upstream.
- **"The guest runs as root."** By design. Every ShellPhone VM gives you root inside
  it — that is the product, and restricting it is a standing non-goal
  ([`docs/OPEN_SOURCE.md`](docs/OPEN_SOURCE.md) §2).
- **"The paid unlock can be bypassed."** Also by design, and documented in
  [`docs/SUSTAINABILITY.md`](docs/SUSTAINABILITY.md). The entitlement is a token on the
  guest kernel command line that any root shell can read. Build from source and you get
  everything anyway. This is not a vulnerability and does not need reporting.
- **The private keys in `SSHKeyFixtures.swift`.** Disposable `ssh-keygen` output used
  as test fixtures. They authenticate to nothing and are checked in deliberately; the
  file says so at the top. Scanners flag them and always will.
- Anything requiring a jailbroken device, or physical access to an unlocked phone.
- Denial of service against your own VM.

## What ShellPhone does with your data

Nothing leaves the device except things you initiate: image downloads over HTTPS,
whatever the guest VM does at your instruction, and SSH connections you configure. No
analytics, no telemetry, no accounts. See [`PRIVACY.md`](PRIVACY.md).

SSH private keys are stored in the iOS Keychain. Guest filesystems and VM snapshots
live unencrypted in the app's Documents directory, protected by the iOS sandbox and
device encryption — treat a guest filesystem as no more secure than the phone it is on.
