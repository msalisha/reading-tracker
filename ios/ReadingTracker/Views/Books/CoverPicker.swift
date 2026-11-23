import SwiftUI
import PhotosUI
import UIKit

/// A book cover you can tap to change: the ISBN cover, a search online, a photo from your library,
/// a picture taken with the camera, or no cover.
struct CoverButton: View {
    @Binding var cover: Data?
    let title: String
    let author: String
    let isbn: String?
    var width: CGFloat = 96

    @Environment(\.theme) private var theme
    @State private var showOptions = false
    @State private var googleQuery: GoogleQuery?
    @State private var showPhotos = false
    @State private var showCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var working = false
    @State private var message: String?

    var body: some View {
        Button { showOptions = true } label: {
            ZStack(alignment: .bottomTrailing) {
                CoverView(data: cover, title: title.isEmpty ? "?" : title, width: width)
                    .opacity(working ? 0.5 : 1)
                    .overlay { if working { ProgressView() } }
                Image(systemName: cover == nil ? "plus.circle.fill" : "camera.circle.fill")
                    .font(.system(size: max(18, width * 0.24)))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(theme.onBrand, theme.brand)
                    .background(Circle().fill(Color(.systemBackground)).padding(2))
                    .offset(x: 6, y: 6)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(cover == nil ? "Add a cover" : "Change the cover")
        .accessibilityIdentifier("coverButton")
        .confirmationDialog("Book cover", isPresented: $showOptions, titleVisibility: .visible) {
            if let code = isbn.flatMap(ISBN.normalize) {
                Button("Use the cover for ISBN \(code)") { Task { await fromISBN(code) } }
            }
            Button("Search Google Images") { googleQuery = GoogleQuery(text: GoogleCovers.query(title: title, author: author)) }
            Button("Choose from Photos") { showPhotos = true }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take a photo") { showCamera = true }
            }
            if cover != nil {
                Button("Remove cover", role: .destructive) { cover = nil }
            }
        }
        .sheet(item: $googleQuery) { q in
            GoogleCoverSearchSheet(query: q.text) { cover = $0 }
        }
        .photosPicker(isPresented: $showPhotos, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                working = true
                defer { working = false; photoItem = nil }
                if let data = try? await item.loadTransferable(type: Data.self), let jpeg = Covers.thumbnail(data, maxSide: 600) {
                    cover = jpeg
                } else {
                    message = "That photo couldn't be opened. Try another one."
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                if let data = image.jpegData(compressionQuality: 0.9) { cover = Covers.thumbnail(data, maxSide: 600) }
            }
            .ignoresSafeArea()
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    /// The catalogues' cover for this ISBN; if they don't have one, search Google Images for the ISBN instead.
    private func fromISBN(_ code: String) async {
        working = true
        let outcome = await BookLookup.lookup(isbn: code)
        var fallback: URL?
        if case .found(let f) = outcome { fallback = f.coverURL }
        let data = outcome == .offline ? nil : await BookLookup.cover(isbn: code, fallback: fallback)
        working = false
        if let data {
            cover = data
        } else if outcome == .offline {
            message = "Couldn't reach the book catalogues. Check your internet connection and try again."
        } else {
            googleQuery = GoogleQuery(text: "\(code) book cover")
        }
    }
}

/// What to search Google Images for.
struct GoogleQuery: Identifiable {
    let text: String
    var id: String { text }
}

/// The camera, for photographing your own copy's cover.
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
