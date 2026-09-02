import PDFKit
import SwiftUI

struct SourcePDFView: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    let page: Int?

    var body: some View {
        PDFKitRepresentable(url: url, workbookPage: page)
            .ignoresSafeArea(edges: .bottom)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
    }
}

struct PDFKitRepresentable: UIViewRepresentable {
    let url: URL
    let workbookPage: Int?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        if let document = PDFDocument(url: url) {
            view.document = document
            navigate(view, to: document, coordinator: context.coordinator)
        }
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        guard let document = uiView.document else { return }
        navigate(uiView, to: document, coordinator: context.coordinator)
    }

    private func navigate(_ view: PDFView, to document: PDFDocument, coordinator: Coordinator) {
        let index = SourceLibraryService.pdfPageIndex(
            for: workbookPage,
            pageCount: document.pageCount
        )
        let navigationKey = "\(url.path)#\(index)"
        guard coordinator.navigationKey != navigationKey,
              let targetPage = document.page(at: index) else { return }
        coordinator.navigationKey = navigationKey

        // PDFView completes its initial layout asynchronously. Navigating on the
        // next main-loop turn prevents auto-scaling from snapping back to page 1.
        DispatchQueue.main.async {
            view.go(to: targetPage)
        }
    }

    final class Coordinator {
        var navigationKey: String?
    }
}
