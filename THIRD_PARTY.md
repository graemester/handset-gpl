# Third-Party Components & Licenses

ShellPhone is distributed together with third-party free software. This file is
the authoritative inventory of every third-party component shipped in (or with)
the application, its version, its license, how it is linked, and where its
complete corresponding source can be obtained.

- The first-party ShellPhone application code is licensed **Apache-2.0** (see
  `LICENSE`).
- The components below retain their own licenses.
- For GPL/LGPL components, the offer of complete corresponding source and the
  build recipes are described in `COMPLIANCE.md`.
- The App Store distribution permission is in `launch/APP_STORE_EXCEPTION.md`.
- Full license texts are bundled in the app at
  `ShellPhone/Resources/licenses/` and shown in-app under
  **Settings → Licenses & Source Code**.

> **Maintainer rule:** every time a shipped version changes, update the matching
> row here **and** publish a matching source tag (see `COMPLIANCE.md`). The App
> Store binary version and the published source must always correspond.

---

## 1. Components linked into / loaded by the application

These are the native libraries that make up the emulator. The emulator core
(QEMU) and the GLib stack are built as **dynamically-loaded frameworks**
(`dlopen`-ed at runtime by `QEMULauncher.m`), not statically linked into the
first-party binary. This linkage posture is deliberate — see `COMPLIANCE.md` §3.

