import AppKit
import SwiftUI

// MARK: - Look

enum Look {
    static let accent = Color(red: 0.55, green: 0.48, blue: 1.0)
    static let ok = Color(red: 0.25, green: 0.82, blue: 0.6)
    static let warn = Color(red: 0.98, green: 0.74, blue: 0.3)
    static let bad = Color(red: 0.98, green: 0.45, blue: 0.5)
    static let seal = Color(red: 0.72, green: 0.55, blue: 1.0)
    static let gradient = LinearGradient(colors: [accent, Color(red: 0.35, green: 0.8, blue: 0.95)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.08)))
    }
}

struct Chip: View {
    let text: String, color: Color
    var body: some View {
        Text(text).font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .foregroundStyle(color)
            .background(Capsule().fill(color.opacity(0.15)))
    }
}

struct Pill: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(prominent ? .white : .primary)
            .background(Capsule().fill(prominent ? AnyShapeStyle(Look.gradient) : AnyShapeStyle(.white.opacity(0.08))))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct Empty: View {
    let icon: String, text: String
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 22)).foregroundStyle(.tertiary)
            Text(text).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 24)
    }
}

/// Inline passphrase / PIN entry, so nothing ever opens a sheet over the popover.
struct SecretForm: View {
    let title: String
    var confirm = false
    var pin = false
    let go: (String) -> Void
    let cancel: () -> Void
    @State private var a = ""
    @State private var b = ""
    private var valid: Bool { pin ? !a.isEmpty : (a.count >= 8 && (!confirm || a == b)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            SecureField(pin ? "PIN de la YubiKey" : "Phrase secrète (8+ caractères)", text: $a)
            if confirm && !pin { SecureField("Confirmer", text: $b) }
            HStack {
                if confirm && !pin && !b.isEmpty && a != b { Text("Différentes").font(.system(size: 10)).foregroundStyle(Look.bad) }
                Spacer()
                Button("Annuler", action: cancel).buttonStyle(Pill())
                Button("Valider") { go(a) }.buttonStyle(Pill(prominent: true)).disabled(!valid)
            }
        }.textFieldStyle(.roundedBorder).padding(.top, 4)
    }
}

// MARK: - Root

struct RootView: View {
    @EnvironmentObject var m: Model
    @Namespace private var tabs

