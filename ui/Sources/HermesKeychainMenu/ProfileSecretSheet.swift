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

    enum Action { case seal, unseal }

    /// Sealing the profile the app is driving cuts the running agent off from
    /// its own keys. Worth a sentence before it happens.
    private var sealsActiveProfile: Bool {
        action == .seal && profile.name == model.activeProfile
    }
    private var isPIN: Bool { action == .unseal && profile.needsHardwareKey }
    private var needsConfirmation: Bool { action == .seal }
    private var canSubmit: Bool {
        !secret.isEmpty && (!needsConfirmation || secret == confirmation) && !model.isBusy
    }

    private var title: String {
        L(action == .seal ? "profiles.sealTitle" : "profiles.unsealTitle")
    }
    private var explanation: String {
        if isPIN { return L("profiles.pinExplain") }
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

                SecureField(L(isPIN ? "profiles.pinField" : "profiles.passField"), text: $secret)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { if canSubmit { submit() } }
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
                ok = await model.seal(profile, passphrase: secret)
            case .unseal:
                ok = await model.unseal(profile, secret: secret)
            }
            if ok { dismiss() }
        }
    }
}