| # | Component | Version | License | Linkage | Ships as | Source |
|---|-----------|---------|---------|---------|----------|--------|
| 1 | **QEMU** (UTM fork) | `v10.0.2-utm` | **GPL-2.0** (with GPLv2+/LGPL parts) | `dlopen` at runtime | `qemu-aarch64-softmmu.framework` | https://github.com/utmapp/qemu (tag `v10.0.2-utm`) |
| 2 | **GLib** | 2.83.0 | **LGPL-2.1-or-later** | dynamic framework | `glib-2.0.0`, `gobject-2.0.0`, `gio-2.0.0`, `gmodule-2.0.0`.framework | https://gitlab.gnome.org/GNOME/glib |
| 3 | **pixman** | 0.38.0 | **MIT** | dynamic framework | `pixman-1.0.framework` | https://gitlab.freedesktop.org/pixman/pixman |
| 4 | **libslirp** | v4.9.1 | **BSD-3-Clause / MIT** | dynamic framework | `slirp.0.framework` | https://gitlab.freedesktop.org/slirp/libslirp |
| 5 | **libffi** | 3.5.0 | **MIT** | dynamic framework | `ffi.8.framework` | https://github.com/libffi/libffi |
| 6 | **libiconv** | 1.16 | **LGPL-2.1** | dynamic framework | `iconv.2.framework` | https://ftp.gnu.org/pub/gnu/libiconv/ |
| 7 | **gettext (libintl)** | 0.22.5 | **LGPL-2.1** (runtime lib) | dynamic framework | `intl.8.framework` | https://ftp.gnu.org/pub/gnu/gettext/ |
| 8 | **zstd** | 1.5.2 | **BSD-3-Clause** (dual BSD/GPLv2; used under BSD) | dynamic framework | `zstd.1.framework` | https://github.com/facebook/zstd |
| 9 | **libucontext** | git `9b1d8f01a6e99166f9808c79966abe10786de8b6` | **MIT** | statically linked into QEMU framework | (inside `qemu-…softmmu.framework`) | https://github.com/utmapp/libucontext (fork of https://github.com/kaniini/libucontext) |
| 10 | **SwiftTerm** | commit `3c45fdcfcf4395c72d2a4ee23c0bce79017b5391` | **MIT** | static (Swift Package, vendored submodule) | in main binary | https://github.com/migueldeicaza/SwiftTerm |
| 31 | **UTM** (source subset, verbatim) | 36 files, imported 17 Mar 2026 | **Apache-2.0** | compiled into the main binary | in main binary | https://github.com/utmapp/UTM |
| 32 | **ios-autotools** (via UTM's `build_dependencies.sh`) | © 2014 Angelo Haller | **ISC** | host build script only | not shipped | https://github.com/szanni/ios-autotools |
| 33 | **zlib** | iOS system library (`libz.tbd`) | **zlib** | dynamic, OS-provided | not bundled (part of iOS) | https://zlib.net |

> The exact framework filenames above match the 11 embedded frameworks in
> `ShellPhone/project.yml` and `deploy.sh` (`NEEDED_FRAMEWORKS`). Any other
> frameworks produced by `ios-build/build-qemu-ios.sh` are build by-products and
> are **not** shipped.

> **Row 31 (UTM)** is ~700 KB of source in `ShellPhone/UTM-Imported/` — the QEMU
> launch mechanism, the configuration/argv model, and `Bootstrap.c`. It is what makes
> running QEMU inside an iOS process possible at all. Files are verbatim with their
> Apache-2.0 headers intact; the §4(b) statement of changes is
> [`ShellPhone/UTM-Imported/CHANGES.md`](ShellPhone/UTM-Imported/CHANGES.md).
>
> **Row 33 (zlib)** is consumed as the iOS system library via `libz.tbd`
> (`ShellPhone/Sources/Zstd/GzipShim.c`), not built or bundled. Listed for
> completeness; an OS-provided library carries no redistribution obligation.

### Build dependencies that are NOT shipped in the app
`pkg-config` is a host build tool only (runs on the build Mac). It is not part of
the distributed application and imposes no runtime obligation. The same applies to
row 32: `ShellPhone/scripts/build_dependencies.sh` is UTM's dependency build script,
derived from Angelo Haller's ISC-licensed `ios-autotools`; it runs on the build Mac
and ships nothing. Its ISC notice is retained in the file header.

### Swift Package Manager dependencies (statically linked into the main binary)

The native SSH client ("Flavor B" — see `docs/SSH_NATIVE.md`) is built on Apple's
SwiftNIO stack, resolved via SwiftPM (`ShellPhone/project.yml`) and statically
linked into the first-party binary. All are **Apache-2.0** (permissive: notice
retention only — no copyleft, no source-offer obligation).

| # | Component | Version (resolved) | License | Linkage | Source |
|---|-----------|--------------------|---------|---------|--------|
| 15 | **swift-nio-ssh** | 0.14.1 | **Apache-2.0** | static (SwiftPM) | https://github.com/apple/swift-nio-ssh |
| 16 | **swift-nio** | 2.101.3 | **Apache-2.0** | static (SwiftPM) | https://github.com/apple/swift-nio |
| 17 | **swift-crypto** | 2.6.0 | **Apache-2.0** | static (SwiftPM) | https://github.com/apple/swift-crypto |
| 18 | **swift-atomics** | 1.3.1 | **Apache-2.0** | static (SwiftPM, transitive) | https://github.com/apple/swift-atomics |
| 19 | **swift-collections** | 1.6.0 | **Apache-2.0** | static (SwiftPM, transitive) | https://github.com/apple/swift-collections |
| 20 | **swift-system** | 1.7.5 | **Apache-2.0** | static (SwiftPM, transitive) | https://github.com/apple/swift-system |
| 34 | **BoringSSL** (`CCryptoBoringSSL`, vendored inside swift-crypto) | as vendored by swift-crypto 2.6.0 | **OpenSSL / SSLeay / ISC / Apache-2.0** (multi-license) | static (SwiftPM, transitive) | https://github.com/apple/swift-crypto |

Versions are `from:`-pinned lower bounds in `project.yml`; the resolved versions
above come from `ShellPhone/Packages/ShellPhoneCore/Package.resolved` and must be
refreshed here at each release freeze (they float upward with SwiftPM resolution).

On iOS, `swift-crypto` routes most primitives through Apple **CryptoKit** — but it
still vendors and links **`CCryptoBoringSSL`** (row 34) for the primitives CryptoKit
does not cover. BoringSSL is a multi-license blob (OpenSSL License, SSLeay, ISC,
Apache-2.0); all are permissive notice-retention licenses with no copyleft or
source-offer obligation. **Verify against the actual link map before each release**
using the §4 procedure — if `CCryptoBoringSSL` symbols are absent from the shipped
binary, this row can be dropped.

---

## 2. Guest components (run *inside* the emulator, not linked into the app)

These are shipped as data images the virtual machine executes. They are
**aggregated** with the application, not linked into it (GPL "mere aggregation").
Their source offer still applies and is covered by `COMPLIANCE.md`.

| # | Component | Version | License | Ships as | Source |
|---|-----------|---------|---------|----------|--------|
| 11 | **Linux kernel** | 6.19.8 (slimmed, custom `.config`) | **GPL-2.0** | `Resources/kernel` (ARM64 `Image`) | https://cdn.kernel.org/pub/linux/kernel/v6.x/ + `kernel-output/config` |
| 12 | **Alpine Linux** minirootfs | 3.21.0 (aarch64) | mixed (MIT/BSD/GPL userland; BusyBox = GPL-2.0, musl = MIT) | `Resources/rootfs.qcow2.gz` | https://alpinelinux.org / https://dl-cdn.alpinelinux.org |
| 13 | **Debian** (curated image, paid) | 13 (Trixie) | mixed (DFSG) | downloadable image | https://www.debian.org |
| 14 | **Arch Linux ARM** (curated image, paid) | rolling | mixed | downloadable image | https://archlinuxarm.org |
| 29 | **Fedora** (curated image, paid) | 41 (aarch64) | mixed (MIT/BSD/GPL/LGPL userland) | downloadable image | https://fedoraproject.org |
| 30 | **Void Linux** (curated image, paid) | rolling (aarch64, glibc) | mixed (MIT/BSD/GPL userland; runit, xbps) | downloadable image | https://voidlinux.org (built by `rootfs-build/build-void.sh`) |
| 21 | **ShellPhone Code** (curated image, free download) | Alpine 3.x base + first-party TUI | mixed (Alpine as row 12) + Apache-2.0 (TUI) | downloadable image | this repo (`rootfs-build/build-shellphone-code.sh`) |

Downloadable curated images (Debian, Arch, Fedora, Void, ShellPhone Code) are fetched from official
mirrors — or, for ShellPhone Code, the project's own GitHub Release — over HTTPS and
verified by SHA-256 before use (see `docs/PRODUCTION_1.0_PLAN.md` Workstream G).

> **The bundled Alpine image (row 12) is Alpine 3.21.** The ShellPhone Code image
> (row 21) is built on **Alpine 3.22** (`rootfs-build/build-shellphone-code.sh`).
> Two different images, two different versions — not a discrepancy.

### GPLv3 in the guest userland

Rows 12 and 21 say "mixed … GPL". Being specific, because it is the one licence
question in this project with a genuinely contested answer: the guest images include
**GPLv3** software — `bash`, `nano`, and `less` among them — alongside the GPLv2
BusyBox and kernel.

GPLv3 §6's installation-information requirement is widely read (including by the FSF)
as incompatible with App Store distribution. ShellPhone's position is that this does
not arise here, because these programs are **not** part of the application:

- They are **guest data**, executed by an emulated CPU inside a virtual machine. They
  are never linked to, loaded by, or executed by the iOS application binary — QEMU
  interprets their instructions. This is mere aggregation in the plainest sense the
  term has.
- The user can replace them freely. The guest root filesystem is writable, `apk` works
  against Alpine's real repositories, and nothing in the app verifies or restricts
  guest binaries. The practical freedom GPLv3 §6 exists to protect — install and run
  your own modified version — is fully present.
- The source offer in `COMPLIANCE.md` §2 covers them regardless, via the distributions'
  own published sources.

See `COMPLIANCE.md` §3 for the full reconciliation, which covers GPLv2 and GPLv3
separately. **This is one of the two questions to put to the FOSS-literate lawyer
`COMPLIANCE.md` already budgets for.**

### Guest components compiled into the ShellPhone Code image

The **ShellPhone TUI** (first-party, `tui/`, **Apache-2.0**) is the boot menu of the
ShellPhone Code image. It is a single static `aarch64-unknown-linux-musl` binary
(~1.0 MB) that runs *inside* the guest — aggregated with the app like the rest of the
guest userland, not linked into the iOS binary. Its third-party Rust dependencies are
compiled into that binary; all are permissive (notice-retention only, no copyleft):

| # | Crate | Version (resolved) | License | Source |
|---|-------|--------------------|---------|--------|
| 22 | **ratatui** | 0.29.0 | **MIT** | https://github.com/ratatui/ratatui |
| 23 | **crossterm** | 0.28.1 | **MIT** | https://github.com/crossterm-rs/crossterm |
| 24 | **serde** (+ derive) | 1.0.x | **MIT OR Apache-2.0** | https://github.com/serde-rs/serde |
| 25 | **toml** | 0.8.x | **MIT OR Apache-2.0** | https://github.com/toml-rs/toml |
| 26 | **anyhow** | 1.0.x | **MIT OR Apache-2.0** | https://github.com/dtolnay/anyhow |
| 27 | **libc** | 0.2.x | **MIT OR Apache-2.0** | https://github.com/rust-lang/libc |

> Plus each crate's transitive dependencies. `cargo tree -e no-dev` from `tui/` is the
> authoritative resolved set (90 packages). `tempfile` is a dev-only dependency (tests)
> and is **not** shipped. Refresh the resolved versions here from `tui/Cargo.lock` at
> each release freeze.
>
> **Removed dependency — `dirs`.** The licence audit found that `dirs` 5.x
> reaches **`option-ext` 0.2.0, which is MPL-2.0** — file-level weak copyleft, and the
> only non-permissive crate that had been in the tree. It was used for exactly two
> things (`$HOME` and the XDG config dir), so the dependency was dropped in favour of
> a dozen lines of `std::env` in `tui/src/config.rs` rather than taking on an MPL
> source-availability obligation. This retires the obligation instead of documenting
> it, and drops the tree from 107 packages to 90. **Every crate now shipped in the TUI
> binary is permissive (MIT / Apache-2.0 / MIT-OR-Apache-2.0) — no copyleft.** If
> `dirs` (or anything reaching `option-ext`) is ever reintroduced, `MPL-2.0.txt` must
> be added to the bundled license texts and a row added here.

---

## 3. License texts

Full texts are bundled at `ShellPhone/Resources/licenses/`:

- `Apache-2.0.txt` — first-party code (incl. the ShellPhone TUI) + the imported UTM
  source (row 31; see `ShellPhone/UTM-Imported/CHANGES.md`) +
  the SwiftNIO SSH stack (`swift-nio-ssh`, `swift-nio`, `swift-crypto`,
  `swift-atomics`, `swift-collections`, `swift-system`) + the dual-licensed guest
  crates taken under Apache-2.0 (`serde`, `toml`, `anyhow`, `dirs`, `libc`)
- `GPL-2.0.txt` — QEMU, Linux kernel, BusyBox
- `LGPL-2.1.txt` — GLib, libiconv, gettext runtime
- `MIT.txt` — SwiftTerm, pixman, libffi, musl (guest), and the guest TUI crates
  `ratatui`, `crossterm`
- `BSD-3-Clause.txt` — libslirp, zstd

**Open item:** if the §4 linkage audit confirms `CCryptoBoringSSL` symbols in the
shipped binary (row 34), bundle `BoringSSL-LICENSE.txt` here too — its OpenSSL/SSLeay
terms are notice-retention and are not covered by any of the five texts above. zlib
(row 33) needs no bundled text: it is an iOS system library, not redistributed by us.

---

## 4. Linkage audit procedure (run on macOS before each release)

The runtime linkage of every shipped framework must be re-verified whenever the
QEMU build changes, to confirm the GPL/LGPL posture in §1 still holds. Run on the
build Mac (this cannot be run in the Linux CI/doc environment):

```bash
# From the built .app or ShellPhone/Frameworks
for fw in Frameworks/*.framework; do
  bin="$fw/$(basename "$fw" .framework)"
  echo "== $bin =="
  otool -L "$bin" 2>/dev/null | grep -E '@rpath|/usr/lib|/System' || true
  # Confirm install-names are @rpath (no /tmp sysroot leakage — see FINDINGS Issue)
  otool -D "$bin"
done
```

Expected result, to be recorded in the release checklist:
- QEMU + GLib frameworks reference each other and each other only via `@rpath`.
- The first-party `ShellPhone` binary links SwiftTerm (MIT, static) and the
  system frameworks; it loads QEMU via `dlopen` (no static GPL link).
- No absolute build-sysroot paths remain in any install-name.