    var body: some View {
        VStack(spacing: 12) {
            header
            tabBar
            ScrollView {
                VStack(spacing: 8) {
                    switch m.tab {
                    case .keys: KeysTab()
                    case .profiles: ProfilesTab()
                    case .vaults: VaultsTab()
                    }
                }.padding(.bottom, 6)
            }.scrollIndicators(.never)
            footer
        }
        .padding(14)
        .frame(width: 390, height: 540)
        .disabled(m.busy != nil)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(Look.gradient).frame(width: 32, height: 32)
                Image(systemName: "lock.shield.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("HEUCAT").font(.system(size: 15, weight: .bold)).tracking(1.5)
                Text("Clés, profils et coffres chiffrés").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { Task { await m.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Rafraîchir")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Quitter")
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(Model.Tab.allCases, id: \.self) { t in
                Button {
                    withAnimation(.snappy(duration: 0.25)) { m.tab = t }
                } label: {
                    Text(t.rawValue).font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .foregroundStyle(m.tab == t ? .white : .secondary)
                        .background {
                            if m.tab == t {
                                Capsule().fill(Look.gradient).matchedGeometryEffect(id: "tab", in: tabs)
                            }
                        }
                        .contentShape(Capsule())
                }.buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(.white.opacity(0.06)))
    }

    @ViewBuilder private var footer: some View {
        HStack(spacing: 6) {
            if let busy = m.busy {
                ProgressView().controlSize(.small)
                Text(busy).foregroundStyle(.secondary)
            } else if let n = m.note {
                Image(systemName: n.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(n.ok ? Look.ok : Look.bad)
                Text(n.text).lineLimit(2).foregroundStyle(.secondary)
            } else {
                Text("Les secrets passent par stdin, jamais par la ligne de commande.").foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }.font(.system(size: 10)).frame(minHeight: 18)
    }
}

// MARK: - Keys

struct KeysTab: View {
    @EnvironmentObject var m: Model
    @State private var adding = false
    @State private var name = ""
    @State private var value = ""
    @State private var enclave = true
    @State private var doomed: String?

    var body: some View {
        HStack {
            Picker("", selection: $m.keyProfile) {
                ForEach(m.hermesProfiles, id: \.self) { Text($0).tag($0) }
            }.labelsHidden().frame(width: 120)
            Spacer()
            Button { Task { await m.unlockKeys() } } label: { Label("Déverrouiller", systemImage: "touchid") }
                .buttonStyle(Pill(prominent: true))
            Button { Task { await m.lockKeys() } } label: { Image(systemName: "lock.fill") }
                .buttonStyle(Pill()).help("Verrouiller maintenant")
        }

        if m.secrets.isEmpty {
            Empty(icon: "key.horizontal", text: "Aucune clé dans le trousseau pour ce profil.")
        }
        ForEach(m.secrets) { s in
            Card {
                HStack(spacing: 10) {
                    Image(systemName: s.enclave ? "touchid" : "key.fill")
                        .foregroundStyle(s.enclave ? Look.accent : .secondary).frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.name).font(.system(size: 12, weight: .medium, design: .monospaced)).lineLimit(1)
                        Text(s.enclave ? "Secure Enclave" : "Trousseau").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if doomed == s.name {
                        Button("Supprimer") { doomed = nil; Task { await m.delete(s.name) } }
                            .buttonStyle(Pill()).foregroundStyle(Look.bad)
                        Button { doomed = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                    } else {
                        Chip(text: s.broken ? "Illisible" : s.open ? "Ouvert" : "Verrouillé",
                             color: s.broken ? Look.bad : s.open ? Look.ok : Look.warn)
                    }
                }
            }.contextMenu { Button("Supprimer \(s.name)…", role: .destructive) { doomed = s.name } }
        }

        if adding {
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("NOM_DE_LA_VARIABLE", text: $name).font(.system(size: 12, design: .monospaced))
                    SecureField("Valeur", text: $value)
                    Toggle("Protéger par Touch ID (Secure Enclave)", isOn: $enclave).font(.system(size: 11))
                    HStack {
                        Spacer()
                        Button("Annuler") { reset() }.buttonStyle(Pill())
                        Button("Enregistrer") {
                            let (n, v, e) = (name, value, enclave)
                            reset()
                            Task { await m.store(n, v, enclave: e) }
                        }.buttonStyle(Pill(prominent: true))
                         .disabled(name.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) == nil || value.isEmpty)
                    }
                }.textFieldStyle(.roundedBorder)
            }
        } else {
            Button { adding = true } label: { Label("Ajouter une clé", systemImage: "plus") }
                .buttonStyle(Pill()).frame(maxWidth: .infinity, alignment: .leading)
        }
        lockToggle
    }

    private func reset() { adding = false; name = ""; value = "" }

    var lockToggle: some View {
        Toggle("Tout verrouiller quand l'écran se verrouille", isOn: $m.lockOnScreenLock)
            .font(.system(size: 10)).foregroundStyle(.secondary).toggleStyle(.checkbox).padding(.top, 4)
    }
}

// MARK: - Profiles

struct ProfilesTab: View {
    @EnvironmentObject var m: Model
    @State private var editing: String?
    @State private var useKey = false

