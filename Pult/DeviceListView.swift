import SwiftUI

struct DeviceListView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ConnectionService.self) private var service
    @State private var pairingHost: DiscoveredHost?
    @State private var pin = ""
    @State private var showManual = false
    @State private var manualIP = ""
    @State private var manualName = "Мой ПК"

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
            ManualConnectSheet(name: $manualName, ip: $manualIP) {
                pairingHost = DiscoveredHost(id: manualIP, name: manualName.isEmpty ? manualIP : manualName, os: .windows, host: manualIP.trimmingCharacters(in: .whitespaces), port: 17420, isOnline: true)
                showManual = false
            }
            .presentationDetents([.medium])
        }
        .onAppear {
            service.store = session
            service.startBrowsing()
        }
    }

    private var list: some View {
        List(session.hosts) { host in
            Button { if host.isOnline { pairingHost = host } } label: {
                HStack {
                    Image(systemName: host.os.symbol)
                    VStack(alignment: .leading) {
                        Text(host.name).font(.body.weight(.semibold))
                        Text(host.os.title).font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(host.isOnline ? "В сети" : "Не в сети").foregroundStyle(host.isOnline ? .green : .secondary)
                }
            }
        }
    }

    private var empty: some View {
        ContentUnavailableView("Нет компьютеров", systemImage: "laptopcomputer.and.iphone", description: Text("Поставьте агент и нажмите + чтобы ввести IP."))
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
                Text("Код на экране «\(host.name)»").font(.title2.weight(.semibold)).multilineTextAlignment(.center)
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
    @Binding var ip: String
    var onAdd: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Имя", text: $name)
                TextField("IP из окна агента", text: $ip).keyboardType(.decimalPad).textInputAutocapitalization(.never)
            }
            .navigationTitle("По IP")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Далее") { onAdd() }.disabled(ip.count < 7) }
            }
        }
    }
}
