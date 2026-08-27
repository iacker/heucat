import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject private var model: AppModel
    var autoRefresh = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            summary

            if model.status.secrets.isEmpty {
                ContentUnavailableView(
                    "No secrets configured",
                    systemImage: "key",
                    description: Text("Use `hermes keychain store` to add one safely.")
                )
                .frame(minHeight: 130)
            } else {
                secrets
            }

            Divider()
            controls
            Text(model.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(16)
        .frame(width: 390)
        .task {
            if autoRefresh { await model.refresh() }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: model.iconName)
                .font(.title2)
                .foregroundStyle(model.status.sourceEnabled ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("HEUCAT Keychain")
                    .font(.headline)
                Text("Apple Keychain + Secure Enclave")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isBusy { ProgressView().controlSize(.small) }
        }
    }

    private var summary: some View {
        HStack {
            Label(model.status.sourceEnabled ? "Source enabled" : "Source disabled",
                  systemImage: model.status.sourceEnabled ? "checkmark.circle.fill" : "xmark.circle")
            Spacer()
            Label(model.status.enclaveKeyPresent ? "Enclave ready" : "No enclave key",
                  systemImage: "cpu")
        }
        .font(.caption)
    }

    private var secrets: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(model.status.secrets) { secret in
                    HStack(spacing: 10) {
                        Image(systemName: secret.isUnlocked ? "lock.open.fill" : "lock.fill")
                            .foregroundStyle(secret.isUnlocked ? .green : .orange)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(secret.name).font(.system(.body, design: .monospaced))
                            Text("\(secret.mode) · \(secret.state)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(9)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
                }
            }
        }
        .frame(maxHeight: 260)
    }

    private var controls: some View {
        HStack {
            Button("Unlock", systemImage: "touchid") {
                Task { await model.unlock() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isBusy || model.status.configuredCount == 0)

            Button("Lock", systemImage: "lock.fill") {
                Task { await model.lock() }
            }
            .disabled(model.isBusy || model.status.configuredCount == 0)

            Button("Refresh", systemImage: "arrow.clockwise") {
                Task { await model.refresh() }
            }
            .disabled(model.isBusy)

            Spacer()

            Menu {
                SettingsLink { Text("Settings…") }
                Button("Open GitHub") { model.openRepository() }
                Divider()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
        }
    }
}
