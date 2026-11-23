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
    @State private var showSearch = false
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
            Button("Search online") { showSearch = true }
            Button("Choose from Photos") { showPhotos = true }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take a photo") { showCamera = true }
            }
            if cover != nil {
                Button("Remove cover", role: .destructive) { cover = nil }
            }
        }
        .sheet(isPresented: $showSearch) {
            CoverSearchSheet(title: title, author: author, isbn: isbn ?? "") { cover = $0 }
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

    private func fromISBN(_ code: String) async {
        working = true
        defer { working = false }
        let found = await BookLookup.find(isbn: code)
        if let data = await BookLookup.cover(isbn: code, fallback: found?.coverURL) {
            cover = data
        } else {
            message = "There's no cover online for ISBN \(code). Try Search online, or take a photo of your copy."
        }
    }
}

/// Search Open Library and Google Books for covers by ISBN, title and author, then pick one.
struct CoverSearchSheet: View {
    @State var title: String
    @State var author: String
    @State var isbn: String
    var onPick: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var results: [URL] = []
    @State private var searching = false
    @State private var searched = false
    @State private var downloading: URL?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(spacing: 8) {
                        TextField("Book name", text: $title).textFieldStyle(.roundedBorder)
                        TextField("Author (optional)", text: $author).textFieldStyle(.roundedBorder)
                        TextField("ISBN (optional)", text: $isbn).textFieldStyle(.roundedBorder).keyboardType(.numberPad)
                        Button(searching ? "Searching…" : "Search") { Task { await search() } }
                            .buttonStyle(PillButton(kind: .brand))
                            .disabled(searching || (title.trimmingCharacters(in: .whitespaces).isEmpty && ISBN.normalize(isbn) == nil))
                            .accessibilityIdentifier("coverSearch")
                    }
                    if searching {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
                    } else if searched && results.isEmpty {
                        Text("No covers found. Try a shorter title, just the author's surname, or choose a photo instead.")
                            .foregroundStyle(.secondary).padding(.top, 20)
                    } else if !results.isEmpty {
                        Text("Tap the cover that matches your copy.").font(.subheadline).foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 14) {
                            ForEach(results, id: \.self) { url in
                                Button { Task { await pick(url) } } label: {
                                    AsyncImage(url: url) { phase in
                                        switch phase {
                                        case .success(let img): img.resizable().scaledToFill()
                                        case .failure: Color(.systemGray5).overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                                        default: Color(.systemGray6).overlay(ProgressView())
                                        }
                                    }
                                    .frame(width: 96, height: 144)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay {
                                        if downloading == url {
                                            RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.4)).overlay(ProgressView().tint(.white))
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(downloading != nil)
                            }
                        }
                    }
                    if failed {
                        Text("That cover couldn't be downloaded. Try another.").font(.footnote).foregroundStyle(theme.brandText)
                    }
                    Text("Covers come from Open Library and Google Books.").font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                }
                .padding(16)
            }
            .navigationTitle("Find a cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { if !searched { await search() } }
        }
    }

    private func search() async {
        searching = true
        failed = false
        results = await BookLookup.coverCandidates(title: title, author: author, isbn: ISBN.normalize(isbn))
        searching = false
        searched = true
    }

    private func pick(_ url: URL) async {
        downloading = url
        failed = false
        defer { downloading = nil }
        if let data = await BookLookup.download(url) {
            onPick(data)
            dismiss()
        } else {
            failed = true
        }
    }
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
