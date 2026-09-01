import Foundation
import Network
import Observation

@Observable
final class ConnectionService {
    private var browser: NWBrowser?
    private var socket: URLSessionWebSocketTask?
    private let urlSession = URLSession(configuration: .default)
    private let queue = DispatchQueue(label: "pult.connection")
    private var frameTimes: [Date] = []
    weak var store: SessionStore?

    func startBrowsing() {
        store?.connectionState = .browsing
        let browser = NWBrowser(for: .bonjour(type: "_pultdesk._tcp", domain: "local."), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in self?.apply(results: results) }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                Task { @MainActor in self?.store?.connectionState = .failed(error.localizedDescription) }
            }
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    func stopBrowsing() { browser?.cancel(); browser = nil }

    func connect(to host: DiscoveredHost, pin: String) async throws {
        await MainActor.run {
            store?.connectionState = .connecting
            store?.selected = host
        }
        guard let url = URL(string: "ws://\(host.host):\(host.port)") else { throw URLError(.badURL) }
        let task = urlSession.webSocketTask(with: url)
        task.resume()
        socket = task
        try await send(.pair(pin: pin))
        await MainActor.run { store?.connectionState = .connected }
        listen()
        try await send(.stream(on: true, quality: store?.streamQuality ?? "medium"))
        try await send(.listDir(path: ""))
        try await send(.apps)
    }

    func disconnect() {
        Task { try? await send(.stream(on: false, quality: "medium")) }
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        Task { @MainActor in
            store?.connectionState = .idle
            store?.frameJPEG = nil
        }
    }

    func send(_ command: ControlCommand) async throws {
        if store?.previewMode == true { return }
        guard let socket else { throw URLError(.notConnectedToInternet) }
        let data = try JSONEncoder().encode(command)
        try await socket.send(.string(String(data: data, encoding: .utf8) ?? "{}"))
    }

    func sendMove(dx: Double, dy: Double) {
        Task { try? await send(.move(dx: dx, dy: dy)) }
    }

    private func listen() {
        socket?.receive { [weak self] result in
            switch result {
            case .failure:
                Task { @MainActor in self?.store?.connectionState = .failed("Связь оборвалась") }
            case .success(let message):
                self?.handle(message)
                self?.listen()
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .data(let d): data = d
        case .string(let s): data = Data(s.utf8)
        @unknown default: return
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return }
        Task { @MainActor in
            switch type {
            case "frame":
                if let b64 = obj["jpeg"] as? String, let jpeg = Data(base64Encoded: b64) {
                    store?.frameJPEG = jpeg
                    store?.frameSize = CGSize(width: obj["w"] as? Double ?? 0, height: obj["h"] as? Double ?? 0)
                    let now = Date()
                    frameTimes.append(now)
                    frameTimes = frameTimes.filter { now.timeIntervalSince($0) < 1 }
                    store?.fps = frameTimes.count
                }
            case "dir":
                store?.filesLoading = false
                store?.currentPath = obj["path"] as? String ?? ""
                if let raw = obj["entries"] as? [[String: Any]] {
                    store?.entries = raw.compactMap { item in
                        guard let name = item["name"] as? String, let path = item["path"] as? String else { return nil }
                        return RemoteEntry(name: name, path: path, isDir: item["isDir"] as? Bool ?? false, size: (item["size"] as? NSNumber)?.int64Value ?? 0, kind: item["kind"] as? String)
                    }
                }
            case "file":
                if let name = obj["name"] as? String, let b64 = obj["data"] as? String, let bin = Data(base64Encoded: b64) {
                    store?.incomingFile = (name, bin)
                }
            case "apps":
                store?.appsLoading = false
                if let raw = obj["items"] as? [[String: Any]] {
                    store?.apps = raw.compactMap { item in
                        guard let id = item["id"] as? String, let name = item["name"] as? String else { return nil }
                        return RemoteApp(id: id, name: name, path: item["path"] as? String ?? "")
                    }
                }
            case "error":
                store?.lastError = obj["message"] as? String
                store?.filesLoading = false
                store?.appsLoading = false
            default: break
            }
        }
    }

    private func apply(results: Set<NWBrowser.Result>) {
        let mapped: [DiscoveredHost] = results.compactMap { result in
            guard case let .service(name: name, type: _, domain: _, interface: _) = result.endpoint else { return nil }
            return DiscoveredHost(id: name, name: name, os: .windows, host: name, port: 17420, isOnline: true)
        }
        Task { @MainActor in store?.hosts = mapped.sorted { $0.name < $1.name } }
    }
}
