import AppKit
import SwiftUI

struct ReadinessCenterView: View {
    @EnvironmentObject var deviceVM: DeviceViewModel
    @State private var exportMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if deviceVM.isCheckingReadiness {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Running readiness checks…")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if let report = deviceVM.readinessReport {
                    summaryCard(report)

                    SectionBlock(title: "Tool Readiness", systemImage: "wrench.and.screwdriver.fill") {
                        readinessRows(report.items.filter { $0.title.contains("Tool") })
                    }

                    SectionBlock(title: "Backup Folder", systemImage: "externaldrive.fill") {
                        readinessRows(report.items.filter { $0.title.contains("Backup Folder") })
                    }

                    SectionBlock(title: "Device Visibility", systemImage: "iphone.gen3") {
                        readinessRows(report.items.filter { $0.title.contains("Device Visibility") })
                    }

                    SectionBlock(title: "Wi-Fi Backup", systemImage: "wifi") {
                        readinessRows(report.items.filter { $0.title.contains("Wi-Fi Backup") })
                    }

                    SectionBlock(title: "Safe Operations", systemImage: "checkmark.shield.fill") {
                        readinessRows(report.items.filter { $0.title.contains("Safe Operations") })
                    }

                    SectionBlock(title: "Diagnostic Report", systemImage: "doc.text.magnifyingglass") {
                        readinessRows(report.items.filter { $0.title.contains("Diagnostic Report") })
                        Button {
                            exportDiagnosticReport(report)
                        } label: {
                            Label("Export Diagnostic Report", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    SectionBlock(title: "Next Steps", systemImage: "arrow.right.circle.fill") {
                        readinessRows(report.items.filter { $0.title.contains("Next Steps") })
                    }
                } else if !deviceVM.isCheckingReadiness {
                    ContentUnavailableView(
                        "Run a readiness check",
                        systemImage: "checklist.checked",
                        description: Text("Phosphor will check device tools, backup-folder access, Wi-Fi visibility, safe-operation guidance, and diagnostic export readiness.")
                    )
                    Button {
                        Task { await deviceVM.refreshReadiness() }
                    } label: {
                        Label("Run Readiness Check", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let exportMessage {
                    Text(exportMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .navigationTitle("Readiness Center")
        .task {
            if deviceVM.readinessReport == nil {
                await deviceVM.refreshReadiness()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Readiness Center")
                        .font(.largeTitle.weight(.bold))
                    Text("One place to verify setup, device visibility, backup safety, and bug-report diagnostics before you move data.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await deviceVM.refreshReadiness() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(deviceVM.isCheckingReadiness)
            }
        }
    }

    private func summaryCard(_ report: ReadinessReport) -> some View {
        HStack(spacing: 14) {
            Image(systemName: report.hasBlockers ? "xmark.octagon.fill" : (report.hasWarnings ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"))
                .font(.system(size: 28))
                .foregroundStyle(report.hasBlockers ? .red : (report.hasWarnings ? .orange : .green))
            VStack(alignment: .leading, spacing: 4) {
                Text(report.hasBlockers ? "Action needed" : (report.hasWarnings ? "Mostly ready" : "Ready"))
                    .font(.headline)
                Text(report.summary)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func readinessRows(_ items: [ReadinessItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(items) { item in
                ReadinessRow(item: item)
            }
        }
    }

    private func exportDiagnosticReport(_ report: ReadinessReport) {
        let panel = NSSavePanel()
        panel.title = "Export Phosphor Diagnostic Report"
        panel.nameFieldStringValue = "phosphor-diagnostic-report.md"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.plainText]
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try report.diagnosticMarkdown.write(to: url, atomically: true, encoding: .utf8)
            exportMessage = "Diagnostic Report exported to \(url.path)."
        } catch {
            exportMessage = "Could not export Diagnostic Report: \(error.localizedDescription)"
        }
    }
}

private struct SectionBlock<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.title3.weight(.semibold))
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.quaternary, lineWidth: 1)
        )
    }
}

private struct ReadinessRow: View {
    let item: ReadinessItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(.headline)
                    Text(item.status.rawValue)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(color.opacity(0.15))
                        .foregroundStyle(color)
                        .clipShape(Capsule())
                }
                Text(item.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let recoveryAction = item.recoveryAction {
                    Text(recoveryAction)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private var icon: String {
        switch item.status {
        case .ready: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .blocked: return "xmark.octagon.fill"
        case .info: return "info.circle.fill"
        }
    }

    private var color: Color {
        switch item.status {
        case .ready: return .green
        case .warning: return .orange
        case .blocked: return .red
        case .info: return .blue
        }
    }
}

#if canImport(PreviewsMacros)
#Preview {
    ReadinessCenterView()
        .environmentObject(DeviceViewModel())
}
#endif
