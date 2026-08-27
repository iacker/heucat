import AppKit
import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var model: AppModel
    var autoRefresh = true

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Theme.hairline).frame(width: 0.7)
            VStack(spacing: 0) {
                titleBar
                Rectangle().fill(Theme.hairline).frame(height: 0.7)
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
                Rectangle().fill(Theme.hairline).frame(height: 0.7)
                footer
            }
        }
        .background(MarbleBackground())
        .frame(minWidth: 1060, minHeight: 700)
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

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(spacing: 9) {
                Crest(size: 74)
                Text("HEUCAT KEYCHAIN")
                    .font(Theme.serif(11, weight: .medium))
                    .tracking(2.2)
                    .foregroundStyle(Theme.ink)
                Text("MMXXVI")
                    .font(Theme.caption(8))
                    .tracking(3)
                    .foregroundStyle(Theme.inkFaint)
                Ornament(width: 92)
                    .padding(.top, 3)
            }
            .padding(.top, 30)
            .padding(.bottom, 26)

            VStack(spacing: 3) {
                ForEach(AppSection.allCases) { section in
                    navItem(section)
                }
            }
            .padding(.horizontal, 13)

            Spacer()

            VStack(alignment: .leading, spacing: 9) {
                Ornament(width: 168)
                HStack(spacing: 9) {
                    Image(systemName: model.status.sourceEnabled ? "lock.fill" : "lock.open.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(model.status.sourceEnabled ? Theme.lapis : Theme.amber)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.status.sourceEnabled ? "All systems secure" : "Needs attention")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Text(model.lastUpdatedCaption)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.inkFaint)
                    }
                    Spacer()
                }
                Capsule()
                    .fill(Theme.hairline)
                    .frame(height: 2.5)
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            Capsule()
                                .fill(LinearGradient(colors: [Theme.lapis, Theme.lapisSoft],
                                                     startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * model.healthFraction)
                        }
                    }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 22)
        }
        .frame(width: 214)
        .background(Color.white.opacity(0.55))
    }

    private func navItem(_ section: AppSection) -> some View {
        let selected = (model.selectedSection ?? .overview) == section
        return Button {
            model.selectedSection = section
        } label: {
            HStack(spacing: 11) {
                Image(systemName: section.icon)
                    .font(.system(size: 13))
                    .frame(width: 17)
                    .foregroundStyle(selected ? Theme.lapis : Theme.inkSoft)
                Text(section.rawValue)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.ink : Theme.inkSoft)
                Spacer()
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? Color.white : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(selected ? Theme.hairline : .clear, lineWidth: 0.7)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Chrome

    private var titleBar: some View {
        HStack(spacing: 14) {
            Text("HEUCAT Keychain")
                .font(Theme.serif(15, weight: .medium))
                .foregroundStyle(Theme.ink)
            Spacer()
            if model.isBusy {
                ProgressView().controlSize(.small)
            }
            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Theme.card))
                    .overlay(Circle().stroke(Theme.hairline, lineWidth: 0.7))
            }
            .buttonStyle(.plain)
            .disabled(model.isBusy)
            .help("Refresh protection status")

            HStack(spacing: 9) {
                Crest(size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Hermes Agent")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(model.profileName)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.inkFaint)
                }
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 15)
    }

    private var footer: some View {
        HStack(spacing: 11) {
            Spacer()
            Ornament(width: 74)
            Image(systemName: "lock.fill")
                .font(.system(size: 9))
                .foregroundStyle(Theme.inkFaint)
            Text("Hardware-backed. Values never leave this Mac.")
                .font(Theme.serif(11))
                .foregroundStyle(Theme.inkSoft)
            Ornament(width: 74)
            Spacer()
        }
        .padding(.vertical, 11)
    }
}

// MARK: - Overview

