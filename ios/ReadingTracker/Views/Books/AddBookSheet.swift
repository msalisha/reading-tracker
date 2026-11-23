import SwiftUI
import SwiftData

/// Add a book: scan its barcode (or type the ISBN) to fill in the details and cover, or type them.
struct AddBookSheet: View {
    var defaultStatus: BookStatus = .reading

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @Query private var books: [Book]

    @State private var isbn = ""
    @State private var title = ""
    @State private var author = ""
    @State private var pagesText = ""
    @State private var atText = ""
    @State private var status: BookStatus = .reading
    @State private var cover: Data?
    @State private var coverURL: URL?
    @State private var lookupMessage: String?
    @State private var looking = false
    @State private var scanning = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        scanning = true
                    } label: {
                        Label("Scan the barcode", systemImage: "barcode.viewfinder").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PillButton(kind: .highlight, big: true))
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .disabled(!ScannerView.isAvailable)
                    .accessibilityIdentifier("scanBarcode")
                } footer: {
                    if !ScannerView.isAvailable { Text("Scanning needs the camera. Type the ISBN or the details below.") }
                }

                Section("ISBN") {
                    HStack {
                        TextField("978…", text: $isbn).keyboardType(.numberPad)
                        Button(looking ? "Looking…" : "Look up") { Task { await lookUp() } }
                            .disabled(looking || isbn.isEmpty)
                    }
                    if let lookupMessage { Text(lookupMessage).font(.footnote).foregroundStyle(.secondary) }
                }

                Section("Book") {
                    HStack(alignment: .top, spacing: 12) {
                        if cover != nil || !title.isEmpty { CoverView(data: cover, title: title.isEmpty ? "?" : title, width: 54) }
                        VStack {
                            TextField("Book name", text: $title).font(.headline).accessibilityIdentifier("addTitle")
                            Divider()
                            TextField("Author", text: $author).accessibilityIdentifier("addAuthor")
                        }
                    }
                    LabeledContent("Number of pages") {
                        TextField("272", text: $pagesText).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("addPages")
                    }
                    Picker("Add to", selection: $status) {
                        Text("On the go").tag(BookStatus.reading)
                        Text("Want to read").tag(BookStatus.wantToRead)
                    }
                    if status == .reading {
                        LabeledContent("Already on page") {
                            TextField("0", text: $atText).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        }
                    }
                }

                if let error {
                    Text(error).foregroundStyle(theme.brandText).font(.subheadline.weight(.semibold))
                }
            }
            .navigationTitle("Add a book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: save).fontWeight(.bold).accessibilityIdentifier("addSave")
                }
            }
            .fullScreenCover(isPresented: $scanning) {
                BarcodeScanScreen { code in
                    scanning = false
                    isbn = code
                    Task { await lookUp() }
                }
            }
            .onAppear { status = defaultStatus }
        }
    }

    private func lookUp() async {
        guard let code = ISBN.normalize(isbn) else {
            lookupMessage = "That doesn't look like an ISBN. It's the 13-digit number under the barcode, starting 978 or 979."
            return
        }
        isbn = code
        if let have = books.first(where: { $0.isbn == code }) {
            lookupMessage = "You already have \(have.title)."
            return
        }
        looking = true
        lookupMessage = "Looking up the book…"
        defer { looking = false }
        guard let found = await BookLookup.find(isbn: code) else {
            lookupMessage = "Couldn't find that book. Fill in the details below."
            return
        }
        title = found.title
        if !found.author.isEmpty { author = found.author }
        if let p = found.pages { pagesText = "\(p)" }
        coverURL = found.coverURL
        lookupMessage = found.pages != nil ? "Found it. Editions differ, so check the last page of your copy." : "Found it. Add the number of pages from your copy."
        cover = await BookLookup.cover(isbn: code, fallback: found.coverURL)
    }

    private func save() {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { error = "Add the book name."; return }
        guard let pages = Int(trimming: pagesText), pages > 0 else { error = "Number of pages should be 1 or more."; return }
        let at = status == .reading ? (Int(trimming: atText) ?? 0) : 0
        guard at >= 0, at < pages else { error = "“Already on page” should be between 0 and \(pages - 1)."; return }
        let code = isbn.isEmpty ? nil : ISBN.normalize(isbn)
        if !isbn.isEmpty, code == nil { error = "That ISBN doesn't look right. Clear it or check the number."; return }
        let book = Book(title: String(name.prefix(200)), author: String(author.trimmingCharacters(in: .whitespaces).prefix(200)),
                        isbn: code, totalPages: pages, startPage: at, status: status, coverData: cover)
        ctx.insert(book)
        Library.save(ctx)
        Haptics.success()
        dismiss()
    }
}

/// The camera, full screen, with a cancel button.
struct BarcodeScanScreen: View {
    var onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .bottom) {
            ScannerView(mode: .barcode, onBarcode: onCode).ignoresSafeArea()
            VStack(spacing: 12) {
                Text("Point at the barcode on the back cover").font(.headline).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8).background(.black.opacity(0.6), in: Capsule())
                Button("Cancel") { dismiss() }.buttonStyle(PillButton(kind: .outline)).frame(width: 160)
                    .background(.white, in: Capsule())
            }
            .padding(.bottom, 40)
        }
    }
}
