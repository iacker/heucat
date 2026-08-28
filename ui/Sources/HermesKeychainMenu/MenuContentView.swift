import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var loc = Loc.shared
    var autoRefresh = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            summary

            if model.status.secrets.isEmpty {
                ContentUnavailableView(
                    L("menu.noSecrets"),
                    systemImage: "key",
                    description: Text(L("overview.useCliHint"))
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
                Text(L("app.title"))
                    .font(.headline)
                Text(L("overview.appleStack"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isBusy { ProgressView().controlSize(.small) }
        }
    }

    private var summary: some View {
        HStack {
            Label(L(model.status.sourceEnabled ? "menu.sourceEnabled" : "menu.sourceDisabled"),
                  systemImage: model.status.sourceEnabled ? "checkmark.circle.fill" : "xmark.circle")
            Spacer()
            Label(L(model.status.enclaveKeyPresent ? "menu.enclaveReady" : "menu.noEnclaveKey"),
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
            Button(L("menu.unlock"), systemImage: "touchid") {
                Task { await model.unlock() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isBusy || model.status.configuredCount == 0)

            Button(L("menu.lock"), systemImage: "lock.fill") {
                Task { await model.lock() }
            }
            .disabled(model.isBusy || model.status.configuredCount == 0)

            Button(L("app.refresh"), systemImage: "arrow.clockwise") {
                Task { await model.refresh() }
            }
            .disabled(model.isBusy)

            Spacer()

            Menu {
                SettingsLink { Text(L("app.settings")) }
                Button(L("diag.openGitHub")) { model.openRepository() }
                Divider()
                Button(L("app.quit")) { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
        }
    }
}