    var body: some View {
        if Shell.chthonios == nil {
            Empty(icon: "exclamationmark.triangle", text: "chthonios introuvable (~/.local/bin/chthonios).")
        }
        ForEach(m.seals) { p in
            Card {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Image(systemName: icon(p.state)).foregroundStyle(color(p.state)).frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(.system(size: 12, weight: .medium))
                            Text(detail(p)).font(.system(size: 10)).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        action(p)
                    }
                    if editing == p.name { form(p) }
                }
            }
        }
        Text("Sceller chiffre le .env du profil : sans clé, il ne peut plus appeler aucun modèle. Pour chiffrer un profil entier, utilise l'onglet Coffres.")
            .font(.system(size: 10)).foregroundStyle(.tertiary).padding(.top, 4)
    }

    @ViewBuilder private func action(_ p: SealRow) -> some View {
        switch p.state {
        case .clear, .unmanaged:
            Button("Sceller") { useKey = m.fidoEnrolled(p.name); editing = p.name }.buttonStyle(Pill())
        case .sealed:
            Button("Ouvrir") { editing = p.name }.buttonStyle(Pill(prominent: true))
        case .open:
            Button("Refermer") { Task { await m.relock(p.name) } }.buttonStyle(Pill())
        }
    }

    @ViewBuilder private func form(_ p: SealRow) -> some View {
        let close = { editing = nil }
        if p.state == .sealed {
            SecretForm(title: p.fido ? "Branche la YubiKey, saisis le PIN puis touche-la." : "Phrase secrète de \(p.name)",
                       pin: p.fido, go: { s in close(); Task { await m.unseal(p.name, secret: s, fido: p.fido) } }, cancel: close)
        } else {
            Text("⚠︎ Un agent qui tourne sur ce profil perd ses clés dès le scellement.")
                .font(.system(size: 10)).foregroundStyle(Look.warn)
            if m.fidoEnrolled(p.name) {
                Toggle("Sceller sur la YubiKey", isOn: $useKey).font(.system(size: 11))
            }
            if useKey {
                HStack { Spacer(); Button("Annuler", action: close).buttonStyle(Pill())
                    Button("Sceller") { close(); Task { await m.seal(p.name, secret: "", fido: true) } }.buttonStyle(Pill(prominent: true)) }
            } else {
                SecretForm(title: "Nouvelle phrase secrète", confirm: true,
                           go: { s in close(); Task { await m.seal(p.name, secret: s, fido: false) } }, cancel: close)
            }
        }
    }

    private func icon(_ s: SealState) -> String {
        switch s { case .sealed: "lock.fill"; case .open: "lock.open.fill"; default: "circle.dashed" }
    }
    private func color(_ s: SealState) -> Color {
        switch s { case .sealed: Look.seal; case .open: Look.warn; default: .secondary }
    }
    private func detail(_ p: SealRow) -> String {
        switch p.state {
        case .sealed: p.fido ? "Scellé · YubiKey" : "Scellé · phrase secrète"
        case .open: "Ouvert : .env en clair jusqu'à fermeture"
        case .clear: "En clair"
        case .unmanaged: "Non scellé"
        }
    }
}

// MARK: - Vaults

struct VaultsTab: View {
    @EnvironmentObject var m: Model
    enum Target: Equatable { case folder(URL), bank(String) }
    @State private var target: Target?
    @State private var lock: Lock = .phrase
    @State private var opening: String?

