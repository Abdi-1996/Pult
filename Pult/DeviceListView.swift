import SwiftUI

struct DeviceListView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ConnectionService.self) private var service
    @State private var pairingHost: DiscoveredHost?
    @State private var pin = ""
    @State private var showManual = false
    @State private var manualName = "Мой ПК"
    @State private var manualAddress = ""
    @State private var link: LinkKind = .tailscale

    var body: some View {
        Group {
            if session.hosts.isEmpty { empty } else { list }
        }
        .navigationTitle("Компьютеры")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showManual = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $pairingHost) { host in
            PairingSheet(host: host, pin: $pin) {
                Task {
                    session.previewMode = false
                    try? await service.connect(to: host, pin: pin)
                    pairingHost = nil
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showManual) {
            ManualConnectSheet(name: $manualName, address: $manualAddress, link: $link) {
                let raw = manualAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                let host = DiscoveredHost(
                    id: raw.lowercased(),
                    name: manualName.isEmpty ? raw : manualName,
                    os: .windows,
                    host: raw,
                    port: 17420,
                    isOnline: true,
                    link: link
                )
                pairingHost = host
                showManual = false
            }
            .presentationDetents([.medium])
        }
        .onAppear {
            service.store = session
            if pin.isEmpty, session.savedPIN.count == 4 { pin = session.savedPIN }
        }
    }

    private var list: some View {
        List(session.hosts) { host in
            Button { pairingHost = host } label: {
                HStack(spacing: 12) {
                    Image(systemName: host.os.symbol)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(host.name).font(.body.weight(.semibold))
                        Text(host.host).font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label(host.link.title, systemImage: host.link.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(host.link == .tailscale ? Color.cyan : Color.green)
                }
            }
        }
    }

    private var empty: some View {
        ContentUnavailableView(
            "Нет компьютеров",
            systemImage: "laptopcomputer.and.iphone",
            description: Text("Первый раз: + и IP из агента. Дальше приложение подключается само.")
        )
    }
}

struct PairingSheet: View {
    let host: DiscoveredHost
    @Binding var pin: String
    var onConnect: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(host.link == .tailscale ? "Tailscale · \(host.host)" : "Wi-Fi · \(host.host)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("PIN из окна агента").font(.title3.weight(.semibold))
                TextField("••••", text: $pin)
                    .keyboardType(.numberPad)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .focused($focused)
                    .onChange(of: pin) { _, value in pin = String(value.filter(\.isNumber).prefix(4)) }
                Button("Подключить") { onConnect() }
                    .buttonStyle(.borderedProminent)
                    .disabled(pin.count != 4)
                Spacer()
            }
            .padding()
            .navigationTitle("Подключение")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } } }
            .onAppear { focused = true }
        }
    }
}

struct ManualConnectSheet: View {
    @Binding var name: String
    @Binding var address: String
    @Binding var link: LinkKind
    var onAdd: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Picker("Сеть", selection: $link) {
                    Text("Tailscale").tag(LinkKind.tailscale)
                    Text("Wi-Fi").tag(LinkKind.lan)
                }
                .pickerStyle(.segmented)
                TextField("Имя", text: $name)
                TextField(link == .tailscale ? "100.x.x.x или имя.ts.net" : "192.168.x.x", text: $address)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .navigationTitle("Подключить")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Далее") { onAdd() }.disabled(address.trimmingCharacters(in: .whitespaces).count < 3)
                }
            }
        }
    }
}
