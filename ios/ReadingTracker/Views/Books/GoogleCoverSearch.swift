import SwiftUI
import WebKit

/// Finding a cover with Google Images, inside the app: tap the cover you want, then "Use this image".
enum GoogleCovers {
    /// Google Images results for a book: "<title> <author> book cover", or an ISBN on its own.
    static func searchURL(query: String) -> URL {
        var c = URLComponents(string: "https://www.google.com/search")!
        c.queryItems = [URLQueryItem(name: "tbm", value: "isch"), URLQueryItem(name: "q", value: query)]
        return c.url!
    }

    static func query(title: String, author: String) -> String {
        [title, author, "book cover"].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Finds the biggest picture currently showing on the page (the one you tapped to enlarge),
    /// preferring sharper images when two are the same size, and returns its address.
    static let largestVisibleImageJS = """
    (() => {
      let best = null, bestScore = 0;
      for (const img of document.images) {
        const r = img.getBoundingClientRect();
        const w = Math.max(0, Math.min(r.right, innerWidth) - Math.max(r.left, 0));
        const h = Math.max(0, Math.min(r.bottom, innerHeight) - Math.max(r.top, 0));
        if (w < 40 || h < 40 || img.naturalWidth < 60) continue;
        const score = w * h + Math.min(img.naturalWidth * img.naturalHeight, 4e6) / 1000;
        if (score > bestScore) { bestScore = score; best = img; }
      }
      return best ? (best.currentSrc || best.src) : null;
    })()
    """

    /// Turns a picture address from the page into cover-sized JPEG data:
    /// a "data:image/…;base64,…" picture is decoded directly; a web address is downloaded.
    static func imageData(fromSource src: String) async -> Data? {
        if src.hasPrefix("data:") {
            guard let comma = src.firstIndex(of: ","), src[..<comma].contains(";base64"),
                  let raw = Data(base64Encoded: String(src[src.index(after: comma)...]), options: .ignoreUnknownCharacters)
            else { return nil }
            return Covers.thumbnail(raw, maxSide: 600)
        }
        guard let url = URL(string: src), url.scheme == "https" || url.scheme == "http" else { return nil }
        var secure = URLComponents(url: url, resolvingAgainstBaseURL: false)
        secure?.scheme = "https"
        return await BookLookup.download(secure?.url ?? url)
    }
}

struct GoogleCoverSearchSheet: View {
    let query: String
    var onPick: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var web = WebHolder()
    @State private var working = false
    @State private var picked: UIImage?
    @State private var hint: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if web.failed {
                    Text("Couldn't open Google. Check your connection, then tap Cancel and try again.")
                        .font(.footnote).foregroundStyle(theme.brandText).padding(8)
                }
                WebView(holder: web, url: GoogleCovers.searchURL(query: query))
                    .overlay {
                        if let picked {
                            ZStack {
                                Color.black.opacity(0.55).ignoresSafeArea()
                                VStack(spacing: 12) {
                                    Image(uiImage: picked).resizable().scaledToFit().frame(maxHeight: 260)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    Label("Cover saved", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(.white)
                                }
                            }
                            .transition(.opacity)
                        }
                    }
                VStack(spacing: 8) {
                    Text(hint ?? "Tap the cover you want so it opens larger, then tap Use this image.")
                        .font(.footnote)
                        .foregroundStyle(hint == nil ? Color.secondary : theme.brandText)
                        .multilineTextAlignment(.center)
                    Button { Task { await useImage() } } label: {
                        Label(working ? "Getting the image…" : "Use this image", systemImage: "photo.badge.checkmark")
                    }
                    .buttonStyle(PillButton(kind: .brand, big: true))
                    .disabled(working)
                    .accessibilityIdentifier("useGoogleImage")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)
            }
            .navigationTitle("Google Images")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    if web.loading { ProgressView() }
                    Button { web.view?.goBack() } label: { Image(systemName: "chevron.backward") }
                        .disabled(!web.canGoBack)
                        .accessibilityLabel("Back")
                }
            }
        }
    }

    private func useImage() async {
        guard let view = web.view else { return }
        working = true
        hint = nil
        defer { working = false }
        let src = try? await view.evaluateJavaScript(GoogleCovers.largestVisibleImageJS) as? String
        guard let src, let data = await GoogleCovers.imageData(fromSource: src), let image = UIImage(data: data) else {
            hint = "Tap a cover to open it first, then tap Use this image."
            return
        }
        onPick(data)
        Haptics.success()
        withAnimation { picked = image }
        try? await Task.sleep(for: .milliseconds(900))
        dismiss()
    }
}

/// Keeps hold of the web view so the buttons can talk to it, and tracks loading and going back.
@MainActor
@Observable
final class WebHolder: NSObject, WKNavigationDelegate {
    var loading = true
    var canGoBack = false
    var failed = false
    @ObservationIgnored weak var view: WKWebView?

    func attach(_ v: WKWebView) {
        view = v
        v.navigationDelegate = self
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loading = true
        failed = false
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loading = false
        canGoBack = webView.canGoBack
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loading = false
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loading = false
        failed = true
    }
}

struct WebView: UIViewRepresentable {
    let holder: WebHolder
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: config)
        view.allowsBackForwardNavigationGestures = true
        holder.attach(view)
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}
}
