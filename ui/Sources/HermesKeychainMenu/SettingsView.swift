import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var loc = Loc.shared

    var body: some View {
        Form {
            Section(L("settings.language")) {
                Picker(L("settings.language"), selection: Binding(
                    get: { loc.language },
                    set: { loc.language = $0 }
                )) {
                    ForEach(Language.allCases) { lang in
                        Text(lang.label).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section(L("overview.hermesRuntime")) {
                LabeledContent(L("settings.cliExe")) { TextField(L("diag.hermesCli"), text: $model.hermesBinary).frame(width: 330) }
                LabeledContent(L("settings.profileHome")) { TextField(L("diag.hermesHome"), text: $model.hermesHome).frame(width: 330) }
                LabeledContent(L("diag.chthoniosCli")) { TextField(L("diag.chthoniosCli"), text: $model.chthoniosBinary).frame(width: 330) }
            }
            Section(L("settings.privacy")) {
                Label(L("settings.privacyBody"), systemImage: "hand.raised.fill")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button(L("settings.verify")) { Task { await model.refresh() } }.disabled(model.isBusy)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 620, height: 400)
    }
}
