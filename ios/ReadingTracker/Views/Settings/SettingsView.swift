import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @AppStorage(AppTheme.storageKey, store: AppGroup.defaults) private var themeID = "neon"
    @AppStorage("appearance") private var appearance = "system"
    @Query private var books: [Book]
    @Query private var sessions: [ReadingSession]
    @State private var importing = false
    @State private var pending: Backup.Contents?
    @State private var message: String?
    @State private var exportFile: URL?
    @State private var csvFile: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section("Colour scheme") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
                        ForEach(AppTheme.all) { t in
                            Button { choose(t) } label: { ThemeSwatch(theme: t, selected: t.id == themeID) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("theme-\(t.id)")
                        }
                    }
                    .padding(.vertical, 6)
                    Picker("Appearance", selection: $appearance) {
                        Text("Match phone").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                }

                Section("Purchase") {
                    purchaseRow
                    Button("Restore purchases") { Task { await store.restore() } }
                        .disabled(store.busy)
                }

                Section {
                    Button("Import a backup") { importing = true }
                    if let exportFile {
                        ShareLink(item: exportFile) { Label("Save a backup", systemImage: "square.and.arrow.up") }
                    }
                    if let csvFile {
                        ShareLink(item: csvFile) { Label("Export as spreadsheet (CSV)", systemImage: "tablecells") }
                    }
                } header: {
                    Text("Your data")
                } footer: {
                    Text("Everything is stored on this iPhone: \(books.count) books and \(sessions.count) sessions. Import a backup from Pageturner or the web Reading Tracker (Log → Save a backup) to bring your history across.")
                }

                Section("About") {
                    Link("Privacy policy", destination: Links.privacy)
                    Link("Help and support", destination: Links.support)
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                }
            }
            .navigationTitle("Settings")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .plainText, .data]) { result in
                readBackup(result)
            }
            .alert("Import this backup?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
                Button("Import") {
                    if let p = pending { Backup.restore(p, into: ctx); message = "Imported \(p.books.count) books and \(p.sessions.count) sessions." }
                    pending = nil
                }
                Button("Cancel", role: .cancel) { pending = nil }
            } message: {
                if let p = pending {
                    Text("It has \(p.books.count) books, \(p.sessions.count) sessions (\(p.totalPages.formatted()) pages) and \(p.notes.count) notes. Books already here with the same id are replaced.")
                }
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            }
            .purchaseAlert()
            .task(id: books.count + sessions.count) { writeExports() }
        }
    }

    @ViewBuilder private var purchaseRow: some View {
        switch store.access {
        case .unlocked:
            Label("Unlocked forever. Thank you!", systemImage: "checkmark.seal.fill").foregroundStyle(theme.brandText)
        case .trial(let end):
            LabeledContent("Free trial", value: AccessRules.timeLeft(until: end, now: store.now))
            Button("Unlock forever" + (store.unlockPrice.isEmpty ? "" : " · \(store.unlockPrice)")) { router.showPaywall = true }
        case .expired, .noTrial:
            LabeledContent("Free trial", value: store.access == .expired ? "Ended" : "Not started")
            Button("Unlock forever" + (store.unlockPrice.isEmpty ? "" : " · \(store.unlockPrice)")) { router.showPaywall = true }
        case .loading:
            ProgressView()
        }
    }

    private func choose(_ t: AppTheme) {
        themeID = t.id
        Haptics.tap()
        Library.refreshWidgets(ctx)
        guard UIApplication.shared.supportsAlternateIcons, UIApplication.shared.alternateIconName != t.iconName else { return }
        UIApplication.shared.setAlternateIconName(t.iconName) { _ in }
    }

    private func readBackup(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            pending = try Backup.parse(try Data(contentsOf: url))
        } catch {
            message = "That file isn't a Pageturner or Reading Tracker backup."
        }
    }

    private func writeExports() {
        let dir = FileManager.default.temporaryDirectory
        let stamp = Day.key(.now)
        let json = dir.appendingPathComponent("pageturner-\(stamp).json")
        let csv = dir.appendingPathComponent("pageturner-\(stamp).csv")
        do {
            try Backup.export(ctx).write(to: json)
            try Backup.csv(ctx).data(using: .utf8)?.write(to: csv)
            exportFile = json
            csvFile = csv
        } catch {
            exportFile = nil
            csvFile = nil
        }
    }
}

struct ThemeSwatch: View {
    let theme: AppTheme
    let selected: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.board)
                VStack(alignment: .leading, spacing: 5) {
                    Capsule().fill(theme.brand).frame(width: 44, height: 8)
                    Capsule().fill(theme.highlight).frame(width: 28, height: 8)
                    Capsule().fill(theme.boardMuted).frame(width: 18, height: 8)
                }
                .padding(10)
            }
            .frame(height: 64)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(selected ? theme.brand : .clear, lineWidth: 3))
            Text(theme.name).font(.footnote.weight(selected ? .bold : .regular))
        }
        .accessibilityElement()
        .accessibilityLabel("\(theme.name) colour scheme")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}
