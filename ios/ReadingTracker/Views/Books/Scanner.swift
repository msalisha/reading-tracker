import SwiftUI
import VisionKit

/// Live camera scanner (VisionKit). Barcode mode returns the first book ISBN it sees;
/// text mode lets the reader tap lines of a page to capture them as a quote.
struct ScannerView: UIViewControllerRepresentable {
    enum Mode { case barcode, text }
    let mode: Mode
    var onBarcode: (String) -> Void = { _ in }
    var onText: (String) -> Void = { _ in }

    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let types: Set<DataScannerViewController.RecognizedDataType> = mode == .barcode
            ? [.barcode(symbologies: [.ean13, .ean8, .upce])]
            : [.text()]
        let vc = DataScannerViewController(recognizedDataTypes: types,
                                           qualityLevel: mode == .barcode ? .balanced : .accurate,
                                           recognizesMultipleItems: mode == .text,
                                           isHighFrameRateTrackingEnabled: false,
                                           isPinchToZoomEnabled: true,
                                           isGuidanceEnabled: true,
                                           isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        if !vc.isScanning { try? vc.startScanning() }
    }

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) {
        vc.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let parent: ScannerView
        private var done = false
        init(_ parent: ScannerView) { self.parent = parent }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard parent.mode == .barcode, !done else { return }
            for item in items {
                if case .barcode(let code) = item, let raw = code.payloadStringValue, let isbn = ISBN.normalize(raw) {
                    done = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    parent.onBarcode(isbn)
                    return
                }
            }
        }

        func dataScanner(_ scanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            guard parent.mode == .text, case .text(let text) = item else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            parent.onText(text.transcript)
        }
    }
}

/// Full-screen quote capture: tap lines on the page to collect them, then Use text.
struct QuoteScanSheet: View {
    var onDone: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var captured: [String] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if ScannerView.isAvailable {
                    ScannerView(mode: .text, onText: { captured.append($0) })
                        .ignoresSafeArea(edges: .horizontal)
                } else {
                    ContentUnavailableView("Camera not available", systemImage: "camera",
                                           description: Text("Quote scanning needs a camera. Type the quote instead."))
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(captured.isEmpty ? "Tap the highlighted lines to capture them, in order." : captured.joined(separator: " "))
                        .font(captured.isEmpty ? .subheadline : .body)
                        .foregroundStyle(captured.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(6)
                    HStack {
                        Button("Clear") { captured.removeAll() }.buttonStyle(PillButton(kind: .outline)).disabled(captured.isEmpty)
                        Button("Use text") { onDone(captured.joined(separator: " ")); dismiss() }
                            .buttonStyle(PillButton(kind: .brand)).disabled(captured.isEmpty)
                    }
                }
                .padding(16)
                .background(.bar)
            }
            .navigationTitle("Scan a quote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
