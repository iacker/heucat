import SwiftUI

/// Six-step checklist. Every box is derived from live state, never stored:
/// a user can't tick "helper built" while the helper is missing.
struct TutorialView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var loc = Loc.shared

    private struct Step: Identifiable {
        let id: Int
        let done: Bool
        let action: () -> Void
    }

    private var steps: [Step] {
        let s = model.status
        return [
            Step(id: 1, done: s.sourceEnabled,
                 action: { Task { await model.refresh() } }),
            Step(id: 2, done: s.helperPath != "unknown" && !s.helperPath.contains("missing"),
                 action: { model.selectedSection = .diagnostics }),
            Step(id: 3, done: model.plainCount > 0,
                 action: { model.prefillName = ""; model.prefillEnclave = false; model.showingAddSecret = true }),
            Step(id: 4, done: model.enclaveCount > 0,
                 action: { model.prefillName = ""; model.prefillEnclave = true; model.showingAddSecret = true }),
            Step(id: 5, done: s.secrets.contains { $0.mode == "enclave" && $0.isUnlocked },
                 action: { Task { await model.unlock() } }),
            Step(id: 6, done: model.lockOnScreenLock,
                 action: { model.lockOnScreenLock = true }),
        ]
    }

    var body: some View {
        Group {
            if snapshotMode { stack } else { ScrollView { stack } }
        }
    }

    private var stack: some View {
        VStack(alignment: .leading, spacing: 20) {
            pageHeader(L("tut.title"), L("tut.subtitle"))
            ForEach(steps) { step in
                Plate {
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: step.done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(step.done ? Theme.verdigris : Theme.inkFaint)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 6) {
                            Eyebrow(text: step.done ? L("tut.done") : L("tut.todo"))
                            Text(L("tut.\(step.id).title"))
                                .font(Theme.serif(17, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                            Text(L("tut.\(step.id).body"))
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if !step.done {
                            Button(L("tut.\(step.id).action"), action: step.action)
                                .disabled(model.isBusy)
                        }
                    }
                }
            }
        }
        .padding(28)
    }
}
