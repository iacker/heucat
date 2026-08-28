import SwiftUI

/// Asks for the one secret a chthonios action needs: a passphrase, or a FIDO2
/// PIN. Sealing asks twice (chthonios confirms), so the second field appears
/// only then.
struct ProfileSecretSheet: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var loc = Loc.shared
    @Environment(\.dismiss) private var dismiss

    let profile: ProfileStatus
    let action: Action

    @State private var secret = ""
    @State private var confirmation = ""
    @State private var useFIDO2 = false

    enum Action { case seal, unseal }

    /// Sealing the profile the app is driving cuts the running agent off from
    /// its own keys. Worth a sentence before it happens.
    private var sealsActiveProfile: Bool {
        action == .seal && profile.name == model.activeProfile
    }
    /// A YubiKey seal is only offered once a key has been enrolled for this
    /// profile; without a recipient chthonios has nothing to encrypt to.
    private var canOfferFIDO2: Bool {
        action == .seal && model.isEnrolledForFIDO2(profile.name)
    }
    private var sealingToKey: Bool { canOfferFIDO2 && useFIDO2 }
    private var isPIN: Bool { action == .unseal && profile.needsHardwareKey }
    /// FIDO2 sealing asks for nothing at all — that is the design.
    private var needsSecret: Bool { !sealingToKey }
    private var needsConfirmation: Bool { action == .seal && !sealingToKey }
    private var canSubmit: Bool {
        guard !model.isBusy else { return false }
        if !needsSecret { return true }
        return !secret.isEmpty && (!needsConfirmation || secret == confirmation)
    }

    private var title: String {
        L(action == .seal ? "profiles.sealTitle" : "profiles.unsealTitle")
    }
    private var explanation: String {
        if isPIN { return L("profiles.pinExplain") }
        if sealingToKey { return L("profiles.sealFido2Explain") }
        return L(action == .seal ? "profiles.sealExplain" : "profiles.unsealExplain")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill((isPIN ? Theme.amber : Theme.lapis).gradient)
                    Image(systemName: isPIN ? "key.horizontal.fill" : "lock.fill")
                        .foregroundStyle(.white).font(.title2)
                }.frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.title2.weight(.semibold))
                    Text(profile.name)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                Text(explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if sealsActiveProfile {
                    Label(L("profiles.warnActive"), systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(Theme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if canOfferFIDO2 {
                    Picker("", selection: $useFIDO2) {
                        Text(L("profiles.backendPassphrase")).tag(false)
                        Text(L("profiles.backendYubikey")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } else if action == .seal {
                    // No key here yet. If another profile has one, the same
                    // physical key can cover this one too — one click, no touch.
                    if let source = model.profileWithEnrolledKey {
                        HStack(spacing: 8) {
                            Image(systemName: "key.horizontal")
                                .foregroundStyle(Theme.amber)
                            Text(L("profiles.reuseKeyFrom").replacingOccurrences(
                                of: "%@", with: source))
                                .font(.caption)
                                .foregroundStyle(Theme.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button(L("profiles.useSameKey")) {
                                Task { await model.reuseKey(for: profile, from: source) }
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                            .disabled(model.isBusy)
                        }
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "key.horizontal")
                                .foregroundStyle(Theme.inkFaint)
                            Text(L("profiles.noKeyEnrolled"))
                                .font(.caption)
                                .foregroundStyle(Theme.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button(L("profiles.copyEnroll")) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(
                                    model.enrollCommand(for: profile.name), forType: .string)
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }
                    }
                }

                if needsSecret {
                    SecureField(L(isPIN ? "profiles.pinField" : "profiles.passField"), text: $secret)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { if canSubmit { submit() } }
                }
                if needsConfirmation {
                    SecureField(L("profiles.passConfirm"), text: $confirmation)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { if canSubmit { submit() } }
                    if !confirmation.isEmpty && secret != confirmation {
                        Text(L("profiles.passMismatch"))
                            .font(.caption).foregroundStyle(.red)
                    }
                }

                if isPIN {
                    Label(L("profiles.touchHint"), systemImage: "hand.tap.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            .padding(20)

            Divider()

            HStack {
                if model.isBusy { ProgressView().controlSize(.small) }
                Spacer()
                Button(L("secrets.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L(action == .seal ? "profiles.seal" : "profiles.unseal")) { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
            }
            .padding(20)
        }
        .frame(width: 460)
    }

    private func submit() {
        Task {
            let ok: Bool
            switch action {
            case .seal:
                ok = await model.seal(profile, passphrase: secret, fido2: sealingToKey)
            case .unseal:
                ok = await model.unseal(profile, secret: secret)
            }
            if ok { dismiss() }
        }
    }
}
