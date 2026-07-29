# ShellPhone — Open-Source License Compliance

> **Purpose:** ShellPhone ships GPL-2.0 (QEMU, Linux) and LGPL-2.1 (GLib, etc.)
> software through the Apple App Store. This document is the operational playbook
> that keeps that distribution compliant. Follow it for every release.
>
> ⚠️ **This is engineering guidance, not legal advice.** Before the first public
> release, have this posture reviewed by a FOSS-literate lawyer or against the
> Software Freedom Conservancy's published guidance. Budget one consult.

---

## 1. The obligations, in plain terms

1. **GPL-2.0 (QEMU, Linux kernel, BusyBox):** anyone who receives the binary must
   be able to obtain the **complete corresponding source** — including the exact
   version and the **scripts used to control compilation and installation**
   (GPLv2 §3). We must not impose **additional restrictions** on their GPL rights
   (GPLv2 §6). See §3 for how App Store terms are reconciled.
2. **LGPL-2.1 (GLib, libiconv, gettext runtime):** same source offer, plus the
   user must be able to **relink** the application against a modified version of
   the library. We satisfy this by shipping these as **dynamically-loaded
   frameworks** (the user can replace the framework), and by publishing the build
   scripts.
3. **MIT / BSD (SwiftTerm, pixman, libffi, libslirp, zstd, musl):** retain
   copyright notices and license text. Satisfied by `THIRD_PARTY.md` + the bundled
   license texts.

---

## 2. The written offer (what users see)

Every distributed build must present, in-app and in the store listing:

> "ShellPhone includes QEMU, the Linux kernel, GNU GLib, and other free software.
> The complete corresponding source code for the version you are running,
> together with the scripts used to build it, is available at:
> **https://github.com/graemester/shellphone-gpl** — see the source tag matching
> this app's version (e.g. `v1.0.0-source`)."

Implemented by:
- In-app **Settings → Licenses & Source Code** screen (Workstream F.6), which
  renders `THIRD_PARTY.md`'s inventory, the bundled license texts, and this offer
  with a tappable source URL.
- The App Store description's "License / Source" section.

A network location that resolves to the tagged source satisfies GPLv2 §3 for
software distributed over a network.

> ### ⚠️ The offer does not resolve yet — this blocks shipping, not publishing
>
> `graemester/shellphone-gpl` **does not exist yet.** It is the intended target, recorded
> here so the offer text does not have to change again — but until that repository exists,
> is public, and carries a tag matching the shipped build, the offer above is
> unsatisfiable and the GPL obligation is **breached**. The offer is not a formality; it
> is the thing that makes distributing QEMU lawful. See
> [`docs/PUBLICATION-SCOPE.md`](docs/PUBLICATION-SCOPE.md) §2a for how to build it.
>
> **This does not mean the repository has to be published.** Whether to open-source
> ShellPhone is a separate commercial decision (see [`OPEN_SOURCE.md`](docs/OPEN_SOURCE.md)
> and [`GOING_PUBLIC.md`](docs/GOING_PUBLIC.md)); the GPL cares only about the
> GPL-licensed components and their corresponding source. Two independent routes
> satisfy §3:
>
> 1. **Publish the whole repository** and tag it, as `GOING_PUBLIC.md` describes. The
>    offer URL then resolves for free. Requires the publish decision.
> 2. **Publish a GPL source bundle only** — the QEMU fork source, the scripts that
>    control its compilation (`ios-build/build-qemu-ios.sh`), `kernel-output/config`
>    plus the kernel version and patches, `ShellPhone/patches/`, and the rootfs build
>    recipe — hosted anywhere publicly reachable and durable (a Release asset on a
>    separate public repo is sufficient). **The first-party Swift/ObjC application code
>    is not required to be in that bundle** unless it is a derivative work of QEMU,
>    which is the unsettled question flagged in §3. This route keeps the main
>    repository private and is the one to take if the publish decision is *not* made.
>
> **Route 2 is the chosen route.** See
> [`docs/PUBLICATION-SCOPE.md`](docs/PUBLICATION-SCOPE.md) for the exact allowlist of
> what goes into the bundle and what does not. In short: the inventory, the licence
> texts, the four third-party patches, `kernel-output/config`, and the build scripts —
> no application source, no documentation, no git history. ShellPhone does not modify
> QEMU (it uses UTM's pre-patched `v10.0.2-utm` tarball), so most of the obligation is
> discharged by pointing at already-public upstreams at pinned versions.
>
> Whichever route is chosen, **the offer URL in the user-facing text above must be
> updated to match before any build ships**, and step 4 of §4 below must actually be
> performed against the real URL rather than assumed — **logged out**, since opening it
> as the repository owner will succeed while it fails for every actual recipient.

---

## 3. Reconciling GPL with the App Store (the core issue)

The tension: Apple's App Store terms add usage conditions (device limits, no
redistribution) that the FSF considers "additional restrictions" incompatible with
GPLv2 §6. This is the well-known VLC/App-Store situation. How ShellPhone stays
clear:

