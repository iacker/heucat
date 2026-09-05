import SwiftUI

struct AddSecretView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var loc = Loc.shared
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
        case enclave = "Secure Enclave"  // raw value is an id, label comes from Loc
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
                    Text(L(isUpdate ? "add.title.update" : "add.title")).font(.title2.weight(.semibold))
                    Text(isUpdate
                         ? L("add.updateHint").replacingOccurrences(of: "%@", with: model.prefillName)
                         : L("add.subtitle")).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(24)
            Divider()
            Form {
                Section(L("add.identity")) {
                    TextField(L("add.envVar"), text: $name, prompt: Text("OPENROUTER_API_KEY"))
                        .textContentType(.none).font(.system(.body, design: .monospaced))
                        .disabled(isUpdate)
                    if !name.isEmpty && !validName { Text(L("add.nameRule")).font(.caption).foregroundStyle(.red) }
                }
                Section(L("overview.protection")) {
                    Picker(L("add.protection"), selection: $protection) {
                        ForEach(Protection.allCases) { option in Text(option.rawValue).tag(option) }
                    }.pickerStyle(.segmented).disabled(isUpdate)
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: protection == .enclave ? "touchid" : "key.fill").foregroundStyle(.tint)
                        Text(protection == .enclave
                             ? L("add.enclaveHint")
                             : L("add.keychainHint"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section(L("add.value")) {
                    SecureField(L("add.valueField"), text: $value)
                    SecureField(L("add.confirm"), text: $confirmation)
                    if !confirmation.isEmpty && value != confirmation { Text(L("add.mismatch")).font(.caption).foregroundStyle(.red) }
                }
                DisclosureGroup(L("add.advanced"), isExpanded: $showAdvanced) {
                    TextField(L("add.service"), text: $service)
                    TextField(L("add.account"), text: $account)
                }.disabled(isUpdate)
                if !error.isEmpty { Text(error).foregroundStyle(.red).font(.caption) }
            }.formStyle(.grouped).scrollContentBackground(.hidden).padding(.horizontal, 10)
            Divider()
            HStack {
                Label(L("add.noLogs"), systemImage: "checkmark.shield.fill")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L("secrets.cancel")) { clearAndDismiss() }.keyboardShortcut(.cancelAction)
                Button(L(isUpdate ? "add.update" : "add.save")) { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!canSave)
            }.padding(18)
        }.frame(width: 560, height: 650)
        .onAppear {
            if isUpdate { name = model.prefillName }
            protection = model.prefillEnclave ? .enclave : .keychain
        }
    }

    private func save() {
        let secretValue = value
        value = ""
        confirmation = ""
        Task {
            let ok = await model.store(name: name, value: secretValue, enclave: protection == .enclave, service: service, account: account)
            if ok { model.prefillName = ""; model.prefillEnclave = true; dismiss() } else { error = model.message }
        }
    }

    private func clearAndDismiss() {
        value = ""; confirmation = ""; model.prefillName = ""; model.prefillEnclave = true; dismiss()
    }
}