struct OverviewView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 20) {
                    hero
                    HStack(alignment: .top, spacing: 16) {
                        keyOverview
                        modeBreakdown
                    }
                }
                rail
                    .frame(width: 268)
            }
            .padding(26)
        }
    }

    private var hero: some View {
        Plate(padding: 0) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(text: "Runtime secret source")
                    Text("HEUCAT")
                        .font(Theme.display(46, weight: .regular))
                        .foregroundStyle(Theme.ink)
                        .tracking(1.5)
                        .fixedSize()
                        .padding(.top, 12)
                    Text("KEYCHAIN")
                        .font(Theme.display(46, weight: .regular))
                        .foregroundStyle(Theme.lapis)
                        .tracking(1.5)
                        .fixedSize()
                    Text("Between worlds,\nshe keeps the keys.")
                        .font(Theme.serif(15))
                        .foregroundStyle(Theme.inkSoft)
                        .lineSpacing(4)
                        .fixedSize()
                        .padding(.top, 16)
                    Ornament(width: 132)
                        .padding(.top, 18)
                    HStack(spacing: 11) {
                        Button {
                            model.selectedSection = .secrets
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "lock.fill").font(.system(size: 11))
                                Text("View secrets")
                                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                            }
                        }
                        .buttonStyle(LapisButtonStyle())

                        Button {
                            model.showingAddSecret = true
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                                Text("Add secret")
                            }
                        }
                        .buttonStyle(QuietButtonStyle())
                    }
                    .padding(.top, 22)
                }
                .padding(30)
                .frame(minWidth: 380, alignment: .leading)
                .layoutPriority(1)

                Spacer(minLength: 0)

                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .stroke(Theme.lapis.opacity(0.07), lineWidth: 0.6)
                            .frame(width: 138 + CGFloat(i) * 42)
                    }
                    ForEach(0..<48, id: \.self) { i in
                        Rectangle()
                            .fill(Theme.lapis.opacity(0.13))
                            .frame(width: 0.7, height: 26)
                            .offset(y: -102)
                            .rotationEffect(.degrees(Double(i) * 7.5))
                    }
                    Image(systemName: "key.fill")
                        .font(.system(size: 62, weight: .ultraLight))
                        .foregroundStyle(
                            LinearGradient(colors: [Theme.ink.opacity(0.75), Theme.inkFaint],
                                           startPoint: .top, endPoint: .bottom)
                        )
                    VStack(spacing: 3) {
                        Ornament(width: 58, tint: Theme.lapis)
                        Text("VERIFIED BY")
                            .font(Theme.caption(7)).tracking(1.8)
                            .foregroundStyle(Theme.lapis.opacity(0.75))
                        Text("HERMES AGENT")
                            .font(Theme.serif(9, weight: .semibold)).tracking(1.4)
                            .foregroundStyle(Theme.lapis)
                        Text("MMXXVI")
                            .font(Theme.caption(7)).tracking(2.2)
                            .foregroundStyle(Theme.lapis.opacity(0.65))
                    }
                    .offset(y: 118)
                }
                .frame(width: 300, height: 316)
                .padding(.trailing, 26)
            }
        }
    }

    private var keyOverview: some View {
        TitledPlate("Key overview") {
            HStack(alignment: .center, spacing: 22) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(model.status.configuredCount)")
                        .font(Theme.display(44, weight: .regular))
                        .foregroundStyle(Theme.ink)
                    Eyebrow(text: "Total keys")
                }
                Rectangle().fill(Theme.hairline).frame(width: 0.7, height: 58)
                VStack(alignment: .leading, spacing: 9) {
                    countRow("key.fill", "Keychain", model.plainCount, Theme.lapis)
                    countRow("cpu", "Enclave", model.enclaveCount, Theme.verdigris)
                    countRow("lock.open.fill", "Readable", model.readableCount, Theme.inkSoft)
                }
                Spacer()
            }
        }
    }

    private func countRow(_ icon: String, _ label: String, _ value: Int, _ tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 10)).foregroundStyle(tint).frame(width: 13)
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.inkSoft).fixedSize()
            Spacer(minLength: 14)
            Text("\(value)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.lapis)
        }
    }

    private var modeBreakdown: some View {
        TitledPlate("Recent secrets") {
            if model.status.secrets.isEmpty {
                EmptySecretsView(compact: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.status.secrets.prefix(4).enumerated()), id: \.element.id) { index, secret in
                        if index > 0 {
                            Rectangle().fill(Theme.hairline).frame(height: 0.7).padding(.vertical, 8)
                        }
                        HStack(spacing: 9) {
                            Image(systemName: secret.mode == "enclave" ? "cpu" : "key.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(secret.mode == "enclave" ? Theme.verdigris : Theme.lapis)
                                .frame(width: 14)
                            Text(secret.name)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            Spacer(minLength: 10)
                            Text(secret.isUnlocked ? "readable" : secret.state)
                                .font(.system(size: 10))
                                .foregroundStyle(secret.isUnlocked ? Theme.verdigris : Theme.amber)
                        }
                    }
                }
            }
        }
    }

    private var rail: some View {
        VStack(spacing: 16) {
            Plate {
                VStack(spacing: 11) {
                    Text("Agent status")
                        .font(Theme.serif(15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ZStack {
                        Image(systemName: "shield")
                            .font(.system(size: 54, weight: .ultraLight))
                            .foregroundStyle(model.status.sourceEnabled ? Theme.lapis : Theme.amber)
                        Image(systemName: "key.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(model.status.sourceEnabled ? Theme.lapis : Theme.amber)
                            .offset(y: -2)
                    }
                    .padding(.top, 3)
                    Eyebrow(text: model.status.sourceEnabled ? "Protected" : "Attention",
                            tint: model.status.sourceEnabled ? Theme.lapis : Theme.amber)
                    Text(model.statusHeadline)
                        .font(Theme.serif(12))
                        .foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Ornament(width: 76).padding(.top, 2)
                }
                .frame(maxWidth: .infinity)
            }

            TitledPlate(title: "Enclave sessions") {
                VStack(spacing: 10) {
                    sessionRow(
                        icon: "cpu",
                        title: "Secure Enclave",
                        detail: model.status.enclaveKeyPresent ? "Key present on this Mac" : "No key generated",
                        active: model.status.enclaveKeyPresent
                    )
                    Rectangle().fill(Theme.hairline).frame(height: 0.7)
                    sessionRow(
                        icon: "touchid",
                        title: "Unlocked secrets",
                        detail: model.enclaveCount == 0 ? "No enclave secrets stored" : "\(model.readableEnclaveCount) of \(model.enclaveCount) readable",
                        active: model.enclaveCount > 0 && model.readableEnclaveCount > 0
                    )
                    Button {
                        model.selectedSection = .sessions
                    } label: {
                        HStack {
                            Text("Manage sessions")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.inkSoft)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.inkFaint)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            } accessory: {
                Text("\(model.enclaveCount)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.lapis)
            }

            TitledPlate("Vault health") {
                VStack(spacing: 11) {
                    HealthRing(value: model.healthFraction, label: model.healthLabel)
                        .padding(.vertical, 4)
                    Text(model.healthCaption)
                        .font(Theme.serif(12))
                        .foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func sessionRow(icon: String, title: String, detail: String, active: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Theme.lapis)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.lapis.opacity(0.07)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.ink)
                Text(detail).font(.system(size: 10)).foregroundStyle(Theme.inkFaint)
            }
            Spacer(minLength: 6)
            HStack(spacing: 4) {
                Circle().fill(active ? Theme.verdigris : Theme.inkFaint).frame(width: 5, height: 5)
                Text(active ? "Active" : "Idle")
                    .font(.system(size: 10))
                    .foregroundStyle(active ? Theme.verdigris : Theme.inkFaint)
            }
        }
    }
}

// MARK: - Secrets

struct SecretsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""

    private var filtered: [SecretStatus] {
        query.isEmpty ? model.status.secrets
                      : model.status.secrets.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageHeader("Secrets", "References are managed here. Values are never revealed.")
            HStack(spacing: 11) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkFaint)
                    TextField("Search", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Theme.hairline, lineWidth: 0.7))
                .frame(maxWidth: 290)

                Spacer()
                Button {
                    model.showingAddSecret = true
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                        Text("Add secret")
                    }
                }
                .buttonStyle(LapisButtonStyle())
                .disabled(model.isBusy)
            }
            if filtered.isEmpty {
                EmptySecretsView(compact: false).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(filtered) { SecretRow(secret: $0, showActions: true) }
                    }
                }
            }
        }
        .padding(30)
    }
}

