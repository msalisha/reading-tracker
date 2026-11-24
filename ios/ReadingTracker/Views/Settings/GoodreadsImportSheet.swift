import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Bring a Goodreads library across: explains how to get the export file, previews it, then imports the chosen shelves.
struct GoodreadsImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @State private var picking = false
    @State private var items: [GoodreadsImport.Item] = []
    @State private var shelves = Set(GoodreadsImport.Shelf.allCases)
    @State private var error: String?
    @State private var result: GoodreadsImport.Result?

    private func count(_ shelf: GoodreadsImport.Shelf) -> Int { items.filter { $0.shelf == shelf }.count }
    private var chosen: Int { items.filter { shelves.contains($0.shelf) }.count }

    var body: some View {
        NavigationStack {
            Form {
                if let result {
                    Section {
                        Label("Imported \(result.added) \(result.added == 1 ? "book" : "books")", systemImage: "checkmark.circle.fill")
                            .font(.headline).foregroundStyle(theme.brandText)
                            .accessibilityIdentifier("goodreadsResult")
                        if result.updated > 0 { Text("\(result.updated) imported before were updated.") }
                        if result.skipped > 0 { Text("\(result.skipped) were already in your library, so they were left alone.") }
                        if !result.toEnrich.isEmpty {
                            Text("Covers and any missing page counts are being fetched in the background. You can carry on using the app.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                } else if items.isEmpty {
                    Section("1. Get your Goodreads file") {
                        step(1, "Open Goodreads in a browser and sign in.")
                        step(2, "Go to My Books, then Tools → Import and export.")
                        step(3, "Tap Export Library and wait for the link to appear.")
                        step(4, "Download goodreads_library_export.csv to your iPhone (it lands in Files → Downloads).")
                        Link(destination: URL(string: "https://www.goodreads.com/review/import")!) {
                            Label("Open the Goodreads export page", systemImage: "safari")
                        }
                    }
                    Section("2. Choose it here") {
                        Button { error = nil; picking = true } label: {
                            Label("Choose the export file", systemImage: "doc.badge.plus").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PillButton(kind: .brand, big: true))
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .accessibilityIdentifier("goodreadsChoose")
                        if let error { Text(error).font(.subheadline.weight(.semibold)).foregroundStyle(theme.brandText) }
                    }
                } else {
                    Section {
                        ForEach(GoodreadsImport.Shelf.allCases) { shelf in
                            Toggle(isOn: Binding(get: { shelves.contains(shelf) },
                                                 set: { on in if on { shelves.insert(shelf) } else { shelves.remove(shelf) } })) {
                                HStack {
                                    Text(shelf.title)
                                    Spacer()
                                    Text("\(count(shelf))").foregroundStyle(.secondary).monospacedDigit()
                                }
                            }
                            .tint(theme.brand)
                            .disabled(count(shelf) == 0)
                        }
                    } header: {
                        Text("Found \(items.count) books")
                    } footer: {
                        Text("Read books become Finished on the date you read them, with your star ratings; reviews become notes. Books you already have aren't duplicated.")
                    }
                    Section {
                        Button { runImport() } label: {
                            Text("Import \(chosen) \(chosen == 1 ? "book" : "books")").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PillButton(kind: .highlight, big: true))
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .disabled(chosen == 0)
                        .accessibilityIdentifier("goodreadsRun")
                    }
                }
            }
            .navigationTitle("Import from Goodreads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(result == nil ? "Cancel" : "Done") { dismiss() } }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.commaSeparatedText, .plainText, .data]) { picked in
                read(picked)
            }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)").font(.caption.weight(.black)).foregroundStyle(theme.onBrand)
                .frame(width: 22, height: 22).background(theme.brand, in: Circle())
            Text(text)
        }
    }

    private func read(_ picked: Swift.Result<URL, Error>) {
        guard case .success(let url) = picked else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let found = try GoodreadsImport.parse(try Data(contentsOf: url))
            if found.isEmpty { error = "That file has no books in it." } else { items = found }
        } catch {
            self.error = GoodreadsImport.Problem.notGoodreads.errorDescription
        }
    }

    private func runImport() {
        let r = GoodreadsImport.apply(items, shelves: shelves, into: ctx)
        result = r
        Haptics.success()
        GoodreadsEnricher.shared.start(r.toEnrich, in: ctx.container)
    }
}
