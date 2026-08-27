import SwiftUI

struct AddSecretView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var value = ""
    @State private var confirmation = ""
    @State private var protection = Protection.enclave
    @State private var showAdvanced = false
    @State private var service = ""
    @State private var account = ""
    @State private var error = ""

    private var isUpdate: Bool { !model.prefillName.isEmpty }

    enum Protection: String, CaseIterable, Identifiable {
        case enclave = "Secure Enclave"
        case keychain = "Apple Keychain"
        var id: String { rawValue }
    }

    private var validName: Bool {
        guard let first = name.first, first == "_" || first.isLetter else { return false }
        return name.allSatisfy { $0 == "_" || $0.isLetter || $0.isNumber }
    }
    private var canSave: Bool { validName && !value.isEmpty && value == confirmation && !model.isBusy }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack { RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.gradient); Image(systemName: "key.fill").foregroundStyle(.white).font(.title2) }.frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isUpdate ? "Update a secret" : "Add a secret").font(.title2.weight(.semibold))
                    Text(isUpdate
                         ? "Enter a new value for \(model.prefillName). The old value is overwritten."
                         : "The value is sent directly to protected storage and never displayed again.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(24)
            Divider()
            Form {
                Section("Identity") {
                    TextField("Environment variable", text: $name, prompt: Text("OPENROUTER_API_KEY"))
                        .textContentType(.none).font(.system(.body, design: .monospaced))
                        .disabled(isUpdate)
                    if !name.isEmpty && !validName { Text("Use letters, numbers and underscores; start with a letter or underscore.").font(.caption).foregroundStyle(.red) }
                }
                Section("Protection") {
                    Picker("Storage mode", selection: $protection) {
                        ForEach(Protection.allCases) { option in Text(option.rawValue).tag(option) }
                    }.pickerStyle(.segmented)
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: protection == .enclave ? "touchid" : "key.fill").foregroundStyle(.tint)
                        Text(protection == .enclave
                             ? "Recommended. Hardware-bound encryption with Touch ID or macOS authentication."
                             : "Stored as a generic password in the macOS login Keychain.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Secret value") {
                    SecureField("Value", text: $value)
                    SecureField("Confirm value", text: $confirmation)
                    if !confirmation.isEmpty && value != confirmation { Text("Values do not match.").font(.caption).foregroundStyle(.red) }
                }
                DisclosureGroup("Advanced options", isExpanded: $showAdvanced) {
                    TextField("Service (optional)", text: $service)
                    TextField("Account (optional)", text: $account)
                }
                if !error.isEmpty { Text(error).foregroundStyle(.red).font(.caption) }
            }.formStyle(.grouped).scrollContentBackground(.hidden).padding(.horizontal, 10)
            Divider()
            HStack {
                Label("Values never enter command arguments or logs", systemImage: "checkmark.shield.fill")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { clearAndDismiss() }.keyboardShortcut(.cancelAction)
                Button(isUpdate ? "Update value" : "Save securely") { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!canSave)
            }.padding(18)
        }.frame(width: 560, height: 650)
        .onAppear { if isUpdate { name = model.prefillName } }
    }

    private func save() {
        let secretValue = value
        value = ""
        confirmation = ""
        Task {
            let ok = await model.store(name: name, value: secretValue, enclave: protection == .enclave, service: service, account: account)
            if ok { model.prefillName = ""; dismiss() } else { error = model.message }
        }
    }

    private func clearAndDismiss() {
        value = ""; confirmation = ""; model.prefillName = ""; dismiss()
    }
}