// MARK: - Sessions

struct SessionsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            pageHeader("Sessions", "Temporary access to Secure Enclave secrets.")
            Plate {
                HStack(spacing: 22) {
                    ZStack {
                        Circle().stroke(Theme.lapis.opacity(0.14), lineWidth: 0.7).frame(width: 88, height: 88)
                        Image(systemName: "touchid")
                            .font(.system(size: 40, weight: .ultraLight))
                            .foregroundStyle(Theme.lapis)
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Authenticate once, work securely")
                            .font(Theme.serif(19, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Text("Touch ID opens a time-limited session covering every Enclave secret at once. Hermes startup stays silent, so gateway and cron processes never block on a prompt.")
                            .font(Theme.serif(13))
                            .foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
            }
            HStack(spacing: 11) {
                Button {
                    Task { await model.unlock() }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "touchid").font(.system(size: 12))
                        Text("Unlock with Touch ID")
                    }
                }
                .buttonStyle(LapisButtonStyle())
                .disabled(model.isBusy || model.enclaveCount == 0)

                Button {
                    Task { await model.lock() }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "lock.fill").font(.system(size: 11))
                        Text("Lock all sessions")
                    }
                }
                .buttonStyle(QuietButtonStyle())
                .disabled(model.isBusy || model.enclaveCount == 0)
            }
            if model.enclaveCount == 0 {
                Label("No Enclave secrets are stored yet, so there is nothing to unlock. Add one from the Secrets page and pick Secure Enclave.",
                      systemImage: "info.circle")
                    .font(Theme.serif(12))
                    .foregroundStyle(Theme.inkSoft)
            }
            Ornament(width: 200)
            Text("While a session is open the values sit in TTL-bounded macOS Keychain records, readable by processes running as you. Lock them when you are done rather than relying on the timeout.")
                .font(Theme.serif(12))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 560, alignment: .leading)
            Spacer()
        }
        .padding(30)
    }
}

