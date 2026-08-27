import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @AppStorage("hermesBinary") var hermesBinary = "~/.local/bin/hermes"
    @AppStorage("hermesHome") var hermesHome = "~/.hermes/profiles/ares"

    @Published var status = KeychainStatus()
    @Published var isBusy = false
    @Published var message = "Ready"
    @Published var lastUpdated: Date?

    var iconName: String {
        guard status.sourceEnabled else { return "lock.slash" }
        if status.secrets.contains(where: { $0.mode == "enclave" && !$0.isUnlocked }) {
            return "lock.fill"
        }
        return status.configuredCount > 0 ? "lock.open.fill" : "key.fill"
    }

    var runner: HermesRunner {
        HermesRunner(
            binaryPath: NSString(string: hermesBinary).expandingTildeInPath,
            hermesHome: hermesHome
        )
    }

    func refresh() async {
        await perform("Refreshing…", command: ["keychain", "status"]) { result in
            self.status = KeychainStatus.parse(result.output)
            self.message = result.exitCode == 0 ? "Status refreshed" : "Status failed (\(result.exitCode))"
            self.lastUpdated = Date()
        }
    }

    func unlock() async {
        await perform("Waiting for authentication…", command: ["keychain", "unlock"]) { result in
            self.message = result.exitCode == 0 ? "Secrets unlocked" : self.lastLine(result.output)
            if result.exitCode == 0 {
                Task { await self.refresh() }
            }
        }
    }

    func lock() async {
        await perform("Locking…", command: ["keychain", "lock"]) { result in
            self.message = result.exitCode == 0 ? "Sessions cleared" : self.lastLine(result.output)
            if result.exitCode == 0 {
                Task { await self.refresh() }
            }
        }
    }

    func openRepository() {
        NSWorkspace.shared.open(URL(string: "https://github.com/iacker/hermes-keychain-secretsource")!)
    }

    private func perform(
        _ activity: String,
        command: [String],
        onResult: @escaping @MainActor (CommandResult) -> Void
    ) async {
        guard !isBusy else { return }
        isBusy = true
        message = activity
        defer { isBusy = false }
        do {
            onResult(try await runner.run(command))
        } catch {
            message = error.localizedDescription
        }
    }

    private func lastLine(_ output: String) -> String {
        output.split(separator: "\n").last.map(String.init) ?? "Command failed"
    }
}
