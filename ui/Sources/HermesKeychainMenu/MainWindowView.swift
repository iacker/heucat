import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var model: AppModel
    var autoRefresh = true

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $model.selectedSection) { section in
                Label(section.rawValue, systemImage: section.icon).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
            .safeAreaInset(edge: .top) { brand }
            .safeAreaInset(edge: .bottom) { sidebarStatus }
        } detail: {
            Group {
                switch model.selectedSection ?? .overview {
                case .overview: OverviewView()
                case .secrets: SecretsView()
                case .sessions: SessionsView()
                case .profiles: SealedProfilesView()
                case .diagnostics: DiagnosticsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            .toolbar { toolbar }
        }
        .frame(minWidth: 900, minHeight: 620)
        .sheet(isPresented: $model.showingAddSecret) { AddSecretView() }
        .alert("Remove this secret?", isPresented: Binding(
            get: { model.pendingDeletion != nil },
            set: { if !$0 { model.pendingDeletion = nil } }
        ), presenting: model.pendingDeletion) { secret in
            Button("Cancel", role: .cancel) { model.pendingDeletion = nil }
            Button("Remove", role: .destructive) {
                model.pendingDeletion = nil
                Task { await model.delete(secret) }
            }
        } message: { secret in
            Text("\(secret.name) will be removed from the Keychain, encrypted storage and any active session. This cannot be undone.")
        }
        .task { if autoRefresh { await model.refresh() } }
    }

    private var brand: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.gradient)
                Image(systemName: "key.fill").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
            }.frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text("Hermes Keychain").font(.headline)
                Text("Secure secrets for Hermes").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }.padding(.horizontal, 14).padding(.vertical, 12)
    }

    private var sidebarStatus: some View {
        HStack(spacing: 8) {
            Circle().fill(model.status.sourceEnabled ? .green : .orange).frame(width: 7, height: 7)
            Text(model.status.sourceEnabled ? "Protection active" : "Needs attention")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }.padding(14)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if model.isBusy { ProgressView().controlSize(.small) }
            Button { Task { await model.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .disabled(model.isBusy).help("Refresh protection status")
            Button { model.showingAddSecret = true } label: { Label("Add Secret", systemImage: "plus") }
                .buttonStyle(.borderedProminent).disabled(model.isBusy)
        }
    }
}

struct OverviewView: View {
    @EnvironmentObject private var model: AppModel
    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                pageHeader("Overview", "Hardware-backed protection for your Hermes credentials")
                LazyVGrid(columns: columns, spacing: 14) {
                    MetricCard(title: "Protected secrets", value: "\(model.status.configuredCount)", icon: "key.horizontal.fill", tint: .blue)
                    MetricCard(title: "Secure Enclave", value: model.status.enclaveKeyPresent ? "Ready" : "Unavailable", icon: "cpu.fill", tint: .purple)
                    MetricCard(title: "Secret source", value: model.status.sourceEnabled ? "Connected" : "Disabled", icon: "link.circle.fill", tint: .green)
                }
                protectionCard
                recentSecrets
            }.padding(32)
        }
    }

    private var protectionCard: some View {
        HStack(spacing: 22) {
            ZStack {
                Circle().fill(.green.opacity(0.12))
                Image(systemName: model.status.sourceEnabled ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 34)).foregroundStyle(model.status.sourceEnabled ? .green : .orange)
            }.frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 5) {
                Text(model.status.sourceEnabled ? "Your secret source is protected" : "Protection needs attention")
                    .font(.title3.weight(.semibold))
                Text("Values stay out of configuration files and are never displayed by this app.")
                    .foregroundStyle(.secondary)
                Text(model.message).font(.caption).foregroundStyle(.secondary).padding(.top, 3)
            }
            Spacer()
            Button("Manage secrets") { model.selectedSection = .secrets }
        }.padding(22).background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary))
    }

    private var recentSecrets: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Secrets").font(.title3.weight(.semibold))
                Spacer()
                if !model.status.secrets.isEmpty {
                    Button("View all") { model.selectedSection = .secrets }
                        .buttonStyle(.plain).foregroundStyle(.tint)
                }
            }
            if model.status.secrets.isEmpty {
                EmptySecretsView(compact: true)
            } else {
                ForEach(model.status.secrets.prefix(4)) { SecretRow(secret: $0) }
            }
        }
    }
}

struct SecretsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    private var filtered: [SecretStatus] { query.isEmpty ? model.status.secrets : model.status.secrets.filter { $0.name.localizedCaseInsensitiveContains(query) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            pageHeader("Secrets", "Manage references safely. Secret values are never revealed.")
            HStack {
                TextField("Search secrets", text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 300)
                Spacer()
                Button("Add secret", systemImage: "plus") { model.showingAddSecret = true }.buttonStyle(.borderedProminent)
            }
            if filtered.isEmpty {
                EmptySecretsView(compact: false).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filtered) { secret in
                            SecretRow(secret: secret, showActions: true)
                        }
                    }
                }
            }
        }.padding(32)
    }
}

