import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// iMessage/SMS conversation browser with export capabilities.
/// Reads from sms.db extracted from iOS backups.
struct MessageListView: View {

    @EnvironmentObject var backupVM: BackupViewModel
    @StateObject private var messageVM = MessageViewModel()
    @State private var showExportSheet = false
    @State private var exportFormat: MessageExportFormat = .html
    @State private var searchText = ""

    var body: some View {
        HSplitView {
            // Chat list (left pane)
            chatListPane
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 380)

            // Message detail (right pane)
            messageDetailPane
        }
        .onAppear(perform: loadIfNeeded)
    }

    // MARK: - Chat List

    private var chatListPane: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Messages")
                    .font(.headline)
                Spacer()
                if !messageVM.chats.isEmpty {
                    Text("\(messageVM.totalMessages) messages")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                TextField("Search conversations...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            Divider()

            if messageVM.isLoading {
                LoadingOverlay(message: "Loading messages...")
            } else if backupVM.selectedBackup == nil && backupVM.backups.isEmpty {
                EmptyStateView(
                    icon: "message",
                    title: "No Backup Available",
                    subtitle: "Create a backup first from the Backups section. Messages are read from local device backups."
                )
            } else if backupVM.selectedBackup == nil {
                EmptyStateView(
                    icon: "message",
                    title: "No Backup Selected",
                    subtitle: "Go to Backups, select a backup, then return here to browse messages.",
                    action: {
                        if let first = backupVM.backups.first {
                            backupVM.openBackupBrowser(first)
                            messageVM.loadChats(from: first.path)
                        }
                    },
                    actionLabel: backupVM.backups.isEmpty ? nil : "Use Latest Backup"
                )
            } else if messageVM.chats.isEmpty {
                EmptyStateView(
                    icon: "message",
                    title: "No Messages Found",
                    subtitle: "This backup doesn't contain messages, or it may be encrypted."
                )
            } else {
                List(filteredChats, selection: Binding<MessageChat?>(
                    get: { messageVM.selectedChat },
                    set: { if let c = $0 { messageVM.selectChat(c) } }
                )) { chat in
                    chatRow(chat)
                        .tag(chat)
                }
                .listStyle(.inset)
            }
        }
    }

    private var filteredChats: [MessageChat] {
        guard !searchText.isEmpty else { return messageVM.chats }
        return messageVM.chats.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.chatIdentifier.localizedCaseInsensitiveContains(searchText) ||
            $0.participants.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    private func chatRow(_ chat: MessageChat) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(chat.isGroupChat ? Color.purple.opacity(0.15) : Color.blue.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: chat.isGroupChat ? "person.3.fill" : "person.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(chat.isGroupChat ? .purple : .blue)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(chat.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                HStack {
                    Text("\(chat.messageCount) messages")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    if let date = chat.lastMessageDate {
                        Text(date.relativeString)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    // MARK: - Message Detail

    private var messageDetailPane: some View {
        VStack(spacing: 0) {
            if let chat = messageVM.selectedChat {
                // Chat header
                HStack {
                    Text(chat.title)
                        .font(.headline)
                    Spacer()

                    Menu("Export") {
                        ForEach(MessageExportFormat.allCases, id: \.self) { format in
                            Button(format.rawValue) {
                                exportSingleChat(format: format)
                            }
                        }
                        Divider()
                        Menu("Export All Conversations As...") {
                            ForEach(MessageExportFormat.allCases, id: \.self) { format in
                                Button(format.rawValue) {
                                    exportAllConversations(format: format)
                                }
                            }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 80)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider()

                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(messageVM.messages) { message in
                                MessageBubble(
                                    message: message,
                                    attachmentResolver: { messageVM.resolveAttachmentDiskPath(for: $0) }
                                )
                                .id(message.id)
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: messageVM.messages.count) { _, _ in
                        if let last = messageVM.messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            } else {
                EmptyStateView(
                    icon: "bubble.left.and.bubble.right",
                    title: "Select a Conversation",
                    subtitle: "Choose a conversation from the list to view messages."
                )
            }
        }
    }

    // MARK: - Helpers

    private func loadIfNeeded() {
        if let backup = backupVM.selectedBackup {
            messageVM.loadChats(from: backup.path)
        }
    }

    /// Drive a native `NSSavePanel` so the file panel respects the format's
    /// extension (HTML/JSON/MBOX). SwiftUI's `.fileExporter` hard-codes a
    /// single `UTType` per modifier and was rewriting `.html` to `.txt`
    /// (issue #17).
    private func exportSingleChat(format: MessageExportFormat) {
        guard let chat = messageVM.selectedChat else { return }
        let panel = NSSavePanel()
        panel.title = "Export Conversation"
        panel.nameFieldStringValue = "\(safeFileName(chat.title)).\(format.fileExtension)"
        if let type = format.contentType { panel.allowedContentTypes = [type] }
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            _ = messageVM.exportChat(format: format, to: url.path)
        }
    }

    private func exportAllConversations(format: MessageExportFormat) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose a folder to export all conversations"

        if panel.runModal() == .OK, let url = panel.url {
            let count = messageVM.exportAllChats(format: format, to: url.path)
            messageVM.alertMessage = "Exported \(count) conversations"
            messageVM.showAlert = true
        }
    }

    private func safeFileName(_ raw: String) -> String {
        let stripped = raw
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return String(stripped.prefix(80))
    }
}

private extension MessageExportFormat {
    var contentType: UTType? {
        switch self {
        case .csv: return .commaSeparatedText
        case .txt: return .plainText
        case .html: return .html
        case .json: return .json
        case .mbox: return UTType(filenameExtension: "mbox") ?? .data
        }
    }
}

/// Single message bubble, styled like iMessage. Renders inline attachments
/// (images, video thumbnails, file links), rich-link previews, and tapback
/// reactions floating over the bubble corner.
struct MessageBubble: View {
    let message: Message
    let attachmentResolver: (MessageAttachment) -> String?

    var body: some View {
        HStack(alignment: .top) {
            if message.isFromMe { Spacer(minLength: 60) }

            VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 2) {
                if !message.isFromMe && !message.senderLabel.isEmpty {
                    Text(message.senderLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                ZStack(alignment: message.isFromMe ? .topLeading : .topTrailing) {
                    bubbleContent
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(message.isFromMe ? Color.blue : Color(.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    if !message.reactions.isEmpty {
                        Text(reactionGlyph)
                            .font(.system(size: 14))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color(.windowBackgroundColor))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
                            .help(reactionTooltip)
                            .offset(x: message.isFromMe ? -8 : 8, y: -10)
                    }
                }

                Text(message.formattedDate)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            if !message.isFromMe { Spacer(minLength: 60) }
        }
    }

    @ViewBuilder
    private var bubbleContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let text = message.text, !text.isEmpty {
                Text(text)
                    .font(.system(size: 14))
                    .foregroundStyle(message.isFromMe ? .white : .primary)
                    .textSelection(.enabled)
            }

            ForEach(message.attachments) { attachment in
                AttachmentView(
                    attachment: attachment,
                    diskPath: attachmentResolver(attachment),
                    isFromMe: message.isFromMe
                )
            }

            if let link = message.linkURL, !link.isEmpty {
                Link(destination: URL(string: link) ?? URL(string: "https://example.com")!) {
                    Text(link)
                        .font(.system(size: 12))
                        .underline()
                        .foregroundStyle(message.isFromMe ? .white : .blue)
                }
            }

            if message.text?.isEmpty != false,
               message.attachments.isEmpty,
               message.linkURL == nil {
                Text(message.displayText)
                    .font(.system(size: 14))
                    .foregroundStyle(message.isFromMe ? .white : .secondary)
                    .italic()
            }
        }
    }

    private var reactionGlyph: String {
        message.reactions.map { $0.type.emoji }.joined(separator: " ")
    }

    private var reactionTooltip: String {
        message.reactions
            .map { "\($0.sender) \($0.type.label.lowercased())" }
            .joined(separator: ", ")
    }
}

/// Renders a single attachment inline. Images load from the on-disk backup
/// blob via `NSImage`. Videos and other files fall back to an icon + filename
/// row that opens the file in the user's default app on click.
private struct AttachmentView: View {
    let attachment: MessageAttachment
    let diskPath: String?
    let isFromMe: Bool

    var body: some View {
        if attachment.isImage, let path = diskPath, let image = NSImage(contentsOfFile: path) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 280, maxHeight: 280)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onTapGesture(count: 2) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                }
        } else {
            let icon: String = {
                if attachment.isVideo { return "play.rectangle.fill" }
                if attachment.isImage { return "photo" }
                return "doc"
            }()
            Button {
                if let path = diskPath {
                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                    Text(attachment.displayName)
                        .lineLimit(1)
                    if diskPath == nil {
                        Text("(missing)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isFromMe ? Color.white.opacity(0.25) : Color.secondary.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(isFromMe ? .white : .primary)
            }
            .buttonStyle(.plain)
            .disabled(diskPath == nil)
        }
    }
}
