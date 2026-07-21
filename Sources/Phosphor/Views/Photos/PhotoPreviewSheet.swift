import SwiftUI
import AVKit

/// In-app photo/video preview sheet for live device photos.
struct PhotoPreviewSheet: View {
    let photo: LiveDeviceBrowser.LivePhoto
    @Binding var localPath: String?
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack(spacing: 12) {
                Image(systemName: photo.isVideo ? "video.fill" : "photo")
                    .foregroundStyle(.secondary)
                Text(photo.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if let path = localPath {
                    Button {
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    } label: {
                        Label("Open Externally", systemImage: "arrow.up.right.square")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.escape)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.brandAccent)
            }
            .padding(16)

            Divider()

            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 720, minHeight: 540)
        .onChange(of: localPath) { _, newPath in
            if photo.isVideo, let path = newPath {
                let newPlayer = AVPlayer(url: URL(fileURLWithPath: path))
                player = newPlayer
                newPlayer.play()
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if let path = localPath {
            if photo.isVideo {
                videoView(path: path)
            } else if let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(16)
            } else {
                unpreviewableView(path: path)
            }
        } else {
            loadingView
        }
    }

    @ViewBuilder
    private func videoView(path: String) -> some View {
        if let player = player {
            VideoPlayer(player: player)
        } else {
            // Player not ready yet — show loading briefly
            loadingView
                .onAppear {
                    let p = AVPlayer(url: URL(fileURLWithPath: path))
                    self.player = p
                    p.play()
                }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().scaleEffect(1.2)
            Text("Downloading from device…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func unpreviewableView(path: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Cannot preview this file")
                .font(.headline)
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            } label: {
                Label("Open in Default App", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
