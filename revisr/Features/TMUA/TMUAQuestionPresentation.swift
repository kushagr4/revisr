import PDFKit
import SwiftUI

/// Bundled papers and solutions used by questions shown from their original paper. They are
/// present only in internal builds: public builds strip both folders.
@MainActor
enum TMUAPaperFiles {
    private static var croppedCache: [String: PDFDocument] = [:]

    static func paperURL(_ document: String, bundle: Bundle = .main) -> URL? {
        url(document, subdirectory: SourceLibraryService.bundleSubdirectory, bundle: bundle)
    }

    static func solutionURL(_ document: String, bundle: Bundle = .main) -> URL? {
        url(document, subdirectory: SolutionLibraryService.bundleSubdirectory, bundle: bundle)
    }

    private static func url(_ document: String, subdirectory: String, bundle: Bundle) -> URL? {
        let name = (document as NSString).deletingPathExtension
        let ext = (document as NSString).pathExtension
        return bundle.url(forResource: name, withExtension: ext, subdirectory: subdirectory)
            ?? bundle.url(forResource: name, withExtension: ext)
    }

    /// A document holding only the question: one cropped page per region, in reading order.
    static func croppedDocument(_ presentation: TMUAItemPresentation, bundle: Bundle = .main) -> PDFDocument? {
        let key = presentation.document + presentation.regions.map { "\($0.page):\($0.y)" }.joined(separator: ",")
        if let cached = croppedCache[key] { return cached }
        guard let url = paperURL(presentation.document, bundle: bundle), let source = PDFDocument(url: url) else { return nil }
        let result = PDFDocument()
        for region in presentation.regions {
            guard let page = source.page(at: region.page)?.copy() as? PDFPage else { return nil }
            let box = CGRect(x: region.x, y: region.y, width: region.width, height: region.height)
            page.setBounds(box, for: .mediaBox)
            page.setBounds(box, for: .cropBox)
            result.insert(page, at: result.pageCount)
        }
        croppedCache[key] = result
        return result
    }
}

/// The question text: Revisr's own typography, or the question as printed in its paper.
struct TMUAQuestionStem: View {
    let content: TMUAContentItem

    var body: some View {
        if content.presentation != nil {
            TMUAPaperQuestionView(item: content)
        } else {
            MathText(content.stem, role: .question)
                .accessibilityIdentifier("question.stem")
        }
    }
}

/// Answer options: full rows for Revisr questions, letters for a question shown from its paper
/// (the option text is printed in the paper above).
struct TMUAAnswerOptions: View {
    let content: TMUAContentItem
    let selectedID: String?
    var marking: (TMUAOption) -> TMUAOptionButton.Marking = { _ in .neutral }
    let onSelect: (TMUAOption) -> Void

    var body: some View {
        if content.presentation != nil {
            TMUALetterOptionGrid(options: content.options, selectedID: selectedID, marking: marking, onSelect: onSelect)
        } else {
            TMUAOptionList(options: content.options) { option in
                TMUAOptionButton(option: option, selected: selectedID == option.id, state: marking(option)) {
                    onSelect(option)
                }
            }
        }
    }
}

/// An official question shown as printed: the cropped region of the bundled paper, full width,
/// with a full-screen view for zooming.
struct TMUAPaperQuestionView: View {
    let item: TMUAContentItem
    @State private var zooming = false

    var body: some View {
        if let presentation = item.presentation, let document = TMUAPaperFiles.croppedDocument(presentation) {
            TMUAPDFView(document: document, interactive: false)
                .aspectRatio(presentation.aspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: RevisrMetrics.compactCornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: RevisrMetrics.compactCornerRadius)
                        .strokeBorder(Color.black.opacity(0.08))
                }
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.footnote.weight(.semibold))
                        .padding(8)
                        .background(.thinMaterial, in: Circle())
                        .padding(6)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
                .onTapGesture { zooming = true }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Question shown as printed in the official paper")
                .accessibilityHint("Opens the question full screen, where you can zoom.")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { zooming = true }
                .accessibilityIdentifier("question.stem")
                .fullScreenCover(isPresented: $zooming) {
                    TMUAPaperZoomView(document: document, title: item.title)
                }
        } else {
            ContentUnavailableView("Paper not in this build", systemImage: "doc.questionmark",
                description: Text("This official question is shown from your bundled paper, which this build does not include."))
        }
    }
}

