import SwiftUI

/// Privacy-safe render of the live Overview for visual regression checks.
///
/// This deliberately mirrors the real Overview rather than reusing it, because
/// `ImageRenderer` does not lay out the split-view chrome correctly off screen.
/// It reads the same model, so the numbers are real, but it never renders a
/// secret value.
struct DiagnosticSnapshotView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Theme.hairline).frame(width: 0.7)
            VStack(spacing: 0) {
                titleBar
                Rectangle().fill(Theme.hairline).frame(height: 0.7)
                dashboard
                Rectangle().fill(Theme.hairline).frame(height: 0.7)
                footer
            }
        }
        .background(MarbleBackground())
    }

    private var titleBar: some View {
        HStack(spacing: 14) {
            Text("Hermes Keychain")
                .font(Theme.serif(15, weight: .medium))
                .foregroundStyle(Theme.ink)
            Spacer()
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Theme.card))
                .overlay(Circle().stroke(Theme.hairline, lineWidth: 0.7))
            HStack(spacing: 9) {
                Crest(size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Hermes Agent")
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

    private var dashboard: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 20) {
                hero
                HStack(alignment: .top, spacing: 16) {
                    keyOverview
                    recentSecrets
                }
                Spacer(minLength: 0)
            }
            rail.frame(width: 268)
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var hero: some View {
        Plate(padding: 0) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(text: "Runtime secret source")
                    Text("HERMES")
                        .font(Theme.display(46)).tracking(1.5)
                        .foregroundStyle(Theme.ink).fixedSize().padding(.top, 12)
                    Text("KEYCHAIN")
                        .font(Theme.display(46)).tracking(1.5)
                        .foregroundStyle(Theme.lapis).fixedSize()
                    Text("Secure your keys.\nEmpower your agent.\nCommand with trust.")
                        .font(Theme.serif(15)).lineSpacing(4)
                        .foregroundStyle(Theme.inkSoft).fixedSize().padding(.top, 16)
                    Ornament(width: 132).padding(.top, 18)
                    HStack(spacing: 11) {
                        Text("View secrets")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20).padding(.vertical, 11)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.lapis))
                        Text("Add secret")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 20).padding(.vertical, 11)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.hairline, lineWidth: 0.8))
                    }
                    .padding(.top, 22)
                }
                .padding(30)
                .frame(minWidth: 380, alignment: .leading)
                .layoutPriority(1)
                Spacer(minLength: 0)
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        Circle().stroke(Theme.lapis.opacity(0.07), lineWidth: 0.6)
                            .frame(width: 138 + CGFloat(i) * 42)
                    }
                    ForEach(0..<48, id: \.self) { i in
                        Rectangle().fill(Theme.lapis.opacity(0.13))
                            .frame(width: 0.7, height: 26).offset(y: -102)
                            .rotationEffect(.degrees(Double(i) * 7.5))
                    }
                    Image(systemName: "key.fill")
                        .font(.system(size: 62, weight: .ultraLight))
                        .foregroundStyle(Theme.ink.opacity(0.75))
                    VStack(spacing: 3) {
                        Ornament(width: 58, tint: Theme.lapis)
                        Text("VERIFIED BY").font(Theme.caption(7)).tracking(1.8)
                            .foregroundStyle(Theme.lapis.opacity(0.75))
                        Text("HERMES AGENT").font(Theme.serif(9, weight: .semibold)).tracking(1.4)
                            .foregroundStyle(Theme.lapis)
                        Text("MMXXVI").font(Theme.caption(7)).tracking(2.2)
                            .foregroundStyle(Theme.lapis.opacity(0.65))
                    }
                    .offset(y: 118)
                }
                .frame(width: 300, height: 316)
                .padding(.trailing, 26)
            }
        }
    }

    private var keyOverview: some View {
        Plate(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Key overview").font(Theme.serif(16, weight: .semibold)).foregroundStyle(Theme.ink)
                HStack(spacing: 22) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(model.status.configuredCount)")
                            .font(Theme.display(44)).foregroundStyle(Theme.ink)
                        Eyebrow(text: "Total keys")
                    }
                    Rectangle().fill(Theme.hairline).frame(width: 0.7, height: 58)
                    VStack(alignment: .leading, spacing: 9) {
                        countRow("key.fill", "Keychain", model.plainCount, Theme.lapis)
                        countRow("cpu", "Enclave", model.enclaveCount, Theme.verdigris)
                        countRow("lock.open.fill", "Readable", model.readableCount, Theme.inkSoft)
                    }
                    Spacer()
                }
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

    private var recentSecrets: some View {
        Plate(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Recent secrets").font(Theme.serif(16, weight: .semibold)).foregroundStyle(Theme.ink)
                if model.status.secrets.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "key.horizontal")
                            .font(.system(size: 24, weight: .ultraLight)).foregroundStyle(Theme.inkFaint)
                        Text("No secrets yet").font(Theme.serif(14, weight: .semibold)).foregroundStyle(Theme.ink)
                    }
                    .frame(maxWidth: .infinity).padding(18)
                    .background(Theme.paperDeep.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                                    .foregroundStyle(Theme.ink).lineLimit(1)
                                Spacer(minLength: 10)
                                Text(secret.isUnlocked ? "readable" : secret.state)
                                    .font(.system(size: 10))
                                    .foregroundStyle(secret.isUnlocked ? Theme.verdigris : Theme.amber)
                            }
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
                    Text("Agent status").font(Theme.serif(15, weight: .semibold))
                        .foregroundStyle(Theme.ink).frame(maxWidth: .infinity, alignment: .leading)
                    ZStack {
                        Image(systemName: "shield").font(.system(size: 54, weight: .ultraLight))
                            .foregroundStyle(model.status.sourceEnabled ? Theme.lapis : Theme.amber)
                        Image(systemName: "key.fill").font(.system(size: 17))
                            .foregroundStyle(model.status.sourceEnabled ? Theme.lapis : Theme.amber).offset(y: -2)
                    }
                    .padding(.top, 3)
                    Eyebrow(text: model.status.sourceEnabled ? "Protected" : "Attention",
                            tint: model.status.sourceEnabled ? Theme.lapis : Theme.amber)
                    Text(model.statusHeadline)
                        .font(Theme.serif(12)).foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    Ornament(width: 76).padding(.top, 2)
                }
                .frame(maxWidth: .infinity)
            }
            Plate(padding: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Enclave sessions").font(Theme.serif(16, weight: .semibold)).foregroundStyle(Theme.ink)
                        Spacer()
                        Text("\(model.enclaveCount)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.lapis)
                    }
                    sessionRow("cpu", "Secure Enclave",
                               model.status.enclaveKeyPresent ? "Key present on this Mac" : "No key generated",
                               model.status.enclaveKeyPresent)
                    Rectangle().fill(Theme.hairline).frame(height: 0.7)
                    sessionRow("touchid", "Unlocked secrets",
                               model.enclaveCount == 0 ? "No enclave secrets stored" : "\(model.readableEnclaveCount) of \(model.enclaveCount) readable",
                               model.enclaveCount > 0 && model.readableEnclaveCount > 0)
                }
            }
            Plate(padding: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Vault health").font(Theme.serif(16, weight: .semibold)).foregroundStyle(Theme.ink)
                    VStack(spacing: 11) {
                        HealthRing(value: model.healthFraction, label: model.healthLabel).padding(.vertical, 4)
                        Text(model.healthCaption)
                            .font(Theme.serif(12)).foregroundStyle(Theme.inkSoft)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func sessionRow(_ icon: String, _ title: String, _ detail: String, _ active: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(Theme.lapis)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.lapis.opacity(0.07)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.ink)
                Text(detail).font(.system(size: 10)).foregroundStyle(Theme.inkFaint)
            }
            Spacer(minLength: 6)
            HStack(spacing: 4) {
                Circle().fill(active ? Theme.verdigris : Theme.inkFaint).frame(width: 5, height: 5)
                Text(active ? "Active" : "Idle").font(.system(size: 10))
                    .foregroundStyle(active ? Theme.verdigris : Theme.inkFaint)
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(spacing: 9) {
                Crest(size: 74)
                Text("HERMES KEYCHAIN").font(Theme.serif(11, weight: .medium)).tracking(2.2)
                    .foregroundStyle(Theme.ink)
                Text("MMXXVI").font(Theme.caption(8)).tracking(3).foregroundStyle(Theme.inkFaint)
                Ornament(width: 92).padding(.top, 3)
            }
            .padding(.top, 30).padding(.bottom, 26)

            VStack(spacing: 3) {
                ForEach(AppSection.allCases) { section in
                    HStack(spacing: 11) {
                        Image(systemName: section.icon).font(.system(size: 13)).frame(width: 17)
                            .foregroundStyle(section == .overview ? Theme.lapis : Theme.inkSoft)
                        Text(section.rawValue)
                            .font(.system(size: 13, weight: section == .overview ? .semibold : .regular))
                            .foregroundStyle(section == .overview ? Theme.ink : Theme.inkSoft)
                        Spacer()
                    }
                    .padding(.horizontal, 13).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(section == .overview ? Color.white : .clear))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(section == .overview ? Theme.hairline : .clear, lineWidth: 0.7))
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
                        Text(model.status.sourceEnabled ? "All systems secure" : "Needs attention")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.ink)
                        Text(model.lastUpdatedCaption)
                            .font(.system(size: 10)).foregroundStyle(Theme.inkFaint)
                    }
                    Spacer()
                }
                Capsule().fill(Theme.hairline).frame(height: 2.5)
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            Capsule().fill(Theme.lapis)
                                .frame(width: geo.size.width * model.healthFraction)
                        }
                    }
            }
            .padding(.horizontal, 18).padding(.bottom, 22)
        }
        .frame(width: 214)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.55))
    }

    private var footer: some View {
        HStack(spacing: 11) {
            Spacer()
            Ornament(width: 74)
            Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(Theme.inkFaint)
            Text("Hardware-backed. Values never leave this Mac.")
                .font(Theme.serif(11)).foregroundStyle(Theme.inkSoft)
            Ornament(width: 74)
            Spacer()
        }
        .padding(.vertical, 11)
    }
}
