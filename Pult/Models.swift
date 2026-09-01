import Foundation
import Observation
import SwiftUI

enum HostOS: String, Codable, CaseIterable {
    case windows, mac, linux
    var title: String { switch self { case .windows: "Windows"; case .mac: "macOS"; case .linux: "Linux" } }
    var symbol: String { switch self { case .windows: "laptopcomputer"; case .mac: "desktopcomputer"; case .linux: "server.rack" } }
}

enum LinkKind: String, Codable {
    case lan, tailscale
    var title: String { self == .tailscale ? "Tailscale" : "Wi-Fi" }
    var symbol: String { self == .tailscale ? "network" : "wifi" }
}

struct DiscoveredHost: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var os: HostOS
    var host: String
    var port: Int
    var isOnline: Bool
    var link: LinkKind
}

enum ConnectionState: Equatable {
    case idle, browsing, connecting, pairing, connected, failed(String)
    var isLive: Bool { if case .connected = self { return true }; return false }
}

struct RemoteEntry: Identifiable, Hashable, Codable {
    var id: String { path }
    var name: String
    var path: String
    var isDir: Bool
    var size: Int64
    var kind: String?
    var sizeText: String {
        guard !isDir else { return "Папка" }
        if size < 1024 { return "\(size) Б" }
        if size < 1_048_576 { return String(format: "%.1f КБ", Double(size) / 1024) }
        return String(format: "%.1f МБ", Double(size) / 1_048_576)
    }
}

struct RemoteApp: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var path: String
}

enum ControlCommand: Encodable {
    case move(dx: Double, dy: Double)
    case click(button: String)
    case tap(x: Double, y: Double, button: String)
    case scroll(dx: Double, dy: Double)
    case type(text: String)
    case key(code: String, modifiers: [String])
    case media(action: String)
    case system(action: String)
    case pair(pin: String)
    case ping
    case stream(on: Bool, quality: String)
    case listDir(path: String)
    case download(path: String)
    case upload(path: String, name: String, data: String)
    case apps
    case launch(id: String)
    case openUrl(url: String)
    case fetchUrl(url: String)

    enum CodingKeys: String, CodingKey {
        case type, dx, dy, button, text, code, modifiers, action, pin
        case x, y, on, quality, path, name, data, id, url
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .move(let dx, let dy):
            try c.encode("move", forKey: .type); try c.encode(dx, forKey: .dx); try c.encode(dy, forKey: .dy)
        case .click(let button):
            try c.encode("click", forKey: .type); try c.encode(button, forKey: .button)
        case .tap(let x, let y, let button):
            try c.encode("tap", forKey: .type); try c.encode(x, forKey: .x); try c.encode(y, forKey: .y); try c.encode(button, forKey: .button)
        case .scroll(let dx, let dy):
            try c.encode("scroll", forKey: .type); try c.encode(dx, forKey: .dx); try c.encode(dy, forKey: .dy)
        case .type(let text):
            try c.encode("type", forKey: .type); try c.encode(text, forKey: .text)
        case .key(let code, let modifiers):
            try c.encode("key", forKey: .type); try c.encode(code, forKey: .code); try c.encode(modifiers, forKey: .modifiers)
        case .media(let action):
            try c.encode("media", forKey: .type); try c.encode(action, forKey: .action)
        case .system(let action):
            try c.encode("system", forKey: .type); try c.encode(action, forKey: .action)
        case .pair(let pin):
            try c.encode("pair", forKey: .type); try c.encode(pin, forKey: .pin)
        case .ping:
            try c.encode("ping", forKey: .type)
        case .stream(let on, let quality):
            try c.encode("stream", forKey: .type); try c.encode(on, forKey: .on); try c.encode(quality, forKey: .quality)
        case .listDir(let path):
            try c.encode("listDir", forKey: .type); try c.encode(path, forKey: .path)
        case .download(let path):
            try c.encode("download", forKey: .type); try c.encode(path, forKey: .path)
        case .upload(let path, let name, let data):
            try c.encode("upload", forKey: .type); try c.encode(path, forKey: .path); try c.encode(name, forKey: .name); try c.encode(data, forKey: .data)
        case .apps:
            try c.encode("apps", forKey: .type)
        case .launch(let id):
            try c.encode("launch", forKey: .type); try c.encode(id, forKey: .id)
        case .openUrl(let url):
            try c.encode("openUrl", forKey: .type); try c.encode(url, forKey: .url)
        case .fetchUrl(let url):
            try c.encode("fetchUrl", forKey: .type); try c.encode(url, forKey: .url)
        }
    }
}

@Observable
final class SessionStore {
    var hosts: [DiscoveredHost] = []
    var selected: DiscoveredHost?
    var connectionState: ConnectionState = .idle
    var sensitivity: Double = 1.4
    var lastError: String?
    var previewMode = false
    var frameJPEG: Data?
    var frameSize: CGSize = .zero
    var fps: Int = 0
    var streamQuality = "medium"
    var currentPath = ""
    var entries: [RemoteEntry] = []
    var filesLoading = false
    var incomingFile: (name: String, data: Data)?
    var apps: [RemoteApp] = []
    var appsLoading = false
    var savedPIN: String = UserDefaults.standard.string(forKey: "pult.pin") ?? ""

    private let savedKey = "pult.savedHosts"

    init() { loadSaved() }

    func remember(_ host: DiscoveredHost, pin: String? = nil) {
        var next = hosts.filter { $0.id != host.id }
        next.insert(host, at: 0)
        hosts = Array(next.prefix(8))
        persist()
        if let pin, pin.count == 4 {
            savedPIN = pin
            UserDefaults.standard.set(pin, forKey: "pult.pin")
        }
    }

    func mergeDiscovered(_ found: [DiscoveredHost]) {
        var byID = Dictionary(uniqueKeysWithValues: hosts.map { ($0.id, $0) })
        for item in found { byID[item.id] = item }
        hosts = byID.values.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private func loadSaved() {
        guard let data = UserDefaults.standard.data(forKey: savedKey),
              let items = try? JSONDecoder().decode([DiscoveredHost].self, from: data) else { return }
        hosts = items
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(hosts) {
            UserDefaults.standard.set(data, forKey: savedKey)
        }
    }
}