1. **We are the packager and distributor.** We choose to distribute the aggregate
   through the App Store and we grant, over our *own* first-party code, an explicit
   additional permission covering Apple's terms (`launch/APP_STORE_EXCEPTION.md`). We do
   **not** (and cannot) relicense QEMU; we make our own glue impose no barrier.
2. **QEMU and the LGPL stack are dynamically loaded, not statically linked.**
   `QEMULauncher.m` `dlopen`s `qemu-aarch64-softmmu.framework` at runtime. This
   keeps the first-party (Apache-2.0) binary a separate work that merely
   *aggregates* and *loads* the GPL framework, strengthening the separation.
3. **Complete corresponding source is always offered** (§2), so the recipient's
   core GPL freedom — to study, modify, and rebuild — is preserved in practice.
4. **Precedent:** UTM SE (which also uses QEMU's threaded interpreter) ships on the
   App Store under the same reasoning. We mirror its posture.

> If a copyright holder of a bundled GPL component objects to App Store
> distribution, the fallback is alternative distribution (e.g. an EU alternative
> marketplace / notarized build). Keep the build channel-agnostic so this is
> possible. This is not expected but is the documented contingency.

### 3a. GPLv**3** in the guest images — a separate argument

Points 1–4 above are about GPL**v2** (QEMU, the Linux kernel, BusyBox), which is what
the VLC/App-Store precedent concerns. The guest root filesystems also carry **GPLv3**
software — `bash`, `nano`, `less` — and GPLv3 §6 (installation information) is a
stricter test than anything in GPLv2. It needs its own answer rather than being
folded into the paragraph above.

The answer is that §6 does not engage, because these are not part of the conveyed
application in the relevant sense:

1. **They are guest data, not program.** They are ARM64 executables inside a disk
   image, interpreted by an emulated CPU. The iOS binary never links, loads, or
   executes them; QEMU decodes their instructions. Whatever else is arguable, this is
   mere aggregation on any reading.
2. **Installation information is already fully present.** The freedom §6 protects is
   the ability to install and run a modified version. The guest filesystem is
   writable and unverified: a user can `apk add`, overwrite `/bin/bash`, rebuild the
   image with `rootfs-build/`, or boot an entirely different image. Nothing in the app
   checks, signs, or restricts guest binaries, and nothing ever should — see §5.
3. **The user is root.** Every guest boots to a root shell (or one keystroke from
   one). There is no privilege the app retains and the user lacks.
4. **The source offer covers them** via each distribution's published sources, per §2.

**Standing constraint this creates:** ShellPhone must never add guest-binary
verification, signed images that refuse to boot when modified, or any mechanism that
makes a user-modified guest unusable. That would convert this from an easy argument
into a hard one, and it is now an explicit non-goal (see `docs/OPEN_SOURCE.md`).

⚠️ This is the **first** of the two questions to put to the FOSS-literate lawyer this
document budgets for (the second being the `launch/APP_STORE_EXCEPTION.md` construction).

---

## 4. Release procedure (do this for EVERY App Store version)

For app version `X.Y.Z`:

1. **Freeze inputs.** Record exact versions/commits of every row in
   `THIRD_PARTY.md` (QEMU tag, kernel version, each library version, the SwiftTerm
   commit).
2. **Publish source.** Ensure the following are present and reachable at the tag:
   - QEMU fork source at the exact commit/tag (or a committed tarball/pointer).
   - `ios-build/build-qemu-ios.sh` — the scripts controlling QEMU compilation.
   - **`kernel-output/config`** + the kernel version + any kernel patches. This is
     the **single** tracked kernel config and it is the one the shipped kernel was
     actually built from — the Docker recipe in `CLAUDE.md` both reads and writes it
     (`cp /output/config .config` … `cp .config /output/config`), so it cannot drift
     from the binary it produced. The duplicate `configs/kernel-minimal.config`
     (clang, and despite its name roughly twice as fat) was removed on 28 Jul 2026
     precisely because publishing it would have made this offer *not* corresponding
     source; it remains in git history at `14d5338` if ever needed.
     **Verify provenance at release time** — the config and the shipped Image must
     come from the same build:
     ```sh
     shasum -a 256 ShellPhone/Resources/kernel kernel-output/Image   # must match
     ```
     If `kernel-output/Image` is absent (it is untracked build output), rebuild per
     `CLAUDE.md` and confirm the resulting Image matches `Resources/kernel` before
     tagging. As of 28 Jul 2026 both are `e5bacfac…635ca128b`.
   - `rootfs-build/` + `populate-rootfs.py` — the rootfs build recipe.
   - `ShellPhone/patches/` — all applied patches (see its `README.md` for which are
     applied by the build and which are provenance only).
3. **Tag it.** `git tag vX.Y.Z-source && git push origin vX.Y.Z-source`. This is
   automated by `.github/workflows/release.yml` (see Workstream B.6) so it can
   never be forgotten.
4. **Verify the offer resolves.** Open the tagged URL; confirm it contains the
   build scripts and points at the exact upstream sources.
5. **Run the linkage audit** (`THIRD_PARTY.md` §4) on the build Mac; confirm QEMU
   is `dlopen`-loaded and no static GPL link crept into the first-party binary.
6. **Update the in-app offer URL/version string** so it names this version's tag.

### Checklist (paste into the release PR)
- [ ] `THIRD_PARTY.md` versions match the actual build
- [ ] Source tag `vX.Y.Z-source` pushed and reachable
- [ ] Build scripts (`build-qemu-ios.sh`, kernel config, rootfs recipe) present at tag
- [ ] In-app Licenses screen shows correct version + working source URL
- [ ] Linkage audit passed (QEMU dlopen, LGPL frameworks replaceable, @rpath clean)
- [ ] `launch/APP_STORE_EXCEPTION.md` present and current
- [ ] Encryption exemption answered in App Store Connect; annual self-classification filed (§6)
- [ ] New Apache-2.0 SPM deps (`swift-nio-ssh` / `swift-nio` / `swift-crypto`) versions recorded in `THIRD_PARTY.md`
- [ ] Transitive licences re-checked (`cargo tree -e no-dev` for `tui/`, `Package.resolved` for SwiftPM) — a permissive direct dependency does not mean a permissive tree
- [ ] The published kernel config is the one the shipped kernel was built from
- [ ] `docs/UPSTREAM.md` updated — including whether this release met the one-contribution commitment

---

## 5. What NOT to do (compliance foot-guns)

- ❌ Do **not** statically link QEMU or any GPL-only library into the first-party
  binary. Keep it a `dlopen`-ed framework.
- ❌ Do **not** ship a binary version without a matching, reachable source tag.
- ❌ Do **not** strip copyright/license notices from any component.
- ❌ Do **not** paywall or DRM the GPL binary in a way that blocks the source
  freedom (selling the app is fine — restricting the source is not; see
  `NEXT_GEN_ROADMAP.md` §14 on compliant monetization).
- ❌ Do **not** modify a library and ship it without also publishing the modified
  source (this is why `patches/` must be in the source tag).

---

## 6. Export / encryption compliance

Separate from FOSS licensing, US export rules (EAR) apply because the app performs
encryption. ShellPhone encrypts in two standard, exemption-qualifying ways:

1. **System TLS** for HTTPS image downloads.
2. The **native SSH client** (`swift-nio-ssh`, backed by `swift-crypto` / Apple
   CryptoKit) — a secure remote-shell channel using only **standard algorithms**
   (AES-GCM, ChaCha20-Poly1305, Curve25519 key exchange, Ed25519 / ECDSA
   signatures). No proprietary or non-standard cryptography is implemented.

Posture:
- `Info.plist` sets `ITSAppUsesNonExemptEncryption = true` — the app does perform
  non-exempt encryption for a secure channel (it is more than incidental HTTPS).
  This is what triggers the App Store Connect encryption questionnaire.
- The app **qualifies for the standard exemption** (Category 5D992, License
  Exception ENC — encryption limited to authentication / a secure channel using
  standard algorithms). At submission, answer the encryption questions selecting
  the exemption; ASC records the classification.
- File the **annual self-classification report** to BIS/ENC (a once-a-year email;
  **no CCATS and no export license** are required for this exemption).
- SSH secrets (private keys, saved passwords) live in the **iOS Keychain**,
  device-only (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`), never synced.

The new SSH stack — **`swift-nio-ssh`, `swift-nio`, `swift-crypto`** — is
**Apache-2.0** (permissive, no copyleft), added via SwiftPM. No new GPL/LGPL
obligations, but record their exact resolved versions in `THIRD_PARTY.md` at each
release (§4 step 1), same as any other bundled dependency.

> ⚠️ Engineering guidance, not legal advice — fold this into the same pre-release
> legal review as the FOSS posture above.
