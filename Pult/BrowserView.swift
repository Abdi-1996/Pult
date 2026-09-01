import SwiftUI
import WebKit

struct BrowserView: View {
    @Environment(ConnectionService.self) private var service
    @State private var urlText = "https://www.google.com"
    @State private var currentURL = URL(string: "https://www.google.com")!
    @State private var note: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Адрес", text: $urlText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .onSubmit { go() }
                Button("Перейти", action: go)
            }
            .padding(10)
            WebStack(url: $currentURL, urlText: $urlText)
            HStack {
                Button("На ПК") { send(.openUrl(url: currentURL.absoluteString)); note = "Открыл в браузере компьютера" }
                Button("Скачать на ПК") { send(.fetchUrl(url: currentURL.absoluteString)); note = "Качаю в Загрузки ПК" }
            }
            .buttonStyle(.bordered)
            .padding(.vertical, 8)
            if let note {
                Text(note).font(.footnote).foregroundStyle(.secondary).padding(.bottom, 8)
            }
        }
        .navigationTitle("Браузер")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func go() {
        var raw = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return }
        if !raw.contains(".") { raw = "https://www.google.com/search?q=\(raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw)" }
        else if !raw.hasPrefix("http") { raw = "https://\(raw)" }
        if let url = URL(string: raw) {
            urlText = raw
            currentURL = url
        }
    }

    private func send(_ command: ControlCommand) {
        Task { try? await service.send(command) }
    }
}

private struct WebStack: UIViewRepresentable {
    @Binding var url: URL
    @Binding var urlText: String

    func makeCoordinator() -> Coord { Coord(urlText: $urlText) }

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.navigationDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        if view.url != url { view.load(URLRequest(url: url)) }
    }

    final class Coord: NSObject, WKNavigationDelegate {
        var urlText: Binding<String>
        init(urlText: Binding<String>) { self.urlText = urlText }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let abs = webView.url?.absoluteString { urlText.wrappedValue = abs }
        }
    }
}
