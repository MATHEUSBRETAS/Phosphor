<!-- Last session: 2026-06-08 -->
# Phosphor - Handoff

## Current Objective
v1.0.7 SHIPPED. Signed + notarized + stapled DMG published; Homebrew tap bumped. This release bundles two things:
1. PR #17 messages overhaul (already on main from prior cycle).
2. PR #19 "harden macOS dependency and backup flows" (external contributor AJV20) - reviewed, approved, squash-merged (`5156c3b`).

## What Shipped in #19 (reviewed + merged)
- `Sources/Phosphor/Utilities/Shell.swift` - `Shell.run` now actually enforces its `timeout` param (was accepted but ignored); reads stdout/stderr on separate dispatch queues to kill a potential pipe-buffer deadlock; PATH-injection logic extracted to `environmentWithToolPaths()` and applied to both sync `run` and `runAsync`; dropped `ifuse` from `checkDependencies()`; pymobiledevice3 detection now uses `PyMobileDevice.available()` instead of `python3 -c import`.
- `Sources/Phosphor/Services/NativeBackupService.swift` - REMOVED the silent auto-`pip3 install pymobiledevice3`; replaced with a guard + install guidance. Backup/restore now go through `PyMobileDevice.runAsync`.
- `Sources/Phosphor/Utilities/PyMobileDevice.swift` - `directBinaryWorks(at:)` validates console-script shims (`<path> version`) before caching, preventing stale-shim false positives.
- `Sources/Phosphor/Services/BackupManager.swift` - new `backupDirectoryWarning(for:)` (cloud-synced folder check), new corrupt/zero-length backup error hint, `defaultBackupDir` -> `systemMobileSyncDir` for the MobileSync-specific TCC message.
- `FileTransferManager`/`MusicTransferManager`/`LiveDeviceBrowser` - guard `Shell.which("ifuse")` before the legacy ifuse fallback; `LiveDeviceBrowser` caches DCIM folder list at mount and counts during scan (no double scan; `photoCount` is 0 until first scan).
- View files - `#Preview` blocks wrapped in `#if canImport(PreviewsMacros)` so `swift build` works under Command Line Tools; SettingsView surfaces the cloud-folder warning; pip3 -> pipx guidance throughout README/UI strings.
- `Resources/Info.plist` - `CFBundleShortVersionString` 1.0.7, `CFBundleVersion` 7 (`803da13`).

## Open Review Nits from #19 (non-blocking, future cleanup)
- `Shell.swift`: theoretical data race on captured `stdoutData/stderrData` if a pipe read hangs past the 2s grace window after a timeout kill (worst case = garbled stderr string, no crash).
- `Shell.swift`: timeout termination escalates SIGTERM -> SIGINT, no SIGKILL fallback for a truly wedged child.
- `LiveDeviceBrowser`: `photoCount` reads 0 until the first scan runs (intentional perf tradeoff).

## Release Verification
- Tag: `v1.0.7` -> https://github.com/momenbasel/Phosphor/releases/tag/v1.0.7
- DMG SHA256: `843697a2e8e3f0634e50e640b0bd608892f6ccbf9704863cd64d686cd435b968` (verified identical to the published release asset).
- Notarization: status **Accepted** (submission `033830ff-a1e5-48fb-8b3d-4d9f635aff28`), stapled, `spctl` accepted (Notarized Developer ID).
- In-repo cask `Homebrew/phosphor.rb` bumped + pushed (`b2c2b72`).
- External tap `momenbasel/homebrew-phosphor@2bc474c` bumped to 1.0.7; `brew info --cask phosphor` reports 1.0.7.
- AC_NOTARY keychain profile (re)provisioned from `~/.appstoreconnect/private_keys/` (key id `5G7R52L8RK`).

## Next Steps / Open Items
- Open issues #18 and #2 are platform-expansion feature requests (Windows/Linux) - not actionable this cycle.
- `attributedBody` typedstream parsing still unimplemented - a small fraction of iOS 16+ messages have empty `text` with content in the NSArchiver blob. Future: byte-scan the UTF-8 segment or `NSUnarchiver`.
- Consider folding the three #19 review nits into a small `Shell.swift` hardening pass next time that file is touched.
