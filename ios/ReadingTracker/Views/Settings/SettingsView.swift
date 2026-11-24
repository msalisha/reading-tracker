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
    @State private var sync: Sync.Status = .checking
    @State private var showGoodreads = false
    @State private var enricher = GoodreadsEnricher.shared
    @State private var syncOn = Persistence.syncEnabled
    @Environment(\.scenePhase) private var scenePhase

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
                    Toggle(isOn: Binding(get: { syncOn }, set: { on in setSync(on) })) {
                        Label("Sync with iCloud", systemImage: sync == .on ? "checkmark.icloud.fill" : "icloud")
                    }
                    .tint(theme.brand)
                    .accessibilityIdentifier("syncToggle")
                    if syncOn, sync != .on, sync != .checking {
                        LabeledContent("Status", value: sync.title).accessibilityIdentifier("syncStatus")
                    }
                } header: {
                    Text("iCloud")
                } footer: {
                    Text(sync.detail)
                }
                .task(id: scenePhase) { if scenePhase == .active { sync = await Sync.status() } }

                Section {
                    if let message {
                        Label(message, systemImage: message.hasPrefix("Imported") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(theme.brandText)
                            .accessibilityIdentifier("importResult")
                    }
                    Button { message = nil; importing = true } label: {
                        Label("Import a backup", systemImage: "arrow.down.doc")
                    }
                    Button {
                        if store.access.canEdit { showGoodreads = true } else { router.showPaywall = true }
                    } label: {
                        Label("Import from Goodreads", systemImage: "books.vertical")
                    }
                    .accessibilityIdentifier("goodreadsImport")
                    if enricher.isRunning {
                        HStack {
                            ProgressView(value: Double(enricher.done), total: Double(max(1, enricher.total)))
                            Text(enricher.progressText).font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                } header: {
                    Text("Bring data in")
                } footer: {
                    Text("Backups from Pageturner or the web Reading Tracker (Log → Save a backup), or your Goodreads library.")
                }

                Section {
                    if let exportFile {
                        ShareLink(item: exportFile) { Label("Save a backup", systemImage: "square.and.arrow.up") }
                    }
                    if let csvFile {
                        ShareLink(item: csvFile) { Label("Export as spreadsheet (CSV)", systemImage: "tablecells") }
                    }
                } header: {
                    Text("Take data out")
                } footer: {
                    Text("\(sync == .on ? "Your library" : "Stored on this iPhone"): \(books.count) books and \(sessions.count) sessions.")
                }

                Section {
                    Link(destination: Links.privacy) { Label("Privacy policy", systemImage: "hand.raised") }
                    Link(destination: Links.support) { Label("Help and support", systemImage: "questionmark.circle") }
                    Label("New: audiobooks, Goodreads import, six card styles", systemImage: "sparkles")
                        .font(.subheadline).foregroundStyle(.secondary)
                } header: {
                    Text("About")
                }
                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                }
            }
            .navigationTitle("Settings")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .plainText, .data]) { result in
                readBackup(result)
            }
            .alert("Import this backup?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
                Button("Import") {
                    guard let p = pending else { return }
                    pending = nil
                    // Let the question close fully before changing the library, then show the result on the page (no second pop-up).
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(400))
                        Backup.restore(p, into: ctx)
                        message = "Imported \(p.books.count) books and \(p.sessions.count) sessions."
                    }
                }
                Button("Cancel", role: .cancel) { pending = nil }
            } message: {
                if let p = pending {
                    Text("It has \(p.books.count) books, \(p.sessions.count) sessions (\(p.totalPages.formatted()) pages) and \(p.notes.count) notes. Books you already have are updated, not duplicated.")
                }
            }
            .purchaseAlert()
            .sheet(isPresented: $showGoodreads) { GoodreadsImportSheet().environment(\.theme, theme) }
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

    /// Save the choice and reopen the library with sync on or off. Nothing is deleted either way.
    private func setSync(_ on: Bool) {
        guard on != Persistence.syncEnabled else { return }
        Persistence.syncEnabled = on
        syncOn = on
        sync = on ? .checking : .turnedOff
        router.libraryGeneration += 1
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