// MARK: - Sealed profiles

struct SealedProfilesView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            pageHeader("Sealed profiles", "Hardware-gated protection for a whole Hermes profile.")
            Plate {
                HStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .stroke((model.chthoniosAvailable ? Theme.lapis : Theme.amber).opacity(0.16), lineWidth: 0.7)
                            .frame(width: 84, height: 84)
                        Image(systemName: "externaldrive.badge.lock")
                            .font(.system(size: 34, weight: .ultraLight))
                            .foregroundStyle(model.chthoniosAvailable ? Theme.lapis : Theme.amber)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Chthonios")
                            .font(Theme.serif(19, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Text(model.chthoniosSummary)
                            .font(Theme.serif(13))
                            .foregroundStyle(Theme.inkSoft)
                        HStack(spacing: 5) {
                            Circle()
                                .fill(model.chthoniosAvailable ? Theme.verdigris : Theme.amber)
                                .frame(width: 5, height: 5)
                            Text(model.chthoniosAvailable ? "Engine available" : "Engine unavailable")
                                .font(.system(size: 11))
                                .foregroundStyle(model.chthoniosAvailable ? Theme.verdigris : Theme.amber)
                        }
                    }
                    Spacer()
                    Button("Refresh") { Task { await model.refreshChthonios() } }
                        .buttonStyle(QuietButtonStyle())
                }
            }
            TitledPlate("Security boundary") {
                VStack(alignment: .leading, spacing: 12) {
                    boundaryRow("cpu", "Secure Enclave protects individual secrets while Hermes runs.")
                    Rectangle().fill(Theme.hairline).frame(height: 0.7)
                    boundaryRow("archivebox.fill", "Chthonios seals a whole profile so it is unusable at rest.")
                    Rectangle().fill(Theme.hairline).frame(height: 0.7)
                    boundaryRow("key.horizontal.fill", "YubiKey unsealing needs the physical key, its PIN and a touch.")
                }
            }
            Text("The two crypto engines stay separate on purpose. Only this dashboard is shared, so neither system has to pretend to be the other. Unsealing is done by you in a terminal, never by this app.")
                .font(Theme.serif(12))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 620, alignment: .leading)
            Spacer()
        }
        .padding(30)
    }

    private func boundaryRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Theme.lapis)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.lapis.opacity(0.07)))
            Text(text).font(Theme.serif(13)).foregroundStyle(Theme.inkSoft)
            Spacer()
        }
    }
}

