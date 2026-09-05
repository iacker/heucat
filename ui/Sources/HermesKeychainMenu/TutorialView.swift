import SwiftUI

/// A beginner guide plus a live checklist. Completion is derived from live state.
struct TutorialView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var loc = Loc.shared

    private struct Step: Identifiable {
        let id: Int
        let done: Bool
        let action: () -> Void
    }

    private struct Lesson: Identifiable {
        let id: String
        let icon: String
        let destination: AppSection
    }

    private var steps: [Step] {
        let s = model.status
        return [
            Step(id: 1, done: s.sourceEnabled, action: { Task { await model.refresh() } }),
            Step(id: 2, done: s.helperPath != "unknown" && !s.helperPath.contains("missing"), action: { model.selectedSection = .diagnostics }),
            Step(id: 3, done: model.plainCount > 0, action: { model.prefillName = ""; model.prefillEnclave = false; model.showingAddSecret = true }),
            Step(id: 4, done: model.enclaveCount > 0, action: { model.prefillName = ""; model.prefillEnclave = true; model.showingAddSecret = true }),
            Step(id: 5, done: s.secrets.contains { $0.mode == "enclave" && $0.isUnlocked }, action: { Task { await model.unlock() } }),
            Step(id: 6, done: model.lockOnScreenLock, action: { model.lockOnScreenLock = true }),
        ]
    }

    private let lessons = [
        Lesson(id: "overview", icon: "square.grid.2x2", destination: .overview),
        Lesson(id: "secrets", icon: "key", destination: .secrets),
        Lesson(id: "sessions", icon: "touchid", destination: .sessions),
        Lesson(id: "profiles", icon: "person.badge.key", destination: .profiles),
        Lesson(id: "diagnostics", icon: "waveform.path.ecg", destination: .diagnostics),
    ]

    private struct Stage: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let body: String
    }

    /// The runtime chain, built at render time so the language switch re-reads it.
    private var stages: [Stage] {
        (1...4).map { i in
            Stage(icon: ["cpu", "lock.doc", "touchid", "bolt.horizontal"][i - 1],
                  title: L("how.\(i).title"),
                  body: L("how.\(i).body"))
        }
    }

    var body: some View {
        Group {
            if snapshotMode { stack } else { ScrollView { stack } }
        }
    }

    private var stack: some View {
        VStack(alignment: .leading, spacing: 20) {
            pageHeader(L("tut.title"), L("tut.subtitle"))
            securityBasics
            pipeline
            interfaceGuide
            checklist
        }
        .padding(28)
    }

    private var pipeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("how.title", "how.subtitle")
            ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
                Plate {
                    HStack(alignment: .top, spacing: 16) {
                        ZStack {
                            Circle().fill(Theme.lapis.opacity(0.08)).frame(width: 46, height: 46)
                            Image(systemName: stage.icon)
                                .font(.system(size: 18, weight: .light))
                                .foregroundStyle(Theme.lapis)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Eyebrow(text: L("how.step") + " \(index + 1)")
                            Text(stage.title)
                                .font(Theme.serif(17, weight: .semibold)).foregroundStyle(Theme.ink)
                            Text(stage.body)
                                .font(Theme.serif(13)).foregroundStyle(Theme.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            Plate {
                VStack(alignment: .leading, spacing: 7) {
                    Eyebrow(text: L("how.tradeoff.title"), tint: Theme.amber)
                    Text(L("how.tradeoff.body"))
                        .font(Theme.serif(13)).foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var securityBasics: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("tut.security.title", "tut.security.subtitle")
            HStack(alignment: .top, spacing: 14) {
                concept("keychain", "key.fill")
                concept("plain", "clock.arrow.circlepath")
                concept("enclave", "touchid")
                concept("session", "timer")
            }
            Plate {
                Label {
                    Text(L("tut.security.rule")).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "lightbulb.fill").foregroundStyle(Theme.amber)
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.ink)
            }
        }
    }

    private func concept(_ id: String, _ icon: String) -> some View {
        Plate {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.system(size: 20)).foregroundStyle(Theme.lapis)
                Text(L("tut.security.\(id).title"))
                    .font(Theme.serif(16, weight: .semibold)).foregroundStyle(Theme.ink)
                Text(L("tut.security.\(id).body"))
                    .font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private var interfaceGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("tut.ui.title", "tut.ui.subtitle")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(lessons) { lesson in
                    Button { model.selectedSection = lesson.destination } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: lesson.icon)
                                .font(.system(size: 18)).foregroundStyle(Theme.lapis).frame(width: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L("tut.ui.\(lesson.id).title"))
                                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                                Text(L("tut.ui.\(lesson.id).body"))
                                    .font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Image(systemName: "arrow.right").foregroundStyle(Theme.inkFaint)
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline, lineWidth: 0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("tut.checklist.title", "tut.checklist.subtitle")
            Plate {
                HStack(spacing: 16) {
                    Image(systemName: "checklist").font(.system(size: 21)).foregroundStyle(Theme.lapis)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L("tut.progress", steps.filter(\.done).count, steps.count))
                            .font(Theme.serif(17, weight: .semibold)).foregroundStyle(Theme.ink)
                        ProgressView(value: Double(steps.filter(\.done).count), total: Double(steps.count)).tint(Theme.verdigris)
                    }
                }
            }
            ForEach(steps) { step in
                Plate {
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: step.done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(step.done ? Theme.verdigris : Theme.inkFaint).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 6) {
                            Eyebrow(text: step.done ? L("tut.done") : L("tut.todo"))
                            Text(L("tut.\(step.id).title"))
                                .font(Theme.serif(17, weight: .semibold)).foregroundStyle(Theme.ink)
                            Text(L("tut.\(step.id).body"))
                                .font(.system(size: 13)).foregroundStyle(Theme.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if !step.done {
                            Button(L("tut.\(step.id).action"), action: step.action)
                                .buttonStyle(QuietButtonStyle()).disabled(model.isBusy)
                        }
                    }
                }
            }
        }
    }

    private func sectionTitle(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L(title)).font(Theme.serif(22, weight: .semibold)).foregroundStyle(Theme.ink)
            Text(L(subtitle)).font(.system(size: 13)).foregroundStyle(Theme.inkSoft)
        }
    }
}
