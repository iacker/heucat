import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            TextField("Hermes CLI", text: $model.hermesBinary)
            TextField("Hermes home", text: $model.hermesHome)
            Text("No secret values are handled by the UI. Unlock and lock are delegated to the plugin CLI.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 520, height: 220)
    }
}
