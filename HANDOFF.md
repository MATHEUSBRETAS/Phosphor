<!-- Last session: 2026-05-27 -->
# Phosphor - Handoff

## Current Objective
Messages overhaul on main, queued for v1.0.7. Closes GitHub issues #16 (Homebrew tap stuck on 1.0.4) and #17 (Messages bugs - attachments, contact names, group titles, reactions, hidden chats, HTML export extension, pluginPayload cleanup). Build green (`swift build`). No DMG cut yet.

## Recently Modified Files
- `Sources/Phosphor/Models/Message.swift` - added `Reaction` / `ReactionType`, `MessageAttachment.isPluginPayload/isImage/isVideo`, multi-attachment + reaction + senderName + linkURL on `Message`, and `participants`/`resolvedTitle` on `MessageChat`.
- `Sources/Phosphor/Utilities/ContactDirectory.swift` - new value type. Builds phone (last-10-digit) + email index from `ContactsExtractor.Contact`; exposes `name(forHandle:)`, `displayName(forHandle:)`, `groupTitle(participants:)`.
- `Sources/Phosphor/Services/MessageExporter.swift` - accepts a `ContactDirectory`; dynamic column gating against the live `chat` / `message` schema; resolves group chat titles from `chat_handle_join`; filters `is_archived`/`is_filtered`/`is_blackholed` chats (with `includeHidden:` opt-out for exports); separate attachment query keyed by message ROWID (no more join-row explosions); reaction add/remove resolver (`associated_message_type` 2000..3005, strips `p:<part>/` and `bp:<part>/` prefixes); rich-link URL extraction via `NSDataDetector` + bplist `$objects` scan; HTML escape helper covers `"`/`'`; HTML/MBOX/JSON/TXT/CSV exporters now render multi-attachments, reactions, and link previews; plugin-payload attachments are dropped from staging.
- `Sources/Phosphor/ViewModels/MessageViewModel.swift` - best-effort `ContactDirectory` from `ContactsExtractor` at load (silent fallback to `.empty`); new `ensureExtension(_:for:)` re-anchors save path to the chosen format; `resolveAttachmentDiskPath(for:)` forwards to the exporter for inline image rendering.
- `Sources/Phosphor/Views/Messages/MessageListView.swift` - bubble renders inline `NSImage` for image attachments, file/icon button for everything else (Finder open on click), inline `Link` for rich-link previews, floating reaction badge; export now uses `NSSavePanel` with the format's `UTType` (HTML lands as `.html`, JSON as `.json`, MBOX as `.mbox`); "Export All Conversations As..." submenu so the format isn't tied to the last single-chat export.
- `Homebrew/phosphor.rb` - corrected sha256 to the actual v1.0.6 DMG digest (`e918b834...`). The old in-tree value didn't match the release asset.

External: `momenbasel/homebrew-phosphor@d74f13e` bumps the tap to 1.0.6 (`brew info phosphor` now reports the correct version) - closes #16.

## Issues / PRs Closed This Cycle
- #16 closed - tap bumped + verified via `brew info phosphor`.
- #17 closed in code; remains opened on the user end until 1.0.7 ships. Mark closed on release.

## Next Steps / Open Items
- Cut v1.0.7: bump `Resources/Info.plist` (`CFBundleShortVersionString` -> 1.0.7, `CFBundleVersion` -> 7), update `Sources/Phosphor/Utilities/Extensions.swift` if its fallback string is hard-coded, run `bash Scripts/release-local.sh v1.0.7`, then update both `Homebrew/phosphor.rb` and the `homebrew-phosphor` tap with the new DMG sha.
- Known limitation documented in the #17 reply: chats genuinely deleted on the iPhone but still synced via iCloud Messages may persist - sms.db has no `is_deleted` flag. We now filter `is_archived` / `is_filtered` / `is_blackholed`, which catches the realistic "I don't want to see this" intent.
- `attributedBody` typedstream parsing remains unimplemented - a small fraction of iOS 16+ messages have empty `text` and the actual content sits in the NSArchiver blob. Future enhancement: pull the UTF-8 segment via byte scan or `NSUnarchiver` (deprecated but still works on macOS 14).

## Release Verification
- Last release: tag `v1.0.6` (https://github.com/momenbasel/Phosphor/releases/tag/v1.0.6). Real DMG SHA256: `e918b834100b903a4a50a0fc3ba6dc398557650ee446cf8cf377b76555b3d833` (HANDOFF previously recorded the wrong digest).
