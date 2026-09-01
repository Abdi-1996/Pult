import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct FilesView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ConnectionService.self) private var service
    @State private var importer = false
    @State private var shareURL: URL?
    @State private var query = ""

    var body: some View {
        List {
            if session.filesLoading { ProgressView("Читаем диск ПК…") }
            Section("Папки") {
                ForEach(visible.filter(\.isDir)) { item in
                    Button {
                        Task { session.filesLoading = true; try? await service.send(.listDir(path: item.path)) }
                    } label: { Label(item.name, systemImage: "folder.fill") }
                }
            }
            Section("Файлы") {
                ForEach(visible.filter { !$0.isDir }) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.name)
                            Text(item.sizeText).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { Task { try? await service.send(.download(path: item.path)) } } label: {
                            Image(systemName: "arrow.down.circle")
                        }
                    }
                }
            }
        }
        .navigationTitle("Файлы")
        .searchable(text: $query)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { importer = true } label: { Image(systemName: "square.and.arrow.up") }
            }
        }
        .fileImporter(isPresented: $importer, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { return }
            Task {
                try? await service.send(.upload(path: session.currentPath, name: url.lastPathComponent, data: data.base64EncodedString()))
                try? await service.send(.listDir(path: session.currentPath))
            }
        }
        .onChange(of: session.incomingFile?.name) { _, _ in
            guard let incoming = session.incomingFile else { return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(incoming.name)
            try? incoming.data.write(to: url)
            shareURL = url
            session.incomingFile = nil
        }
        .sheet(item: Binding(get: { shareURL.map(IdentifiedURL.init) }, set: { shareURL = $0?.url })) { item in
            ShareSheet(url: item.url)
        }
        .onAppear { if session.entries.isEmpty { Task { try? await service.send(.listDir(path: session.currentPath)) } } }
        .refreshable { try? await service.send(.listDir(path: session.currentPath)) }
    }

    private var visible: [RemoteEntry] {
        if query.isEmpty { return session.entries }
        return session.entries.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
}

private struct IdentifiedURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
