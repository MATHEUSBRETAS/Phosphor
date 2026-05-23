# Phosphor - Handoff

## Current Objective
v1.0.6 shipped 2026-05-23. Bug-fix release covering GitHub issues #14 (version display) and #15 (open existing MobileSync backups). Notarized DMG + Homebrew cask bumped + tag pushed.

## Recently Modified Files
- `Resources/Info.plist` - bumped `CFBundleShortVersionString` to 1.0.6, `CFBundleVersion` to 6.
- `Sources/Phosphor/Utilities/Extensions.swift` - dropped stale 2.1/2 placeholders in `AppVersion` fallback.
- `Sources/Phosphor/Services/BackupManager.swift` - `discoverBackups` surfaces `contentsOfDirectory` failures via `lastError` with TCC instructions for MobileSync path; accepts a single UDID backup folder at root; added `looksLikeBackupFolder`.
- `Sources/Phosphor/ViewModels/BackupViewModel.swift` - propagates `lastError` as `loadError`; new `openExistingBackupFolder()` that opens an `NSOpenPanel` and points the backup directory at the picked dir (or its parent if the pick is a single UDID folder).
- `Sources/Phosphor/Views/Backup/BackupListView.swift` - new "Open Existing Backup Folder..." menu item under New Backup; orange warning banner when `loadError` is set with a Pick Folder action.
- `Sources/Phosphor/Views/Settings/SettingsView.swift` - "Use Apple MobileSync directory" button + inline TCC reminder.
- `Homebrew/phosphor.rb` - version 1.0.6, sha 0e5c6d4bfb551ff91584ec142c0b19541e8a34e82db0a3784d170bec4d824b6a.

Commits on main: `f15b743 fix: ...` then `7850ae3 homebrew: bump cask to v1.0.6`.

## Issues / PRs Closed This Cycle
- #14 closed - version display fixed.
- #15 closed - MobileSync open + TCC surfacing.
- #2 still open as cross-platform roadmap placeholder; status update comment added.

## Next Steps / Open Items
- No open PRs.
- Open issue: #2 (Windows/Linux port) - intentionally kept open as a placeholder; revisit when concrete feature requests accumulate.
- `Scripts/release-local.sh` does not currently bump `Info.plist` version automatically. Consider adding a `sed` step so future releases don't repeat #14's root cause; for now the maintainer must remember to bump `Info.plist` alongside the cask before running the script.

## Release Verification
- Tag: https://github.com/momenbasel/Phosphor/releases/tag/v1.0.6
- DMG SHA256: `0e5c6d4bfb551ff91584ec142c0b19541e8a34e82db0a3784d170bec4d824b6a`
- Notarization submission id: `25ddf1e7-b8e0-4d17-8e72-424895396f31` (Accepted, stapled, spctl-accepted).
