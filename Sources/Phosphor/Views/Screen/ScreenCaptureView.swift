import SwiftUI

/// Live screen capture from connected device via pymobiledevice3 developer screenshot.
struct ScreenCaptureView: View {

    @EnvironmentObject var deviceVM: DeviceViewModel
    @StateObject private var capture = ScreenCaptureService()
    @State private var rotationDegrees: Double = 0
    @State private var isMirrored = false

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if deviceVM.selectedDevice == nil {
                EmptyStateView(
                    icon: "camera.viewfinder",
                    title: "No Device Connected",
                    subtitle: "Connect a device to capture its screen."
                )
            } else if capture.needsTunnel {
                tunnelRequiredView
            } else if let error = capture.error {
                errorView(error)
            } else if let frame = capture.currentFrame {
                screenView(frame)
            } else if capture.isCapturing {
                LoadingOverlay(message: "Waiting for first frame...")
            } else {
                idleView
            }
        }
        .onDisappear {
            capture.stopCapture()
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 14) {
            GradientIconTile(systemName: "camera.viewfinder", color: .purple, size: 40, iconSize: 19)

            Text("Screen Capture")
                .font(.title2.weight(.semibold))

            if capture.isCapturing {
                StatusChip(text: "Live", color: .red, dot: true)
            }

            Spacer()

            if capture.isCapturing {
                Text("\(capture.frameCount) frames")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }

    // MARK: - Screen Display

    private func screenView(_ frame: NSImage) -> some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                Image(nsImage: frame)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .rotationEffect(.degrees(rotationDegrees))
                    .scaleEffect(x: isMirrored ? -1 : 1, y: 1)
                    .frame(maxWidth: geo.size.width, maxHeight: geo.size.height)
                    .frame(width: geo.size.width, height: geo.size.height)
            }

            Divider()

            HStack(spacing: 16) {
                Button {
                    capture.stopCapture()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)

                Divider().frame(height: 20)

                Button { withAnimation { rotationDegrees -= 90 } } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .help("Rotate CCW")

                Button { withAnimation { rotationDegrees += 90 } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Rotate CW")

                Button { withAnimation { isMirrored.toggle() } } label: {
                    Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                }
                .help("Mirror")

                Divider().frame(height: 20)

                Button { saveScreenshot() } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
            }
            .padding(12)
            .background(.bar)
        }
    }

    // MARK: - Tunnel Required (iOS 17+)

    private var tunnelRequiredView: some View {
        VStack(spacing: 16) {
            Image(systemName: "network.badge.shield.half.filled")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Tunnel Service Required")
                .font(.title3.weight(.semibold))

            Text("iOS 17+ requires a tunnel service for developer tools like\nscreen capture and location spoofing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            VStack(alignment: .leading, spacing: 8) {
                Text("Option 1: Click below (requires admin password)")
                    .font(.system(size: 12, weight: .medium))
                Button {
                    ScreenCaptureService.startTunnelService()
                    // Wait a bit for tunnel to start, then retry
                    Task {
                        try? await Task.sleep(for: .seconds(3))
                        capture.needsTunnel = false
                        capture.error = nil
                        if let udid = deviceVM.selectedDevice?.id {
                            capture.startCapture(udid: udid)
                        }
                    }
                } label: {
                    Label("Start Tunnel Service", systemImage: "play.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandAccent)

                Divider().padding(.vertical, 4)

                Text("Option 2: Run manually in Terminal")
                    .font(.system(size: 12, weight: .medium))
                let manualCmd = PyMobileDevice.tunneldCommand()
                HStack {
                    Text(manualCmd)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(2)
                    Button {
                        manualCmd.copyToClipboard()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                }
                .padding(8)
                .background(Color(.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .frame(maxWidth: 460, alignment: .leading)
            .elevatedCard()

            Button {
                capture.needsTunnel = false
                capture.error = nil
                if let udid = deviceVM.selectedDevice?.id {
                    capture.startCapture(udid: udid)
                }
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Idle

    private var idleView: some View {
        EmptyStateView(
            icon: "camera.viewfinder",
            title: "Screen Capture",
            subtitle: "Capture your device screen in real-time.\nRequires Developer Mode and tunnel service on iOS 17+.",
            action: {
                guard let udid = deviceVM.selectedDevice?.id else { return }
                capture.startCapture(udid: udid)
            },
            actionLabel: "Start Capture"
        )
    }

    // MARK: - Error

    private func errorView(_ error: String) -> some View {
        EmptyStateView(
            icon: "exclamationmark.triangle.fill",
            title: "Capture Failed",
            subtitle: error,
            action: {
                capture.error = nil
                guard let udid = deviceVM.selectedDevice?.id else { return }
                capture.startCapture(udid: udid)
            },
            actionLabel: "Try Again",
            color: .orange
        )
    }

    private func saveScreenshot() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "phosphor-capture-\(Int(Date().timeIntervalSince1970)).png"
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let _ = capture.saveCurrentFrame(to: url.path)
    }
}
