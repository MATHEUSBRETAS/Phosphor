import Foundation
import SwiftUI

/// Drives message browsing and export UI.
@MainActor
final class MessageViewModel: ObservableObject {

    @Published var chats: [MessageChat] = []
    @Published var selectedChat: MessageChat?
    @Published var messages: [Message] = []
    @Published var isLoading = false
    @Published var searchQuery = ""
    @Published var searchResults: [Message] = []
    @Published var showAlert = false
    @Published var alertMessage = ""

    private var exporter: MessageExporter?
    private var backupPath: String?

    func loadChats(from backupPath: String) {
        self.backupPath = backupPath
        isLoading = true

        // Best-effort contact directory: if the AddressBook database isn't in
        // the backup (encrypted backup, partial restore, etc.) we still want
        // to surface the conversations - just without name resolution.
        let directory: ContactDirectory
        if let extractor = try? ContactsExtractor(backupPath: backupPath),
           let contacts = try? extractor.getContacts() {
            directory = ContactDirectory(contacts: contacts)
        } else {
            directory = .empty
        }

        do {
            let exporter = try MessageExporter(backupPath: backupPath, contacts: directory)
            self.exporter = exporter
            chats = try exporter.getChats()
        } catch {
            alertMessage = "Could not load messages: \(error.localizedDescription)"
            showAlert = true
            chats = []
        }

        isLoading = false
    }

    func selectChat(_ chat: MessageChat) {
        selectedChat = chat
        guard let exporter else { return }

        do {
            messages = try exporter.getMessages(chatId: chat.id)
        } catch {
            alertMessage = error.localizedDescription
            showAlert = true
            messages = []
        }
    }

    func search(_ query: String) {
        guard !query.isEmpty, let exporter else {
            searchResults = []
            return
        }
        do {
            searchResults = try exporter.searchMessages(query)
        } catch {
            searchResults = []
        }
    }

    func exportChat(format: MessageExportFormat, to path: String) -> Bool {
        guard let chatId = selectedChat?.id, let exporter else { return false }
        // The system file panel may have stripped or replaced our extension.
        // Re-anchor the output to the format the user actually picked so HTML
        // exports don't land as `.txt` (issue #17).
        let normalisedPath = ensureExtension(path, for: format)
        do {
            try exporter.exportChat(chatId: chatId, format: format, to: normalisedPath)
            return true
        } catch {
            alertMessage = "Export failed: \(error.localizedDescription)"
            showAlert = true
            return false
        }
    }

    func exportAllChats(format: MessageExportFormat, to directory: String) -> Int {
        guard let exporter else { return 0 }
        do {
            return try exporter.exportAllChats(format: format, to: directory)
        } catch {
            alertMessage = "Export failed: \(error.localizedDescription)"
            showAlert = true
            return 0
        }
    }

    /// Ensure a path ends with the export format's expected extension. Replaces
    /// a mismatched extension (e.g. `.txt` from SwiftUI's plain-text fallback)
    /// instead of appending so the file lands with one extension.
    private func ensureExtension(_ path: String, for format: MessageExportFormat) -> String {
        let target = format.fileExtension.lowercased()
        let ns = path as NSString
        let current = ns.pathExtension.lowercased()
        if current == target { return path }
        let stem = ns.deletingPathExtension
        return "\(stem).\(format.fileExtension)"
    }

    var totalMessages: Int {
        chats.reduce(0) { $0 + $1.messageCount }
    }

    /// Resolve an attachment to its on-disk location inside the backup, so
    /// the bubble view can render images inline or open files via Finder.
    func resolveAttachmentDiskPath(for attachment: MessageAttachment) -> String? {
        guard let filename = attachment.filename, let exporter else { return nil }
        return exporter.resolveAttachmentDiskPath(filename: filename)
    }
}
