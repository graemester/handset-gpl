# Handset — corresponding source for GPL and LGPL components

Handset runs a real Linux virtual machine on an iPhone: QEMU compiled as a threaded
interpreter, a purpose-built Linux kernel, and curated guest root filesystems, presented
in a terminal. No jailbreak, no JIT, no writable-executable pages.

**This repository exists to satisfy the GPL.** It holds the complete corresponding source
and the scripts used to build the GPL-2.0 and LGPL-2.1 software distributed inside the
Handset application, together with the full licence texts and the third-party
inventory. It is a compliance artifact, and it is meant to be genuinely usable as one —
not a gesture toward one.

If you maintain something Handset depends on, the two sections most likely to matter to
you are [What Handset changed](#what-Handset-changed-and-what-it-did-not) and
[If something here is wrong](#if-something-here-is-wrong).

---

## Which version this corresponds to

| | |
|---|---|
| Handset app version | `0.1.0` |
| Tag | `v0.1.0-source` |

Every shipped version of the application has a matching `vX.Y.Z-source` tag here.

**Tags are permanent.** They are never deleted, moved, or force-pushed. If you are running
an older build, the source corresponding to *that* build remains available — the GPL's
guarantee is about the version you actually received, not the version we happen to ship
today.

## The written offer

This is the offer presented in the application, under **Settings → Licenses & Source
Code**, and in the App Store listing:

> Handset includes QEMU, the Linux kernel, GNU GLib, and other free software. The
> complete corresponding source code for the version you are running, together with the
> scripts used to build it, is available at
> **https://github.com/graemester/Handset-gpl** — see the source tag matching this
> app's version.

It is reproduced here so it can be checked against what is actually published rather than
taken on trust.

---

## What Handset changed, and what it did not

**Handset makes no modifications to QEMU.** It consumes UTM's `v10.0.2-utm` release
unmodified. The `patches/` directory in this repository contains four patches applied to
third-party sources during the cross-build, and **all four originate from the UTM
project**, not from Handset — see `patches/README.md`, which records their provenance
individually.

This matters for anyone auditing the licence position: the delta Handset contributes
over its upstreams is the *build configuration* and the *packaging*, not changes to the
software itself. What is genuinely Handset's own work in this repository is the build
scripts, the kernel configuration, and the guest image recipes.

### Credit where it is load-bearing

Handset does not exist without two pieces of work by **osy** and the
[UTM project](https://github.com/utmapp/UTM):

- **`tcg/aarch64-tcti`** — a threaded-interpreter TCG backend. iOS forbids
  writable-executable memory, so a JIT is impossible; without an interpreter backend there
  is no emulation on the platform at all.
- **`--enable-shared-lib`** — building QEMU as a loadable library. iOS forbids `fork` and
  `exec`, so QEMU cannot be a subprocess; it has to be loadable into the host process.

Those two changes are the difference between this being possible and impossible. They are
upstream in [utmapp/qemu](https://github.com/utmapp/qemu), under GPL-2.0, and this project
is a consumer of them, not a co-author.

Likewise: **QEMU** and its contributors, the **Linux kernel**, the **GLib** stack, and the
**Alpine, Debian, Arch, Fedora and Void** projects whose systems are what actually run
inside. The proportion of this product that other people wrote is not close.

---

## What is in this repository

| Path | Contents |
|---|---|
| `THIRD_PARTY.md` | Every third-party component: exact version, licence, how it is linked, and where its upstream source lives. **Start here** — it is the authoritative inventory. |
| `COMPLIANCE.md` | How this distribution is kept licence-compliant, release by release, including the reconciliation of GPL terms with App Store distribution. |
| `APP_STORE_EXCEPTION.md` | An additional permission granted over Handset's *own* first-party code, so that Apple's terms impose no barrier on the aggregate. |
| `licenses/` | Full licence texts: GPL-2.0, LGPL-2.1, MIT, BSD-3-Clause, Apache-2.0. |
| `build/build-qemu-ios.sh` | The script controlling QEMU's compilation for iOS, as required by GPLv2 §3. |
| `patches/` | The four patches applied to third-party sources, with per-patch provenance. |
| `kernel/config` | The exact kernel configuration the shipped `Image` was built from. |
| `kernel/Image.sha256` | Checksum of the kernel binary in the shipped app, so a rebuild can be verified against it. |
| `rootfs-build/` | Build recipes for the guest images Handset distributes. |
| `vendor/` | Upstream source tarballs at the pinned versions, with `SHA256SUMS`. |
| `MANIFEST.sha256` | Checksums of everything in this bundle. |

### Why the tarballs are vendored

`vendor/` duplicates source that is already available upstream, which is redundant until
the day it isn't. A source offer that resolves only by way of a third party's continued
hosting is one rename away from being unsatisfiable, and the breakage would be silent. The
bytes are cheap; the obligation is not conditional on someone else's infrastructure.

---

## Building

### QEMU

`build/build-qemu-ios.sh` expects the QEMU source tree unpacked **alongside** it as
`qemu-10.0.2-utm/`. It does not fetch QEMU itself — worth knowing before you run it,
because the failure is otherwise confusing. Either unpack
`vendor/qemu-10.0.2-utm.tar.gz`, or obtain it from
<https://github.com/utmapp/qemu> at tag `v10.0.2-utm`.

The script builds its dependency stack first, then QEMU, and takes roughly 15–30 minutes
on an Apple-silicon Mac. It requires the iOS SDK. Note that it explicitly disables a
number of optional QEMU features; several of those `--disable-*` flags exist because a
Homebrew library on the build host would otherwise be auto-detected and break the
cross-compile.

### The kernel

Linux 6.19.8 for arm64, configured with `kernel/config`. Use the script — it
is the same one used to build the shipped kernel:

```sh
/bin/sh build/build-kernel.sh
```

It runs the build in an `alpine:3.21` container, downloads
<https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.19.8.tar.xz> fresh, applies `kernel/config` via
`make olddefconfig`, builds `Image`, then verifies the arm64 magic, the size, the options
Handset requires to boot, and prints the sha256 — which you can compare against
`kernel/Image.sha256` to confirm you have reproduced the shipped binary exactly.

Equivalent by hand, if you would rather not use Docker:

```sh
tar xf linux-6.19.8.tar.xz && cd linux-6.19.8
cp ../kernel/config .config
make olddefconfig
make -j"$(nproc)" Image
sha256sum arch/arm64/boot/Image    # compare with kernel/Image.sha256
```

**Build it on Linux**, not macOS: the kernel builds host tools that need Linux headers,
and a case-insensitive filesystem collides `Documentation/Kbuild` with
`documentation/kbuild`, which breaks `make mrproper`. If you are on an Apple-silicon Mac,
the container route above is native — no cross-compilation is involved.

### The guest images

`rootfs-build/` holds a script per guest system. Each fetches its distribution's own
official base — Alpine's minirootfs, Debian via `debootstrap`, Arch Linux ARM's tarball,
Fedora's cloud base, Void's ROOTFS tarball — and configures init, the serial console,
networking and hostname, then converts to qcow2.

**No packages are modified.** The images contain unmodified upstream binaries from each
distribution's own repositories at the versions current when the image was built, and
their corresponding source is available from those distributions. What these scripts
contribute is configuration, and stripping documentation, locales and firmware that a
virtual machine with no physical hardware cannot use.

---

## Why the application's own source is not here

Worth addressing directly rather than leaving you to wonder.

Handset's Swift and Objective-C application layer is not published. The reasoning:
QEMU is used **unmodified** and loaded at **runtime** as a separate dynamic framework via
`dlopen`, so the application aggregates and loads QEMU rather than being built from it.
The first-party code is licensed Apache-2.0 — GPL-compatible — and
`APP_STORE_EXCEPTION.md` grants an additional permission over it that removes any
App Store-imposed restriction on that portion of the aggregate.

**We know that boundary is not universally agreed.** Reasonable people, including the FSF,
read in-process dynamic linking more strictly than this. The position above is a
considered one; it is not a settled one, and this README is not the place to pretend
otherwise.

So: if you hold copyright in QEMU or in anything else listed in `THIRD_PARTY.md` and you
read the boundary differently, **we would genuinely rather hear from you than not.** Open
an issue, or use the contact in `SECURITY.md` if you would prefer not to raise it in
public. That is not a formality — it is much cheaper for everyone to have the conversation
than for the first notice to arrive as a complaint.

---

## If something here is wrong

If you maintain something Handset uses and you find an attribution missing, a licence
misstated, a source link broken, a version recorded inaccurately, or your project's name
used in a way you dislike — **open an issue and it goes to the front of the queue**, ahead
of features and ahead of releases.

That ordering is a commitment, not a courtesy. A compliance repository that is slow to fix
compliance defects has failed at its only job.

Security reports: see `SECURITY.md`. Private vulnerability reporting is enabled on this
repository.

---

## Licence summary

| Component | Licence |
|---|---|
| QEMU (UTM fork, unmodified) | GPL-2.0 |
| Linux kernel | GPL-2.0 |
| GLib, libiconv, gettext runtime | LGPL-2.1 |
| pixman, libslirp, libffi, zstd, libucontext | MIT / BSD-3-Clause |
| Guest userlands | Mixed; each distribution's own terms |
| Handset's first-party code | Apache-2.0, plus the additional permission in `APP_STORE_EXCEPTION.md` |

`THIRD_PARTY.md` is authoritative and more precise than this table. Where they disagree,
`THIRD_PARTY.md` is correct and this table needs fixing — please say so.
