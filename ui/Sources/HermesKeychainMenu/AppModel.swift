import AppKit
import Foundation
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case secrets = "Secrets"
    case sessions = "Sessions"
    case profiles = "Sealed Profiles"
    case diagnostics = "Diagnostics"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .secrets: "key.horizontal"
        case .sessions: "touchid"
        case .profiles: "externaldrive.badge.lock"
        case .diagnostics: "waveform.path.ecg"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @AppStorage("hermesBinary") var hermesBinary = "~/.local/bin/hermes"
    @AppStorage("hermesHome") var hermesHome = "~/.hermes/profiles/ares"
    @AppStorage("chthoniosBinary") var chthoniosBinary = "~/Library/Python/3.9/bin/chthonios"

    @Published var status = KeychainStatus()
    @Published var isBusy = false
    @Published var message = "Ready"
    @Published var lastUpdated: Date?
    @Published var selectedSection: AppSection? = .overview
    @Published var showingAddSecret = false
    @Published var pendingDeletion: SecretStatus?
    @Published var chthoniosSummary = "Checking…"
    @Published var chthoniosAvailable = false

    var iconName: String {
        guard status.sourceEnabled else { return "lock.slash" }
        if status.secrets.contains(where: { $0.mode == "enclave" && !$0.isUnlocked }) { return "lock.fill" }
        return status.configuredCount > 0 ? "lock.open.fill" : "key.fill"
    }

    var runner: HermesRunner {
        HermesRunner(binaryPath: NSString(string: hermesBinary).expandingTildeInPath, hermesHome: hermesHome)
    }

    func refresh() async {
        await perform("Refreshing status…", command: ["keychain", "status"]) { result in
            self.status = KeychainStatus.parse(result.output)
            self.message = result.exitCode == 0 ? "Protection status is up to date" : "Status failed (\(result.exitCode))"
            self.lastUpdated = Date()
        }
        await refreshChthonios()
    }

    func refreshChthonios() async {
        let path = NSString(string: chthoniosBinary).expandingTildeInPath
        guard FileManager.default.isExecutableFile(atPath: path) else {
            chthoniosAvailable = false
            chthoniosSummary = "Chthonios is not installed"
            return
        }
        do {
            let result = try await HermesRunner(binaryPath: path, hermesHome: hermesHome).run(["status"])
            chthoniosAvailable = result.exitCode == 0
            if result.output.contains("unmanaged") {
                chthoniosSummary = "Arès is active and not sealed"
            } else if result.output.contains("sealed") {
                chthoniosSummary = "A sealed profile is present"
            } else {
                chthoniosSummary = result.exitCode == 0 ? "Chthonios ready" : "Chthonios check failed"
            }
        } catch {
            chthoniosAvailable = false
            chthoniosSummary = error.localizedDescription
        }
    }

    func unlock() async {
        await perform("Waiting for Touch ID…", command: ["keychain", "unlock"]) { result in
            self.message = result.exitCode == 0 ? "Secure session opened" : self.lastLine(result.output)
        }
        await refresh()
    }

    func lock() async {
        await perform("Closing secure sessions…", command: ["keychain", "lock"]) { result in
            self.message = result.exitCode == 0 ? "All sessions closed" : self.lastLine(result.output)
        }
        await refresh()
    }

    func store(name: String, value: String, enclave: Bool, service: String, account: String) async -> Bool {
        var command = ["keychain", "store", name, "--stdin"]
        if enclave { command.append("--enclave") }
        if !service.isEmpty { command += ["--service", service] }
        if !account.isEmpty { command += ["--account", account] }
        var succeeded = false
        await perform("Encrypting and saving…", command: command, stdinData: Data(value.utf8)) { result in
            succeeded = result.exitCode == 0
            self.message = succeeded ? "\(name) saved securely" : self.lastLine(result.output)
        }
        if succeeded { await refresh() }
        return succeeded
    }

    func delete(_ secret: SecretStatus) async {
        await perform("Removing \(secret.name)…", command: ["keychain", "delete", secret.name]) { result in
            self.message = result.exitCode == 0 ? "\(secret.name) removed" : self.lastLine(result.output)
        }
        await refresh()
    }

    func openRepository() {
        NSWorkspace.shared.open(URL(string: "https://github.com/iacker/hermes-keychain-secretsource")!)
    }

    func openKeychainFolder() {
        let path = NSString(string: hermesHome).expandingTildeInPath + "/keychain"
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
    }

    private func perform(_ activity: String, command: [String], stdinData: Data? = nil,
                         onResult: @escaping @MainActor (CommandResult) -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        message = activity
        defer { isBusy = false }
        do { onResult(try await runner.run(command, stdinData: stdinData)) }
        catch { message = error.localizedDescription }
    }

    private func lastLine(_ output: String) -> String {
        output.split(separator: "\n").last.map(String.init) ?? "Command failed"
    }
}
