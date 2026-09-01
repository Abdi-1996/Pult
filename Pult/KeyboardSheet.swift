import SwiftUI

struct KeyboardSheet: View {
    let service: ConnectionService
    @State private var text = ""
    @State private var ctrl = false
    @State private var alt = false
    @State private var shift = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextField("Текст уйдёт на компьютер", text: $text, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit { sendText() }

                HStack {
                    modifier("Ctrl", $ctrl)
                    modifier("Alt", $alt)
                    modifier("Shift", $shift)
                    Button("Enter") { sendKey("enter") }
                        .buttonStyle(.bordered)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(["esc", "tab", "backspace", "delete", "up", "down", "left", "right", "f5", "f11", "win", "cmd"], id: \.self) { code in
                        Button(code.uppercased()) { sendKey(code) }
                            .buttonStyle(.bordered)
                    }
                }

                Button("Отправить текст") { sendText() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(text.isEmpty)

                Spacer()
            }
            .padding()
            .navigationTitle("Клавиатура")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { focused = true }
        }
    }

    private func modifier(_ title: String, _ flag: Binding<Bool>) -> some View {
        Button(title) { flag.wrappedValue.toggle() }
            .buttonStyle(.bordered)
            .tint(flag.wrappedValue ? .blue : .primary)
    }

    private func sendText() {
        let snapshot = text
        guard !snapshot.isEmpty else { return }
        text = ""
        Task { try? await service.send(.type(text: snapshot)) }
    }

    private func sendKey(_ code: String) {
        var mods: [String] = []
        if ctrl { mods.append("ctrl") }
        if alt { mods.append("alt") }
        if shift { mods.append("shift") }
        Task { try? await service.send(.key(code: code, modifiers: mods)) }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }
}
