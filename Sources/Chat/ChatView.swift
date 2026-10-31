import CoreAIKitUI
import SwiftUI

struct ChatView: View {
    @State private var model = ChatModel()
    @State private var input = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                pickerBar
                DownloadsButton()
                    .padding(.trailing, 12)
            }
            if let reason = model.unavailableReason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                    .accessibilityIdentifier("chat.unavailableReason")
            }
            Divider()
            ChatTranscriptView(bubbles: model.bubbles)
            Divider()
            StatsBar(stats: model.stats)
            inputBar
        }
        .task { await model.loadCatalog() }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
    }

    /// CoreAIKitUI's ModelPickerBar, with the models this device has no bundle for marked in
    /// the menu and their Load button off, as the Speak picker marks its voices.
    private var pickerBar: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(model.entries) { entry in
                    Button {
                        model.selectedEntry = entry
                    } label: {
                        if entry == model.selectedEntry {
                            Label(Self.menuTitle(for: entry), systemImage: "checkmark")
                        } else {
                            Text(Self.menuTitle(for: entry))
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(model.selectedEntry?.name ?? "Model").lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(model.isBusy)
            .accessibilityIdentifier("chat.modelPicker")

            Button(model.status == .idle ? "Download & Load" : "Reload") { model.load() }
                .fixedSize()
                .disabled(model.isBusy || model.selectedEntry == nil || model.unavailableReason != nil)
                .accessibilityIdentifier("chat.load")

            Spacer(minLength: 8)

            if let fraction = model.downloadFraction {
                ProgressView(value: fraction).frame(width: 60)
            }
            Text(model.status.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .accessibilityIdentifier("chat.status")
        }
        .padding(10)
    }

    private static func menuTitle(for entry: CatalogEntry) -> String {
        let size = entry.variant?.sizeMB.map { " (\($0) MB)" } ?? ""
        return entry.unavailableReason == nil
            ? entry.name + size : "\(entry.name) (not on this device)"
    }

    private var inputBar: some View {
        HStack {
            TextField("Message", text: $input)
                .textFieldStyle(.roundedBorder)
                .onSubmit(send)
                .disabled(model.status != .ready)
            if model.status == .generating {
                Button("Stop") { model.stop() }
            } else {
                Button("Send", action: send)
                    .disabled(model.status != .ready || input.isEmpty)
            }
            if model.showThinkingToggle {
                Toggle("Think", isOn: $model.thinkingEnabled)
                    .toggleStyle(.button)
                    .disabled(model.status == .generating)
            }
            Button("New") { model.newChat() }
                .disabled(model.isBusy)
        }
        .padding(10)
    }

    private func send() {
        let text = input
        input = ""
        model.send(text)
    }
}
