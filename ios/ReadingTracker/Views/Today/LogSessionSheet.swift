import SwiftUI
import SwiftData

/// Log a session by hand: when, which book, which pages, and optionally how long.
struct LogSessionSheet: View {
    let books: [Book]
    @State var initialBookID: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Environment(Router.self) private var router
    @Environment(\.theme) private var theme

    @State private var startedAt = Date()
    @State private var fromText = ""
    @State private var toText = ""
    @State private var minutesText = ""
    @State private var error: String?

    private var book: Book? { books.first { $0.uid == initialBookID } ?? books.first }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Book", selection: $initialBookID) {
                        ForEach(books) { Text($0.title).tag($0.uid) }
                    }
                    DatePicker("Started reading", selection: $startedAt, in: ...Date())
                }
                Section {
                    LabeledContent("Started on page") {
                        TextField("0", text: $fromText).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("logFrom")
                    }
                    LabeledContent("Finished on page") {
                        TextField(book.map { "up to \($0.totalPages)" } ?? "", text: $toText)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("logTo")
                    }
                    LabeledContent("Minutes read") {
                        TextField("optional", text: $minutesText).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text(preview)
                }
                if let error {
                    Text(error).foregroundStyle(theme.brandText).font(.subheadline.weight(.semibold))
                }
            }
            .navigationTitle("Log a session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log", action: save).fontWeight(.bold).accessibilityIdentifier("logSave")
                }
            }
            .onAppear(perform: fill)
            .onChange(of: initialBookID) { _, _ in fill() }
        }
        .presentationDetents([.large])
    }

    private var preview: String {
        guard let b = book else { return "" }
        let from = Int(trimming: fromText), to = Int(trimming: toText)
        guard let f = from, let t = to, t > f else { return "\(b.totalPages - (from ?? 0)) pages left in this book." }
        return t >= b.totalPages ? "\(t - f) pages, and that's the end of the book." : "\(t - f) pages. You'll be \(Int((Double(t) / Double(b.totalPages) * 100).rounded()))% through."
    }

    private func fill() {
        if let b = book { fromText = "\(b.currentPage)" }
        error = nil
    }

    private func save() {
        guard let b = book else { return }
        let from = Int(trimming: fromText), to = Int(trimming: toText)
        if let problem = Library.problem(from: from, to: to, totalPages: b.totalPages) { error = problem; return }
        var minutes: Int?
        if !minutesText.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let m = Int(trimming: minutesText), m > 0 else { error = "Minutes should be a whole number, or leave it empty."; return }
            minutes = m
        }
        let finished = Library.logSession(ctx, book: b, startedAt: startedAt, from: from!, to: to!, minutes: minutes)
        dismiss()
        if finished { router.rateBookID = b.uid }
    }
}