private struct TMUAPaperZoomView: View {
    @Environment(\.dismiss) private var dismiss
    let document: PDFDocument
    let title: String

    var body: some View {
        NavigationStack {
            TMUAPDFView(document: document, interactive: true)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }
    }
}

struct TMUAPDFView: UIViewRepresentable {
    let document: PDFDocument
    let interactive: Bool

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = false
        view.pageBreakMargins = .zero
        view.pageShadowsEnabled = false
        view.backgroundColor = interactive ? .systemBackground : .white
        view.document = document
        view.autoScales = true
        view.isUserInteractionEnabled = interactive
        if interactive {
            view.minScaleFactor = view.scaleFactorForSizeToFit
            view.maxScaleFactor = max(4, view.scaleFactorForSizeToFit * 4)
        }
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }
        // Keep fitting the width as the view resizes (rotation, text size changes).
        DispatchQueue.main.async {
            view.autoScales = true
            if interactive { view.minScaleFactor = view.scaleFactorForSizeToFit }
        }
    }
}

/// Lettered answer buttons for a question whose options are printed in its paper.
struct TMUALetterOptionGrid: View {
    let options: [TMUAOption]
    let selectedID: String?
    var marking: (TMUAOption) -> TMUAOptionButton.Marking = { _ in .neutral }
    let onSelect: (TMUAOption) -> Void
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: RevisrSpacing.small) {
            Text("Your answer").font(.footnote.weight(.semibold)).foregroundStyle(RevisrColors.secondaryLabel)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: size, maximum: size * 1.6), spacing: 10)], spacing: 10) {
                ForEach(options, id: \.id) { option in
                    letter(option)
                }
            }
        }
    }

    private func letter(_ option: TMUAOption) -> some View {
        let selected = selectedID == option.id
        let state = marking(option)
        let accent: Color = switch state {
        case .neutral: RevisrColors.accentFill
        case .correct, .key: RevisrColors.success
        case .incorrect: RevisrColors.critical
        }
        let filled = selected || state == .key
        return Button {
            onSelect(option)
        } label: {
            Text(option.id)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: size)
                .foregroundStyle(filled ? Color.white : RevisrColors.primaryLabel)
                .background(filled ? accent : RevisrColors.secondaryBackground,
                            in: RoundedRectangle(cornerRadius: RevisrMetrics.standardCornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: RevisrMetrics.standardCornerRadius)
                        .strokeBorder(state == .neutral ? Color.clear : accent, lineWidth: 2)
                }
                .contentShape(RoundedRectangle(cornerRadius: RevisrMetrics.standardCornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Option \(option.id)")
        .accessibilityValue(Self.accessibilityState(state, selected: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("option.\(option.id)")
    }

    private static func accessibilityState(_ state: TMUAOptionButton.Marking, selected: Bool) -> String {
        switch state {
        case .neutral: selected ? "Selected" : ""
        case .correct: "Your answer, correct"
        case .incorrect: "Your answer, incorrect"
        case .key: "Correct answer"
        }
    }
}

/// The worked solution: Revisr's own text, or a link to the official worked solution at its page.
struct TMUAWorkedSolution: View {
    let item: TMUAContentItem
    @State private var showingOfficial = false

    var body: some View {
        if let reference = item.solutionReference {
            VStack(alignment: .leading, spacing: RevisrSpacing.small) {
                Label("Official worked solution", systemImage: "lightbulb").font(.subheadline.weight(.semibold))
                Text("\(reference.publisher) publishes a worked solution for this question.")
                    .font(.callout).foregroundStyle(RevisrColors.secondaryLabel)
                if let url = TMUAPaperFiles.solutionURL(reference.document) {
                    Button("Open worked solution") { showingOfficial = true }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("solution.official")
                        .sheet(isPresented: $showingOfficial) {
                            NavigationStack { SourcePDFView(url: url, page: reference.page) }
                        }
                } else {
                    Text("The worked-solutions document is not included in this build.")
                        .font(.footnote).foregroundStyle(RevisrColors.secondaryLabel)
                }
                if let provenance = item.keyProvenance {
                    Text("Answer key: \(provenance).").font(.caption).foregroundStyle(RevisrColors.secondaryLabel)
                }
            }
            .padding(RevisrSpacing.standard)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RevisrColors.tintedSurface, in: RoundedRectangle(cornerRadius: RevisrMetrics.standardCornerRadius))
        } else {
            TMUASolutionCard(solution: item.solution)
        }
    }
}