struct SessionsView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            pageHeader("Sessions", "Control temporary access to Secure Enclave secrets")
            HStack(spacing: 18) {
                ZStack { Circle().fill(.blue.opacity(0.12)); Image(systemName: "touchid").font(.system(size: 42)).foregroundStyle(.blue) }.frame(width: 88, height: 88)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Authenticate once, work securely").font(.title2.weight(.semibold))
                    Text("Touch ID opens a time-limited session for all Enclave-protected secrets. Hermes startup remains silent and non-interactive.").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(24).background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
            HStack(spacing: 12) {
                Button("Unlock with Touch ID", systemImage: "touchid") { Task { await model.unlock() } }.buttonStyle(.borderedProminent).controlSize(.large).disabled(model.isBusy || model.status.configuredCount == 0)
                Button("Lock all sessions", systemImage: "lock.fill") { Task { await model.lock() } }.controlSize(.large).disabled(model.isBusy || model.status.configuredCount == 0)
            }
            Divider()
            Label("Session plaintext is held only in TTL-bounded macOS Keychain records and can be cleared immediately.", systemImage: "info.circle").foregroundStyle(.secondary)
            Spacer()
        }.padding(32)
    }
}

struct DiagnosticsView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            pageHeader("Diagnostics", "Local paths and runtime health. No secret values are shown.")
            GroupBox {
                LabeledContent("Hermes CLI", value: model.hermesBinary)
                Divider(); LabeledContent("Hermes home", value: model.hermesHome)
                Divider(); LabeledContent("Helper", value: model.status.helperPath)
                Divider(); LabeledContent("Secure Enclave key", value: model.status.enclaveKeyPresent ? "Present" : "Missing")
                Divider(); LabeledContent("Last status", value: model.message)
            }
            HStack {
                Button("Open keychain folder", systemImage: "folder") { model.openKeychainFolder() }
                SettingsLink { Label("Settings", systemImage: "gearshape") }
                Button("View source", systemImage: "chevron.left.forwardslash.chevron.right") { model.openRepository() }
            }
            Spacer()
        }.padding(32)
    }
}

struct SealedProfilesView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            pageHeader("Sealed Profiles", "Hardware-gated protection for complete Hermes profiles")
            HStack(spacing: 20) {
                ZStack {
                    Circle().fill((model.chthoniosAvailable ? Color.indigo : Color.orange).opacity(0.12))
                    Image(systemName: "externaldrive.badge.lock")
                        .font(.system(size: 38)).foregroundStyle(model.chthoniosAvailable ? .indigo : .orange)
                }.frame(width: 84, height: 84)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Chthonios").font(.title2.weight(.semibold))
                    Text(model.chthoniosSummary).foregroundStyle(.secondary)
                    Label(model.chthoniosAvailable ? "Engine available" : "Engine unavailable",
                          systemImage: model.chthoniosAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(model.chthoniosAvailable ? .green : .orange)
                }
                Spacer()
                Button("Refresh") { Task { await model.refreshChthonios() } }
            }
            .padding(24).background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary))

            GroupBox("Security boundary") {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Secure Enclave protects individual runtime secrets on this Mac.", systemImage: "cpu")
                    Label("Chthonios seals a complete profile so it becomes unusable at rest.", systemImage: "archivebox.fill")
                    Label("YubiKey unsealing requires your physical key, PIN and touch.", systemImage: "key.horizontal.fill")
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            Label("Seal and unseal remain separate from routine secret management. Hardware unsealing must be performed by you in a terminal.", systemImage: "hand.raised.fill")
                .foregroundStyle(.secondary)
            Spacer()
        }.padding(32)
    }
}

struct MetricCard: View {
    let title: String, value: String, icon: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: icon).font(.title2).foregroundStyle(tint)
            Text(value).font(.title2.weight(.semibold))
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
    }
}

struct SecretRow: View {
    @EnvironmentObject private var model: AppModel
    let secret: SecretStatus
    var showActions = false
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill((secret.mode == "enclave" ? Color.purple : Color.blue).opacity(0.12))
                Image(systemName: secret.mode == "enclave" ? "cpu" : "key.fill").foregroundStyle(secret.mode == "enclave" ? .purple : .blue)
            }.frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 4) {
                Text(secret.name).font(.system(.body, design: .monospaced, weight: .medium))
                Text(secret.mode == "enclave" ? "Secure Enclave" : "Apple Keychain").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Label(secret.isUnlocked ? "Available" : secret.state.capitalized, systemImage: secret.isUnlocked ? "checkmark.circle.fill" : "lock.fill")
                .font(.caption.weight(.medium)).foregroundStyle(secret.isUnlocked ? .green : .orange)
            if showActions {
                Menu {
                    Button("Remove", systemImage: "trash", role: .destructive) { model.pendingDeletion = secret }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 28)
            }
        }.padding(14).background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }
}

struct EmptySecretsView: View {
    @EnvironmentObject private var model: AppModel
    let compact: Bool
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.horizontal").font(.system(size: compact ? 28 : 40)).foregroundStyle(.secondary)
            Text("No secrets yet").font(.title3.weight(.semibold))
            Text("Add your first credential without leaving a plaintext copy behind.").foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Add secret", systemImage: "plus") { model.showingAddSecret = true }.buttonStyle(.borderedProminent)
        }.frame(maxWidth: .infinity).padding(compact ? 20 : 32)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(style: StrokeStyle(lineWidth: 1, dash: [5])).foregroundStyle(.quaternary))
    }
}

@ViewBuilder func pageHeader(_ title: String, _ subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.largeTitle.weight(.semibold))
        Text(subtitle).foregroundStyle(.secondary)
    }
}
