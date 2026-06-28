<!-- Last session: 2026-06-28 -->
# Phosphor - Handoff

## Current Objective
v1.0.8 release cycle. Apple-redesigned brand assets + 5 contributor PRs integrated + all open issues triaged/closed.

## What Shipped in 1.0.8
### Branding (commit d623494)
- AppIcon.svg rebuilt in Apple design language: macOS material squircle (Big Sur grid 824/1024, 185 corner), SF Pro Heavy "P" as a vector path (font-independent), top-light gradient, base shade, soft drop shadow, beveled rim. No neon/scanlines/circuit clutter.
- AppIcon.icns rebuilt all sizes 16-1024.
- banner.svg/png rebuilt (dark, indigo halo, embedded icon, SF Pro wordmark as paths). README uses banner.png (GitHub sanitizes SVG <image>).
- og-image.png (1200x630) added; docs/index.html got og:image, twitter card, theme-color, clean P favicon.
- README: star-history chart added.

### Merged PRs (all from AJV20, reviewed via adversarial multi-agent workflow; reviewer + verifier both agreed merge; each builds clean + regression green)
- #26 chore: PR scope guard + split regression runner (Scripts/regression/).
- #25 fix: reopen Phosphor windows reliably -> FIXES issue #27 (frozen on intro screen, Tahoe). NSApplicationDelegateAdaptor reopen guard for 0-window launches.
- #20 perf: startup defer + streaming exports (FileHandle, remove-before-write truncation) + lazy manifest sizes.
- #23 ux: message export flow (MessageExportOptions date-range/includeAttachments, backup picker, Export All, background export Task).
- #24 feat: Wi-Fi/network device discovery (usbmux list --usb/--network merge, USB-precedence dedupe), network selection preserved through scheduled/manual backups.

### Merge conflict resolution note
- MessageExporter.swift: #20 (streaming) vs #23 (options API) resolved to keep BOTH - exportHTML/exportMbox take `includeAttachments` AND stream via FileHandle; exportChat/exportMessages take `MessageExportOptions`. Build + 8 regression checks pass.

## Release Verification (filled by release-local.sh)
- Tag: v1.0.8
- DMG SHA256: <computed by release-local.sh>
- Notarization: <status>
- In-repo cask Homebrew/phosphor.rb bumped by release-local.sh.
- External tap momenbasel/homebrew-phosphor ALSO bumped to 1.0.8 with the SAME SHA (issue #21 root cause: tap SHA drift).

## Issues - all closed this cycle
- #27 frozen intro (Tahoe): fixed by #25, closed referencing v1.0.8.
- #22 macOS-on-Proxmox launch error: responded (VM/Gatekeeper guidance), closed.
- #21 Homebrew SHA-256 mismatch: fixed - v1.0.8 cask SHA matches the published DMG in both in-repo cask and external tap.
- #18 Android/non-iOS iPod support: out of scope (native macOS/iOS-only), closed.
- #2 Windows/Linux: out of scope (native SwiftUI/macOS), closed.

## Next Steps / Open Items
- attributedBody typedstream parsing still unimplemented (small fraction of iOS 16+ messages have empty text).
- Shell.swift hardening nits from #19 (SIGKILL fallback, stdout/stderr race) still pending.
- Stale local branches from this session's gh-pr-checkout pollution (pr20/pr23/pr24, perf/*, fix/*, feat/*, chore/*) can be pruned.