// MARK: - Diagnostics

struct DiagnosticsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            pageHeader("Diagnostics", "Local paths and runtime health. No secret values appear here.")
            TitledPlate("Runtime") {
                VStack(spacing: 0) {
                    diagRow("Hermes CLI", model.hermesBinary)
                    diagDivider
                    diagRow("Profile home", model.hermesHome)
                    diagDivider
                    diagRow("Helper binary", model.status.helperPath)
                    diagDivider
                    diagRow("Secure Enclave key", model.status.enclaveKeyPresent ? "Present" : "Missing")
                    diagDivider
                    diagRow("Last status", model.message)
                }
            }
            HStack(spacing: 11) {
                Button("Open keychain folder") { model.openKeychainFolder() }
                    .buttonStyle(QuietButtonStyle())
                SettingsLink { Text("Settings") }
                    .buttonStyle(QuietButtonStyle())
                Button("View source") { model.openRepository() }
                    .buttonStyle(QuietButtonStyle())
            }
            Spacer()
        }
        .padding(30)
    }

    private var diagDivider: some View {
        Rectangle().fill(Theme.hairline).frame(height: 0.7).padding(.vertical, 9)
    }

    private func diagRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkSoft)
                .frame(width: 150, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Shared rows

struct SecretRow: View {
    @EnvironmentObject private var model: AppModel
    let secret: SecretStatus
    var showActions = false

    var body: some View {
        Plate(padding: 14) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill((secret.mode == "enclave" ? Theme.verdigris : Theme.lapis).opacity(0.08))
                    Image(systemName: secret.mode == "enclave" ? "cpu" : "key.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(secret.mode == "enclave" ? Theme.verdigris : Theme.lapis)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text(secret.name)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                    Text(secret.mode == "enclave" ? "Secure Enclave" : "Apple Keychain")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.inkFaint)
                }
                Spacer(minLength: 12)

                HStack(spacing: 5) {
                    Circle()
                        .fill(secret.isUnlocked ? Theme.verdigris : Theme.amber)
                        .frame(width: 5, height: 5)
                    Text(secret.isUnlocked ? "Available" : secret.state.capitalized)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(secret.isUnlocked ? Theme.verdigris : Theme.amber)
                }

                if showActions {
                    Menu {
                        Button("Copy variable name", systemImage: "doc.on.doc") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(secret.name, forType: .string)
                            model.message = "Copied \(secret.name)"
                        }
                        Button("Update value…", systemImage: "arrow.triangle.2.circlepath") {
                            model.prefillName = secret.name
                            model.showingAddSecret = true
                        }
                        Divider()
                        Button("Remove", systemImage: "trash", role: .destructive) {
                            model.pendingDeletion = secret
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.inkFaint)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 24)
                }
            }
        }
    }
}

struct EmptySecretsView: View {
    @EnvironmentObject private var model: AppModel
    let compact: Bool

    var body: some View {
        VStack(spacing: 11) {
            Image(systemName: "key.horizontal")
                .font(.system(size: compact ? 24 : 38, weight: .ultraLight))
                .foregroundStyle(Theme.inkFaint)
            Text("No secrets yet")
                .font(Theme.serif(compact ? 14 : 18, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text("Add a credential and the plaintext copy stops being the source of truth.")
                .font(Theme.serif(12))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                model.showingAddSecret = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                    Text("Add secret")
                }
            }
            .buttonStyle(LapisButtonStyle())
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(compact ? 18 : 30)
        .background(Theme.paperDeep.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 0.8, dash: [4]))
                .foregroundStyle(Theme.hairline)
        )
    }
}

@ViewBuilder func pageHeader(_ title: String, _ subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
        Text(title)
            .font(Theme.display(30, weight: .regular))
            .foregroundStyle(Theme.ink)
        Text(subtitle)
            .font(Theme.serif(13))
            .foregroundStyle(Theme.inkSoft)
        Ornament(width: 118).padding(.top, 3)
    }
}
