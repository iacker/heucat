import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Hermes runtime") {
                LabeledContent("CLI executable") { TextField("Hermes CLI", text: $model.hermesBinary).frame(width: 330) }
                LabeledContent("Profile home") { TextField("Hermes home", text: $model.hermesHome).frame(width: 330) }
                LabeledContent("Chthonios CLI") { TextField("Chthonios CLI", text: $model.chthoniosBinary).frame(width: 330) }
            }
            Section("Privacy") {
                Label("Secret values are accepted in protected fields, piped directly to the local CLI, cleared from the form, and never displayed again.", systemImage: "hand.raised.fill")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Verify connection") { Task { await model.refresh() } }.disabled(model.isBusy)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 620, height: 310)
    }
}
