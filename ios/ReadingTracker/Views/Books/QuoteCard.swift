import SwiftUI
import UIKit

/// A quote (or thought) laid out as a shareable picture, in a colour scheme of the reader's choice.
struct QuoteCard: View {
    enum Shape: String, CaseIterable, Identifiable {
        case square = "Square", story = "Story"
        var id: String { rawValue }
        /// Points; rendered at 3× (1080 px wide).
        var size: CGSize { self == .square ? CGSize(width: 360, height: 360) : CGSize(width: 360, height: 640) }
    }

    let text: String
    let isQuote: Bool
    let title: String
    let author: String
    let page: Int?
    let theme: AppTheme
    let shape: Shape
    var background: CardBackground = .glow

    var body: some View {
        let story = shape == .story
        VStack(alignment: .leading, spacing: story ? 22 : 14) {
            HStack(spacing: 5) {
                Capsule().fill(theme.brand).frame(width: 40, height: 7)
                Capsule().fill(theme.highlight).frame(width: 26, height: 7)
                Capsule().fill(theme.boardMuted).frame(width: 14, height: 7)
            }
            Spacer(minLength: 0)
            if isQuote {
                Text("“")
                    .font(.system(size: story ? 86 : 64, weight: .black, design: .serif))
                    .foregroundStyle(theme.highlight)
                    .frame(height: story ? 44 : 32, alignment: .top)
            }
            Text(text)
                .font(.system(size: story ? 27 : 21, weight: .semibold, design: .serif))
                .lineSpacing(story ? 6 : 4)
                .foregroundStyle(theme.boardText)
                .minimumScaleFactor(0.35)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: story ? 18 : 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(theme.brand)
                    .lineLimit(2)
                let byline = [author.isEmpty ? nil : author, page.map { "p. \($0)" }].compactMap { $0 }.joined(separator: " · ")
                if !byline.isEmpty {
                    Text(byline).font(.system(size: story ? 15 : 13, weight: .medium)).foregroundStyle(theme.boardMuted).lineLimit(1)
                }
            }
            HStack {
                Spacer()
                Text("Pageturner").font(.system(size: story ? 13 : 11, weight: .heavy, design: .rounded)).foregroundStyle(theme.boardMuted)
            }
        }
        .padding(story ? 34 : 26)
        .frame(width: shape.size.width, height: shape.size.height)
        .background(CardBackdrop(style: background, theme: theme))
        .environment(\.colorScheme, .dark)
    }
}

/// Preview a note as a card, pick a shape and colours, then share or save it.
struct QuoteCardSheet: View {
    let note: BookNote

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var currentTheme
    @State private var shape: QuoteCard.Shape = .square
    @State private var themeID = ""
    @AppStorage("cardBackground") private var backgroundRaw = CardBackground.glow.rawValue
    @State private var image: UIImage?

    private var cardTheme: AppTheme { AppTheme.named(themeID.isEmpty ? currentTheme.id : themeID) }
    private var background: CardBackground { CardBackground(rawValue: backgroundRaw) ?? .glow }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Group {
                        if let image {
                            Image(uiImage: image).resizable().scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                                .accessibilityLabel("Quote card preview")
                        } else {
                            ProgressView().frame(height: 300)
                        }
                    }
                    .frame(maxHeight: shape == .story ? 480 : 340)

                    Picker("Shape", selection: $shape) {
                        ForEach(QuoteCard.Shape.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    BackgroundPicker(selection: $backgroundRaw, theme: cardTheme)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(AppTheme.all) { t in
                                Button { themeID = t.id } label: {
                                    VStack(spacing: 4) {
                                        ZStack {
                                            Circle().fill(t.board)
                                            Circle().fill(t.brand).frame(width: 18, height: 18).offset(x: -6, y: -4)
                                            Circle().fill(t.highlight).frame(width: 12, height: 12).offset(x: 8, y: 6)
                                        }
                                        .frame(width: 44, height: 44)
                                        .overlay(Circle().strokeBorder(t.id == cardTheme.id ? Color.primary : .clear, lineWidth: 2.5))
                                        Text(t.name).font(.caption2)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(t.name) colours")
                            }
                        }
                        .padding(.horizontal, 2)
                    }

                    if let image {
                        ShareLink(item: Image(uiImage: image),
                                  preview: SharePreview(note.book?.title ?? "Quote", image: Image(uiImage: image))) {
                            Label("Share or save", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(PillButton(kind: .brand, big: true))
                        .accessibilityIdentifier("cardShare")
                    }
                    Text("Share to Instagram, Messages or WhatsApp, or choose Save Image to keep it in Photos.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(16)
            }
            .navigationTitle(note.kind == .quote ? "Quote card" : "Note card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { if themeID.isEmpty { themeID = currentTheme.id }; render() }
            .onChange(of: shape) { _, _ in render() }
            .onChange(of: themeID) { _, _ in render() }
            .onChange(of: backgroundRaw) { _, _ in render() }
        }
    }

    @MainActor private func render() {
        let card = QuoteCard(text: note.text, isQuote: note.kind == .quote, title: note.book?.title ?? "",
                             author: note.book?.author ?? "", page: note.page, theme: cardTheme, shape: shape,
                             background: background)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        image = renderer.uiImage
    }
}

/// A row of small previews of each background style.
struct BackgroundPicker: View {
    @Binding var selection: String
    let theme: AppTheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(CardBackground.allCases) { b in
                    Button { selection = b.rawValue } label: {
                        VStack(spacing: 4) {
                            CardBackdrop(style: b, theme: theme)
                                .frame(width: 54, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(selection == b.rawValue ? Color.primary : Color.clear, lineWidth: 2.5))
                                .environment(\.colorScheme, .dark)
                            Text(b.rawValue).font(.caption2)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(b.rawValue) background")
                    .accessibilityIdentifier("bg-\(b.rawValue)")
                }
            }
            .padding(.horizontal, 2)
        }
    }
}
