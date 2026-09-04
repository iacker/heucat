import AppKit
import SwiftUI

/// ImageRenderer measures an offscreen ScrollView as empty, so snapshots would
/// come out blank. Set once at capture time instead of threading a parameter
/// through every view.
let snapshotMode = ProcessInfo.processInfo.environment["HERMES_UI_CAPTURE_PATH"] != nil

struct MainWindowView: View {
    @EnvironmentObject private var model: AppModel
    /// Observing Loc makes the whole window redraw the moment the language
    /// changes, which is what makes the picker feel instant.
    @ObservedObject private var loc = Loc.shared
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
                    case .howitworks: HowItWorksView()
                    case .tutorial: TutorialView()
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
        .sheet(isPresented: $model.showingAddSecret, onDismiss: {
            model.prefillName = ""
            model.prefillEnclave = true
        }) { AddSecretView() }
        .alert(L("secrets.confirmRemove"), isPresented: Binding(
            get: { model.pendingDeletion != nil },
            set: { if !$0 { model.pendingDeletion = nil } }
        ), presenting: model.pendingDeletion) { secret in
            Button(L("secrets.cancel"), role: .cancel) { model.pendingDeletion = nil }
            Button(L("secrets.remove"), role: .destructive) {
                model.pendingDeletion = nil
                Task { await model.delete(secret) }
            }
        } message: { secret in
            Text(secret.name + L("secrets.removeWarning"))
        }
        .task { if autoRefresh { await model.refresh() } }
        // The session countdown would otherwise sit frozen at whatever it read
        // on open. Refreshing on focus keeps it honest without a polling timer.
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            if autoRefresh { Task { await model.refresh() } }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(spacing: 9) {
                Crest(size: 74)
                Text(L("app.wordmark"))
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
                        Text(model.status.sourceEnabled ? L("app.allSecure") : L("app.needsAttention"))
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
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.cream)
                .shadow(color: Theme.marbleShadow.opacity(0.16), radius: 22, x: 4, y: 6)
        )
        .padding(.vertical, 12)
        .padding(.leading, 12)
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
                    .foregroundStyle(selected ? Color.white : Theme.inkSoft)
                Text(section.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.white : Theme.inkSoft)
                Spacer()
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected
                          ? AnyShapeStyle(LinearGradient(colors: [Theme.lapis, Theme.lapisSoft],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                          : AnyShapeStyle(Color.clear))
                    .shadow(color: selected ? Theme.lapis.opacity(0.34) : .clear, radius: 7, y: 3)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Chrome

    private var titleBar: some View {
        HStack(spacing: 14) {
            Text(L("app.title"))
                .font(Theme.serif(15, weight: .medium))
                .foregroundStyle(Theme.ink)
            Spacer()
            if model.isBusy {
                ProgressView().controlSize(.small)
            }
            Button {
                loc.language = loc.language == .french ? .english : .french
            } label: {
                Text(loc.language == .french ? "FR" : "EN")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.lapis)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Theme.card))
                    .overlay(Circle().stroke(Theme.hairline, lineWidth: 0.7))
            }
            .buttonStyle(.plain)
            .help(L("settings.language"))

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
            .help(L("app.refresh.help"))

            HStack(spacing: 9) {
                Crest(size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(L("app.agent"))
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
            Text(L("overview.hardwareBacked"))
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
        Group {
            if snapshotMode { content } else { ScrollView { content } }
        }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 20) {
                hero
                statTiles
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

    private var hero: some View {
        Plate(padding: 0) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(text: L("overview.eyebrow"))
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
                    Text(L("overview.motto"))
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
                                Text(L("overview.viewSecrets"))
                                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                            }
                        }
                        .buttonStyle(LapisButtonStyle())

                        Button {
                            model.showingAddSecret = true
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                                Text(L("overview.addSecret"))
                            }
                        }
                        .buttonStyle(QuietButtonStyle())
                    }
                    .padding(.top, 22)
                }
                .padding(30)
                .frame(minWidth: 340, alignment: .leading)
                .layoutPriority(1)

                Spacer(minLength: 12)

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
                .frame(width: 268, height: 300)
                .padding(.trailing, 20)
            }
        }
    }

    /// Four counters across the top. Every number comes from parsed CLI status;
    /// the captions state what the number means rather than a fake trend.
    private var statTiles: some View {
        HStack(spacing: 16) {
            StatTile(icon: "key.fill",
                     value: "\(model.status.configuredCount)",
                     label: L("stat.secrets"),
                     caption: L("stat.secrets.caption"))
            StatTile(icon: "cpu",
                     value: "\(model.enclaveCount)",
                     label: L("stat.enclave"),
                     caption: L("stat.enclave.caption"),
                     tint: Theme.verdigris)
            StatTile(icon: "lock.open.fill",
                     value: "\(model.readableCount)",
                     label: L("stat.readable"),
                     caption: L(model.readableCount == 0 ? "stat.readable.closed" : "stat.readable.open"),
                     tint: model.readableCount == 0 ? Theme.amber : Theme.verdigris)
            StatTile(icon: "checkmark.shield.fill",
                     value: model.healthLabel,
                     label: L("stat.health"),
                     caption: L(model.status.sourceEnabled ? "stat.health.on" : "stat.health.off"))
        }
    }

    private var keyOverview: some View {
        TitledPlate(L("overview.keyOverview")) {
            HStack(alignment: .center, spacing: 22) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(model.status.configuredCount)")
                        .font(Theme.display(44, weight: .regular))
                        .foregroundStyle(Theme.ink)
                    Eyebrow(text: L("overview.totalKeys"))
                }
                Rectangle().fill(Theme.hairline).frame(width: 0.7, height: 58)
                VStack(alignment: .leading, spacing: 9) {
                    countRow("key.fill", L("overview.keychain"), model.plainCount, Theme.lapis)
                    countRow("cpu", L("overview.enclave"), model.enclaveCount, Theme.verdigris)
                    countRow("lock.open.fill", L("overview.readable"), model.readableCount, Theme.inkSoft)
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
        TitledPlate(L("overview.recentSecrets")) {
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
                            Text(secret.isUnlocked ? L("state.readable") : LState(secret.state))
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
                    Text(L("overview.agentStatus"))
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
                    Eyebrow(text: L(model.status.sourceEnabled ? "overview.protected" : "overview.exposed"),
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

            TitledPlate(title: L("overview.enclaveSessions")) {
                VStack(spacing: 10) {
                    sessionRow(
                        icon: "cpu",
                        title: L("secrets.modeEnclave"),
                        detail: L(model.status.enclaveKeyPresent ? "overview.keyPresent" : "overview.noKey"),
                        active: model.status.enclaveKeyPresent
                    )
                    Rectangle().fill(Theme.hairline).frame(height: 0.7)
                    sessionRow(
                        icon: "touchid",
                        title: L("overview.unlockedSecrets"),
                        detail: model.enclaveCount == 0 ? L("sessions.none") : L("overview.nReadable", model.readableEnclaveCount, model.enclaveCount),
                        active: model.enclaveCount > 0 && model.readableEnclaveCount > 0
                    )
                    Button {
                        model.selectedSection = .sessions
                    } label: {
                        HStack {
                            Text(L("overview.manageSessions"))
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

            TitledPlate(L("overview.vaultHealth")) {
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
                Text(L(active ? "overview.active" : "overview.idle"))
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
            pageHeader(L("secrets.title"), L("secrets.subtitle"))
            HStack(spacing: 11) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkFaint)
                    TextField(L("secrets.search"), text: $query)
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
                    Task { await model.testAll() }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "bolt.horizontal").font(.system(size: 11))
                        Text(L(model.isTestingAll ? "secrets.testing" : "secrets.testAll"))
                    }
                }
                .buttonStyle(QuietButtonStyle())
                .disabled(model.isTestingAll || model.status.secrets.isEmpty)

                Button {
                    model.showingAddSecret = true
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                        Text(L("overview.addSecret"))
                    }
                }
                .buttonStyle(LapisButtonStyle())
                .disabled(model.isBusy)
            }

            // Only shown when there is something to act on: a plain secret is
            // readable by anything running as you, and the fix is one click.
            if model.plainCount > 0 {
                migrateBanner
            }
            if filtered.isEmpty {
                EmptySecretsView(compact: false).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if snapshotMode {
                VStack(spacing: 9) {
                    ForEach(filtered) { SecretRow(secret: $0, showActions: true) }
                }
                Spacer(minLength: 0)
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

    /// Amber, not red: a plain secret is a weaker default, not a breach.
    private var migrateBanner: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "exclamationmark.shield")
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(Theme.amber)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.plainCount == 1 ? L("migrate.banner1") : L("migrate.banner", model.plainCount))
                    .font(Theme.serif(14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(L("migrate.bannerBody"))
                    .font(Theme.serif(12))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            Button {
                Task { await model.migrateAllPlain() }
            } label: {
                Text(L(model.isBusy ? "migrate.busy" : "migrate.action"))
            }
            .buttonStyle(LapisButtonStyle())
            .disabled(model.isBusy)
        }
        .padding(15)
        .background(Theme.amber.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.amber.opacity(0.3), lineWidth: 0.8)
        )
    }
}

// MARK: - Sessions

struct SessionsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            pageHeader(L("sessions.title"), L("sessions.subtitle"))
            Plate {
                HStack(spacing: 22) {
                    ZStack {
                        Circle().stroke(Theme.lapis.opacity(0.14), lineWidth: 0.7).frame(width: 88, height: 88)
                        Image(systemName: "touchid")
                            .font(.system(size: 40, weight: .ultraLight))
                            .foregroundStyle(Theme.lapis)
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        Text(L("sessions.headline"))
                            .font(Theme.serif(19, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Text(L("sessions.body"))
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
                        Text(L("sessions.unlock"))
                    }
                }
                .buttonStyle(LapisButtonStyle())
                .disabled(model.isBusy || model.enclaveCount == 0)

                Button {
                    Task { await model.lock() }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "lock.fill").font(.system(size: 11))
                        Text(L("sessions.lockAll"))
                    }
                }
                .buttonStyle(QuietButtonStyle())
                .disabled(model.isBusy || model.enclaveCount == 0)
            }
            if model.enclaveCount == 0 {
                Label(L("sessions.none"),
                      systemImage: "info.circle")
                    .font(Theme.serif(12))
                    .foregroundStyle(Theme.inkSoft)
            }
            Ornament(width: 200)
            Text(L("sessions.tradeoff"))
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
    @ObservedObject private var loc = Loc.shared
    @State private var sheet: SheetRequest?

    /// Identifiable wrapper so `.sheet(item:)` carries both row and action.
    struct SheetRequest: Identifiable {
        let profile: ProfileStatus
        let action: ProfileSecretSheet.Action
        var id: String { profile.name + String(describing: action) }
    }

    var body: some View {
        // A ScrollView renders nothing in the offscreen snapshot path, so
        // captures of this page came out blank. Same escape hatch as Overview.
        Group {
            if snapshotMode { content } else { ScrollView { content } }
        }
        .sheet(item: $sheet) { request in
            ProfileSecretSheet(profile: request.profile, action: request.action)
                .environmentObject(model)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            pageHeader(L("profiles.title"), L("profiles.subtitle2"))
            // The dashboard, not a description of the engine: how many profiles
            // are sealed, which one this app is driving, and whether chthonios
            // can actually run. The engine's own name belongs in the footer.
            Plate {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 0) {
                        tally(model.sealedCount, L("profiles.tallySealed"),
                              "lock.fill", Theme.verdigris)
                        tallyDivider
                        tally(model.openCount, L("profiles.tallyOpen"),
                              "lock.open.fill", Theme.amber)
                        tallyDivider
                        tally(model.unmanagedCount, L("profiles.tallyUnmanaged"),
                              "circle.dashed", Theme.inkFaint)
                        Spacer(minLength: 12)
                        Button(L("app.refresh")) { Task { await model.refreshChthonios() } }
                            .buttonStyle(QuietButtonStyle())
                    }
                    Rectangle().fill(Theme.hairline).frame(height: 0.7)
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.lapis)
                        Text(L("profiles.activeIs"))
                            .font(Theme.serif(12))
                            .foregroundStyle(Theme.inkSoft)
                        Text(model.activeProfile)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Circle()
                            .fill(model.chthoniosAvailable ? Theme.verdigris : Theme.amber)
                            .frame(width: 5, height: 5)
                        Text(model.chthoniosAvailable ? L("profiles.engineOn")
                                                      : L("profiles.engineOff"))
                            .font(.system(size: 11))
                            .foregroundStyle(model.chthoniosAvailable ? Theme.verdigris
                                                                      : Theme.amber)
                    }
                }
            }

            if !model.profiles.isEmpty {
                TitledPlate(L("profiles.allProfiles")) {
                    VStack(spacing: 9) {
                        ForEach(model.profiles) { profile in
                            ProfileRow(profile: profile) { action in
                                sheet = SheetRequest(profile: profile, action: action)
                            }
                        }
                    }
                }
            }

            TitledPlate(L("profiles.boundary")) {
                VStack(alignment: .leading, spacing: 12) {
                    boundaryRow("cpu", L("profiles.boundary.enclave"))
                    Rectangle().fill(Theme.hairline).frame(height: 0.7)
                    boundaryRow("archivebox.fill", L("profiles.boundary.chthonios"))
                    Rectangle().fill(Theme.hairline).frame(height: 0.7)
                    boundaryRow("key.horizontal.fill", L("profiles.boundary.yubikey"))
                }
            }
            Text(L("profiles.separate"))
                .font(Theme.serif(12))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 620, alignment: .leading)
        }
        .padding(30)
    }

    private var tallyDivider: some View {
        Rectangle().fill(Theme.hairline).frame(width: 0.7, height: 34)
            .padding(.horizontal, 18)
    }

    /// One number and what it counts. Zero is shown greyed rather than hidden:
    /// "0 sealed" is the most important thing this page can say.
    private func tally(_ count: Int, _ label: String,
                       _ icon: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(count)")
                .font(Theme.serif(27, weight: .semibold))
                .foregroundStyle(count == 0 ? Theme.inkFaint : tint)
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundStyle(count == 0 ? Theme.inkFaint : tint)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(count) \(label)")
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

/// One profile: state, backend, and the actions that state allows.
struct ProfileRow: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var loc = Loc.shared
    let profile: ProfileStatus
    let onSecretNeeded: (ProfileSecretSheet.Action) -> Void

    private var tint: Color {
        switch profile.state {
        case .sealed: Theme.verdigris
        case .open: Theme.amber
        case .unmanaged: Theme.inkFaint
        }
    }
    private var icon: String {
        switch profile.state {
        case .sealed: "lock.fill"
        case .open: "lock.open.fill"
        case .unmanaged: "circle.dashed"
        }
    }
    private var stateLabel: String {
        switch profile.state {
        case .sealed: L("profiles.stateSealed")
        case .open: L("profiles.stateOpen")
        case .unmanaged: L("profiles.stateUnmanaged")
        }
    }

    var body: some View {
        Plate(padding: 14) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(tint.opacity(0.08))
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundStyle(tint)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(profile.name)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.ink)
                        if profile.name == model.activeProfile {
                            Text(L("profiles.active"))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Theme.lapis)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Theme.lapis.opacity(0.1), in: Capsule())
                        }
                        if profile.needsHardwareKey {
                            Image(systemName: "key.horizontal.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.amber)
                                .help(L("profiles.yubikeyBacked"))
                        }
                    }
                    HStack(spacing: 5) {
                        Text(stateLabel)
                            .font(.system(size: 10))
                            .foregroundStyle(tint)
                        if !profile.backend.isEmpty {
                            Text("· \(profile.backend)")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.inkFaint)
                        }
                        if !profile.sealedAt.isEmpty {
                            Text("· \(profile.sealedAt.prefix(10))")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.inkFaint)
                        }
                    }
                }
                Spacer(minLength: 12)

                HStack(spacing: 7) {
                    switch profile.state {
                    case .unmanaged:
                        Button(L("profiles.seal")) { onSecretNeeded(.seal) }
                            .buttonStyle(QuietButtonStyle())
                            .accessibilityLabel("\(L("profiles.seal")) \(profile.name)")
                    case .sealed:
                        Button(L("profiles.unseal")) { onSecretNeeded(.unseal) }
                            .buttonStyle(QuietButtonStyle())
                            .accessibilityLabel("\(L("profiles.unseal")) \(profile.name)")
                        Button(L("profiles.verify")) {
                            Task { await model.verifyProfile(profile) }
                        }
                        .buttonStyle(QuietButtonStyle())
                        .accessibilityLabel("\(L("profiles.verify")) \(profile.name)")
                    case .open:
                        Button(L("profiles.lock")) {
                            Task { await model.lockProfile(profile) }
                        }
                        .buttonStyle(QuietButtonStyle())
                        .accessibilityLabel("\(L("profiles.lock")) \(profile.name)")
                        Button(L("profiles.verify")) {
                            Task { await model.verifyProfile(profile) }
                        }
                        .buttonStyle(QuietButtonStyle())
                        .accessibilityLabel("\(L("profiles.verify")) \(profile.name)")
                    }
                }
                .disabled(model.isBusy)
            }
        }
    }
}

