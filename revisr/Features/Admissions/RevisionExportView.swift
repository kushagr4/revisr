import SwiftData
import SwiftUI
import UIKit

struct RevisionExportView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var preparing: RevisionExportKind?
    @State private var artifact: RevisionExportArtifact?
    @State private var errorMessage: String?
    @State private var copiedPrompt = false

    var body: some View {
        List {
            Section {
                Text("Create a local copy of your revision data that you can save or share with tools such as ChatGPT.")
                    .foregroundStyle(.secondary)
            }

            Section {
                exportButton(
                    kind: .snapshot,
                    title: "Revision Snapshot",
                    subtitle: "Recommended for ChatGPT. Current progress, complete attempt history, review, coverage, standby and upcoming work.",
                    systemImage: "doc.text"
                )
                exportButton(
                    kind: .full,
                    title: "Full Data Export",
                    subtitle: "A ZIP archive with structured JSON, CSV and Markdown files for detailed analysis or personal archival.",
                    systemImage: "archivebox"
                )
            } header: {
                Text("Export Options")
            }

            Section("Suggested ChatGPT Prompt") {
                Text(RevisionExportService.suggestedPrompt)
                    .font(.subheadline)
                    .textSelection(.enabled)
                Button(copiedPrompt ? "Copied" : "Copy Suggested Prompt", systemImage: copiedPrompt ? "checkmark" : "doc.on.doc") {
                    UIPasteboard.general.string = RevisionExportService.suggestedPrompt
                    copiedPrompt = true
                }
                .disabled(copiedPrompt)
            }

            Section {
                Label(
                    "This export may contain your revision history, notes and performance data. Nothing is uploaded automatically.",
                    systemImage: "hand.raised"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Label(
                    "Source-paper PDFs and full Question wording are never included.",
                    systemImage: "doc.badge.ellipsis"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Export Revision Data")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if preparing != nil {
                ProgressView("Preparing export…")
                    .padding(RevisrSpacing.large)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel("Preparing export")
            }
        }
        .disabled(preparing != nil)
        .sheet(item: $artifact) { artifact in
            RevisionShareSheet(url: artifact.url)
                .ignoresSafeArea()
        }
        .alert("Unable to Create Export", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
        .task {
            RevisionExportService.cleanupTemporaryExports()
        }
    }

    @ViewBuilder
    private func exportButton(
        kind: RevisionExportKind,
        title: String,
        subtitle: String,
        systemImage: String
    ) -> some View {
        Button {
            generate(kind)
        } label: {
            HStack(alignment: .top, spacing: RevisrSpacing.standard) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(RevisrColors.accentTeal)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: RevisrSpacing.small) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Creates a local file and opens the iOS Share Sheet")
    }

    private func generate(_ kind: RevisionExportKind) {
        preparing = kind
        Task { @MainActor in
            await Task.yield()
            do {
                switch kind {
                case .snapshot:
                    artifact = try RevisionExportService.createSnapshotFile(in: modelContext)
                case .full:
                    artifact = try RevisionExportService.createFullExportFile(in: modelContext)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            preparing = nil
        }
    }
}

private struct RevisionShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
