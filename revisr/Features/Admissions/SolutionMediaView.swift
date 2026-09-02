import AVKit
import SwiftUI

/// Read-only local solution viewer. Playback never records or mutates a
/// question attempt; attempts remain explicit user actions elsewhere.
struct SolutionMediaView: View {
    let document: SolutionDocument
    let url: URL
    let page: Int?
    let startTimeSeconds: Double?

    init(resolution: QuestionSolutionResolution) {
        self.document = resolution.document
        self.url = resolution.url
        self.page = resolution.link.startPage
        self.startTimeSeconds = resolution.link.startTimeSeconds
    }

    init(document: SolutionDocument, url: URL) {
        self.document = document
        self.url = url
        self.page = nil
        self.startTimeSeconds = nil
    }

    @ViewBuilder
    var body: some View {
        switch document.mediaKind {
        case .pdf:
            SourcePDFView(url: url, page: page)
        case .video:
            LocalSolutionVideoView(
                url: url,
                startTimeSeconds: startTimeSeconds
            )
        }
    }
}

private struct LocalSolutionVideoView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer
    let startTimeSeconds: Double?

    init(url: URL, startTimeSeconds: Double?) {
        _player = State(initialValue: AVPlayer(url: url))
        self.startTimeSeconds = startTimeSeconds
    }

    var body: some View {
        VideoPlayer(player: player)
            .background(.black)
            .onAppear {
                if let startTimeSeconds {
                    player.seek(to: CMTime(seconds: startTimeSeconds, preferredTimescale: 600))
                }
            }
            .onDisappear { player.pause() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
    }
}