// MARK: - Diagnostics

struct DiagnosticsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            pageHeader(L("diag.title"), L("diag.subtitle2"))
            TitledPlate(L("diag.runtime")) {
                VStack(spacing: 0) {
                    diagRow(L("diag.hermesCli"), model.hermesBinary)
                    diagDivider
                    diagRow(L("diag.hermesHome"), model.hermesHome)
                    diagDivider
                    diagRow(L("diag.helper"), model.status.helperPath)
                    diagDivider
                    diagRow(L("diag.enclaveKey"), model.status.enclaveKeyPresent ? L("diag.present") : L("diag.missing"))
                    diagDivider
                    diagRow(L("diag.lastStatus"), model.message)
                }
            }
            HStack(spacing: 11) {
                Button(L("diag.openFolder")) { model.openKeychainFolder() }
                    .buttonStyle(QuietButtonStyle())
                SettingsLink { Text(L("app.settings")) }
                    .buttonStyle(QuietButtonStyle())
                Button(L("diag.viewSource")) { model.openRepository() }
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

// MARK: - How it works

struct HowItWorksView: View {
    @ObservedObject private var loc = Loc.shared

    private struct Stage: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let body: String
    }

    /// Built at render time so switching language re-reads the tables.
    private var stages: [Stage] {
        (1...4).map { i in
            Stage(icon: ["cpu", "lock.doc", "touchid", "bolt.horizontal"][i - 1],
                  title: L("how.\(i).title"),
                  body: L("how.\(i).body"))
        }
    }

    var body: some View {
        Group {
            if snapshotMode { stack } else { ScrollView { stack } }
        }
    }

    private var stack: some View {
            VStack(alignment: .leading, spacing: 20) {
                pageHeader(L("how.title"), L("how.subtitle"))
                ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
                    Plate {
                        HStack(alignment: .top, spacing: 16) {
                            ZStack {
                                Circle().fill(Theme.lapis.opacity(0.08)).frame(width: 46, height: 46)
                                Image(systemName: stage.icon)
                                    .font(.system(size: 18, weight: .light))
                                    .foregroundStyle(Theme.lapis)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Eyebrow(text: L("how.step") + " \(index + 1)")
                                Text(stage.title)
                                    .font(Theme.serif(17, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                                Text(stage.body)
                                    .font(Theme.serif(13))
                                    .foregroundStyle(Theme.inkSoft)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                Plate {
                    VStack(alignment: .leading, spacing: 7) {
                        Eyebrow(text: L("how.tradeoff.title"), tint: Theme.amber)
                        Text(L("how.tradeoff.body"))
                            .font(Theme.serif(13))
                            .foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Ornament(width: 200).frame(maxWidth: .infinity)
            }
            .padding(30)
    }
}

// MARK: - Shared rows

struct SecretRow: View {
    @EnvironmentObject private var model: AppModel
    let secret: SecretStatus
    var showActions = false

    private func pingColor(_ ping: String) -> Color {
        switch ping {
        case "ok": return Theme.verdigris
        case "dead": return Color.red
        case "…": return Theme.inkFaint
        default: return Theme.amber
        }
    }

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
                    Text(L(secret.mode == "enclave" ? "secrets.modeEnclave" : "secrets.modeKeychain"))
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.inkFaint)
                }
                Spacer(minLength: 12)

                if let ping = model.pingResults[secret.name] {
                    Text(ping)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(pingColor(ping))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(pingColor(ping).opacity(0.1), in: Capsule())
                }

                HStack(spacing: 5) {
                    Circle()
                        .fill(secret.isUnlocked ? Theme.verdigris : Theme.amber)
                        .frame(width: 5, height: 5)
                    Text(secret.isUnlocked ? L("secrets.available") : LState(secret.state).capitalized)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(secret.isUnlocked ? Theme.verdigris : Theme.amber)
                }

                if showActions {
                    // Unlock lives on the row that shows the problem, not three
                    // clicks away in Sessions.
                    if secret.mode == "enclave" && !secret.isUnlocked {
                        Button {
                            Task { await model.unlock() }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "touchid").font(.system(size: 11))
                                Text(L("secrets.unlockRow"))
                            }
                        }
                        .buttonStyle(QuietButtonStyle())
                        .disabled(model.isBusy)
                        .help(L("secrets.unlockRowHelp"))
                    }

                    Menu {
                        Button(L("secrets.copyName"), systemImage: "doc.on.doc") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(secret.name, forType: .string)
                            model.message = L("msg.copied") + " \(secret.name)"
                        }
                        Button(L("secrets.updateValue"), systemImage: "arrow.triangle.2.circlepath") {
                            model.prefillName = secret.name
                            model.prefillEnclave = secret.mode == "enclave"
                            model.showingAddSecret = true
                        }
                        if secret.mode == "plain" {
                            Button(L("secrets.migrate"), systemImage: "cpu") {
                                Task { await model.migrateToEnclave(secret) }
                            }
                        }
                        Button(L("secrets.test"), systemImage: "bolt.horizontal") {
                            Task { await model.testSecret(secret) }
                        }
                        Divider()
                        Button(L("secrets.remove"), systemImage: "trash", role: .destructive) {
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
            Text(L("secrets.empty.title"))
                .font(Theme.serif(compact ? 14 : 18, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text(L("secrets.empty.body"))
                .font(Theme.serif(12))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                model.showingAddSecret = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                    Text(L("overview.addSecret"))
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
