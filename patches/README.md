<!-- SPDX-License-Identifier: Apache-2.0 -->
# Build patches

Patches applied to third-party sources during the iOS cross-build
(`ios-build/build-qemu-ios.sh`). They originate from the
[UTM project](https://github.com/utmapp/UTM) and are derivative works of their
respective upstreams — each stays under its upstream's license, not ShellPhone's.

`download()` in the build script applies `<name>.patch` automatically when the
filename matches the unpacked source directory, so the names below are load-bearing.

| Patch | Applies to | Upstream license |
|---|---|---|
| `gettext-0.22.5.patch` | GNU gettext 0.22.5 | LGPL-2.1 (runtime lib) |
| `libslirp-v4.9.1.patch` | libslirp v4.9.1 | BSD-3-Clause / MIT |
| `pixman-0.38.0.patch` | pixman 0.38.0 | MIT |
| `qemu-10.0.2-utm.patch` | QEMU (UTM fork) | GPL-2.0 |

## A note on `qemu-10.0.2-utm.patch`

This one is **not applied by the build script** — QEMU is fetched as the
pre-patched `v10.0.2-utm` release tarball from
<https://github.com/utmapp/qemu>, so the changes are already baked in. It is kept
here as provenance: it is the record of what UTM changed in QEMU (the
`tcg/aarch64-tcti` threaded-interpreter backend and the `--enable-shared-lib`
loadable-library build, which are the two things that make ShellPhone possible at
all), authored by osy. Deleting it would make the shipped GPL binary harder to
trace back to its modifications, which is the opposite of what `COMPLIANCE.md`
asks for.

## What used to be here

Before the licence audit this directory also carried twelve patches for
components ShellPhone deliberately does **not** build (spice, spice-gtk, gstreamer,
libusb, libgcrypt, libsoup, libtpms, json-glib, openssl, phodav, and a stale
`glib-2.69.0.patch` that could never match the 2.83.0 we build), a `data/`
directory of EDK2 and QEMU `pc-bios` firmware blobs that nothing installs
(QEMU is configured `--disable-install-blobs`), and a verbatim copy of UTM's
`sources` manifest. They were inherited wholesale when the build was derived from
UTM's and were never used. Redistributing derivative works of LGPL/GPL upstreams
for no reason creates obligations with no corresponding benefit, so they were
removed rather than documented.
