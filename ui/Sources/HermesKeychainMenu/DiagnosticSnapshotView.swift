import SwiftUI

/// Privacy-safe render of the live Overview for visual regression checks.
struct DiagnosticSnapshotView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            dashboard
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Overview").font(.largeTitle.weight(.semibold))
                Text("Hardware-backed protection for your Hermes credentials")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                snapshotMetric("Protected secrets", "\(model.status.configuredCount)", "key.horizontal.fill", .blue)
                snapshotMetric("Secure Enclave", model.status.enclaveKeyPresent ? "Ready" : "Unavailable", "cpu.fill", .purple)
                snapshotMetric("Secret source", model.status.sourceEnabled ? "Connected" : "Disabled", "link.circle.fill", .green)
            }

            HStack(spacing: 22) {
                ZStack {
                    Circle().fill(.green.opacity(0.12))
                    Image(systemName: model.status.sourceEnabled ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .font(.system(size: 34)).foregroundStyle(model.status.sourceEnabled ? .green : .orange)
                }.frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.status.sourceEnabled ? "Your secret source is protected" : "Protection needs attention")
                        .font(.title3.weight(.semibold))
                    Text("Values stay out of configuration files and are never displayed by this app.")
                        .foregroundStyle(.secondary)
                    Text(model.message).font(.caption).foregroundStyle(.secondary).padding(.top, 3)
                }
                Spacer()
                Text("Manage secrets").foregroundStyle(.tint)
            }
            .padding(22)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary))

            HStack { Text("Secrets").font(.title3.weight(.semibold)); Spacer() }
            VStack(spacing: 12) {
                Image(systemName: "key.horizontal").font(.system(size: 30)).foregroundStyle(.secondary)
                Text("No secrets yet").font(.title3.weight(.semibold))
                Text("Add your first credential without leaving a plaintext copy behind.")
                    .foregroundStyle(.secondary)
                Text("＋  Add secret").font(.body.weight(.medium)).foregroundStyle(.white)
                    .padding(.horizontal, 15).padding(.vertical, 8)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
            }
            .frame(maxWidth: .infinity)
            .padding(22)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(style: StrokeStyle(lineWidth: 1, dash: [5])).foregroundStyle(.quaternary))
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func snapshotMetric(_ title: String, _ value: String, _ icon: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundStyle(tint)
            Text(value).font(.title2.weight(.semibold))
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.gradient)
                    Image(systemName: "key.fill").foregroundStyle(.white).font(.system(size: 17, weight: .semibold))
                }.frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Hermes Keychain").font(.headline)
                    Text("Secure secrets for Hermes").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.bottom, 14)

            ForEach(AppSection.allCases) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(section == .overview ? Color.accentColor.opacity(0.14) : .clear,
                                in: RoundedRectangle(cornerRadius: 8))
            }
            Spacer()
            HStack(spacing: 8) {
                Circle().fill(model.status.sourceEnabled ? .green : .orange).frame(width: 7, height: 7)
                Text(model.status.sourceEnabled ? "Protection active" : "Needs attention")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 220)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
    }
}