    var body: some View {
        HStack(spacing: 8) {
            tile("folder.fill", "Dossier", "Obsidian, profil") { pickFolder() }
            Menu {
                if m.banks.isEmpty { Text("Hindsight injoignable") }
                ForEach(m.banks, id: \.self) { b in Button(b) { target = .bank(b) } }
            } label: {
                tileLabel("brain.head.profile", "Mémoire", "Banque Hindsight")
            }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        }
        .task { await m.refreshBanks() }

        if let target {
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: isBank ? "brain.head.profile" : "folder.fill").foregroundStyle(Look.accent)
                        Text(title(target)).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    }
                    Picker("", selection: $lock) {
                        ForEach(Lock.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden()
                    if lock == .yubikey {
                        if m.fidoProfileDir == nil {
                            Text("Aucune YubiKey enrôlée : lance `chthonios enroll-key <profil>` dans un terminal.")
                                .font(.system(size: 10)).foregroundStyle(Look.warn)
                        } else {
                            Text("Aucune touche requise pour sceller. Ouvrir demandera la clé.").font(.system(size: 10)).foregroundStyle(.secondary)
                            HStack { Spacer(); Button("Annuler") { self.target = nil }.buttonStyle(Pill())
                                Button("Sceller") { run(target, "") }.buttonStyle(Pill(prominent: true)) }
                        }
                    } else {
                        SecretForm(title: "Phrase secrète du coffre", confirm: true,
                                   go: { run(target, $0) }, cancel: { self.target = nil })
                    }
                }
            }
        }

        HStack {
            Text("Mes coffres").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            Spacer()
            Button { NSWorkspace.shared.open(URL(fileURLWithPath: m.coffreDir)) } label: { Image(systemName: "folder") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("~/Coffres dans le Finder")
        }.padding(.top, 6)

        if m.coffres.isEmpty { Empty(icon: "archivebox", text: "Aucun coffre dans ~/Coffres.") }
        ForEach(m.coffres) { c in
            Card {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Image(systemName: c.isMemory ? "brain.head.profile" : "archivebox.fill")
                            .foregroundStyle(c.isAge ? Look.seal : Look.accent).frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.name).font(.system(size: 11, weight: .medium)).lineLimit(1).truncationMode(.middle)
                            Text("\(ByteCountFormatter.string(fromByteCount: c.size, countStyle: .file)) · \(c.date.formatted(date: .abbreviated, time: .shortened))\(c.isAge ? " · YubiKey" : "")")
                                .font(.system(size: 10)).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        if c.isAge {
                            Button("Copier la commande") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(m.yubikeyOpenCommand(c), forType: .string)
                                m.note = ("Commande copiée : colle-la dans un terminal, YubiKey branchée.", true)
                            }.buttonStyle(Pill()).help("Ouvrir un coffre YubiKey se fait au terminal, avec la clé")
                        } else {
                            Button(c.isMemory ? "Restaurer" : "Ouvrir") { opening = c.id }.buttonStyle(Pill())
                        }
                    }
                    if opening == c.id {
                        SecretForm(title: c.isMemory ? "Restaure dans une nouvelle banque, l'actuelle n'est pas touchée." : "Déchiffre dans ~/Coffres/ouverts",
                                   go: { s in opening = nil; Task { c.isMemory ? await m.restore(c, secret: s) : await m.open(c, secret: s) } },
                                   cancel: { opening = nil })
                    }
                }
            }.contextMenu { Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([c.url]) } }
        }
    }

    private var isBank: Bool { if case .bank = target { return true }; return false }

    private func title(_ t: Target) -> String {
        switch t { case .folder(let u): u.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"); case .bank(let b): "Hindsight · \(b)" }
    }

    private func run(_ t: Target, _ secret: String) {
        target = nil
        let l = lock
        Task {
            switch t {
            case .folder(let u): await m.sealFolder(u, lock: l, secret: secret)
            case .bank(let b): await m.sealBank(b, lock: l, secret: secret)
            }
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        panel.prompt = "Choisir"
        panel.message = "Dossier ou fichier à chiffrer (l'original est conservé)"
        if panel.runModal() == .OK, let u = panel.url { target = .folder(u) }
    }

    private func tile(_ icon: String, _ t: String, _ s: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { tileLabel(icon, t, s) }.buttonStyle(.plain)
    }

    private func tileLabel(_ icon: String, _ t: String, _ s: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(Look.accent)
            Text(t).font(.system(size: 12, weight: .semibold))
            Text(s).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(10).frame(maxWidth: .infinity, minHeight: 72, maxHeight: 72, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.08)))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}
