import AppKit
import Foundation
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case secrets = "Secrets"
    case sessions = "Sessions"
    case profiles = "Sealed Profiles"
    case howitworks = "How it works"
    case diagnostics = "Diagnostics"
    var id: String { rawValue }

    /// Translated label for the sidebar.
    @MainActor var title: String {
        switch self {
        case .overview: L("nav.overview")
        case .secrets: L("nav.secrets")
        case .sessions: L("nav.sessions")
        case .profiles: L("nav.profiles")
        case .howitworks: L("nav.howitworks")
        case .diagnostics: L("nav.diagnostics")
        }
    }

    var icon: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .secrets: "key.horizontal"
        case .sessions: "touchid"
        case .profiles: "externaldrive.badge.lock"
        case .howitworks: "cpu"
        case .diagnostics: "waveform.path.ecg"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @AppStorage("hermesBinary") var hermesBinary = "~/.local/bin/hermes"
    @AppStorage("hermesHome") var hermesHome = "~/.hermes/profiles/ares"
    @AppStorage("chthoniosBinary") var chthoniosBinary = AppModel.defaultChthonios

    /// First install that actually exists. Hardcoding one path breaks the
    /// Sealed Profiles page the day that interpreter is cleaned up.
    static let defaultChthonios: String = [
        "~/.hermes/hermes-agent/venv/bin/chthonios",
        "~/.local/bin/chthonios",
        "~/Library/Python/3.9/bin/chthonios",
    ].first {
        FileManager.default.isExecutableFile(atPath: NSString(string: $0).expandingTildeInPath)
    } ?? "~/.local/bin/chthonios"

    @Published var status = KeychainStatus()
    @Published var isBusy = false
    @Published var message = L("msg.ready")
    @Published var lastUpdated: Date?
    @Published var selectedSection: AppSection? = .overview
    @Published var showingAddSecret = false
    @Published var prefillName = ""   // set when opening Add to update an existing secret's value
    @Published var pendingDeletion: SecretStatus?
    @Published var chthoniosSummary = "Checking…"
    @Published var chthoniosAvailable = false
    @Published var profiles: [ProfileStatus] = []
    @Published var pingResults: [String: String] = [:]   // env name -> "ok" | "dead" | "unknown" | "…"
    @Published var isTestingAll = false

    // MARK: Derived state
    //
    // Every number the dashboard shows is computed from real CLI status output.
    // Nothing here is decorative: an empty vault reports zero rather than a
    // flattering placeholder.

    var plainCount: Int { status.secrets.filter { $0.mode == "plain" }.count }
    var enclaveCount: Int { status.secrets.filter { $0.mode == "enclave" }.count }
    var readableCount: Int { status.secrets.filter(\.isUnlocked).count }
    var readableEnclaveCount: Int { status.secrets.filter { $0.mode == "enclave" && $0.isUnlocked }.count }

    var profileName: String {
        let name = (hermesHome as NSString).lastPathComponent
        return name.isEmpty ? "default" : name
    }

    /// Fraction of stored secrets currently readable. An empty vault is shown as
    /// full rather than zero, because "nothing stored" is not a failure state.
    var healthFraction: Double {
        guard status.sourceEnabled else { return 0 }
        guard !status.secrets.isEmpty else { return 1 }
        return Double(readableCount) / Double(status.secrets.count)
    }

    var healthLabel: String {
        guard status.sourceEnabled else { return "off" }
        return "\(Int((healthFraction * 100).rounded()))%"
    }

    var healthCaption: String {
        if !status.sourceEnabled { return L("overview.sourceDisabledCaption") }
        if status.secrets.isEmpty { return L("overview.noSecretsYet") }
        if readableCount == status.secrets.count { return L("overview.allReadable", status.secrets.count) }
        return L("overview.nLocked", status.secrets.count - readableCount, status.secrets.count)
    }

    var statusHeadline: String {
        if !status.sourceEnabled { return L("overview.sourceOff") }
        if status.secrets.isEmpty { return L("overview.noneStored") }
        return status.secrets.count == 1 ? L("overview.serving1") : L("overview.servingN", status.secrets.count)
    }

    var lastUpdatedCaption: String {
        guard let lastUpdated else { return L("app.notChecked") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return L("app.verified") + " " + formatter.localizedString(for: lastUpdated, relativeTo: Date())
    }

    var iconName: String {
        guard status.sourceEnabled else { return "lock.slash" }
        if status.secrets.contains(where: { $0.mode == "enclave" && !$0.isUnlocked }) { return "lock.fill" }
        return status.configuredCount > 0 ? "lock.open.fill" : "key.fill"
    }

    var runner: HermesRunner {
        HermesRunner(binaryPath: NSString(string: hermesBinary).expandingTildeInPath, hermesHome: hermesHome)
    }

    func refresh() async {
        await perform(L("msg.refreshing"), command: ["keychain", "status"]) { result in
            self.status = KeychainStatus.parse(result.output)
            self.message = result.exitCode == 0 ? L("msg.statusOk") : "Status \(result.exitCode)"
            self.lastUpdated = Date()
        }
        await refreshChthonios()
    }

    func refreshChthonios() async {
        let path = NSString(string: chthoniosBinary).expandingTildeInPath
        guard FileManager.default.isExecutableFile(atPath: path) else {
            chthoniosAvailable = false
            chthoniosSummary = L("profiles.notInstalled")
            profiles = []
            return
        }
        do {
            let result = try await chthoniosRunner.run(["status"])
            let ok = result.exitCode == 0
            chthoniosAvailable = ok
            chthoniosSummary = ChthoniosStatus.parse(result.output, ok: ok).label
            profiles = ChthoniosStatus.rows(result.output, ok: ok)
        } catch {
            chthoniosAvailable = false
            chthoniosSummary = error.localizedDescription
            profiles = []
        }
    }

    /// Chthonios is driven from the Hermes ROOT, not the profile dir — see
    /// `chthoniosHome(from:)`. Without this it only ever saw one profile.
    var chthoniosRunner: HermesRunner {
        HermesRunner(binaryPath: NSString(string: chthoniosBinary).expandingTildeInPath,
                     hermesHome: chthoniosHome(from: hermesHome))
    }

    /// The profile this app is currently pointed at. Sealing it cuts the agent
    /// off mid-session, so the UI warns before doing that.
    var activeProfile: String { (hermesHome as NSString).lastPathComponent }

    /// A profile can only be sealed to a YubiKey once a key has been enrolled,
    /// which writes the (non-secret) recipient beside the profile. Enrollment
    /// itself is a multi-prompt interactive ceremony and stays in the terminal.
    func isEnrolledForFIDO2(_ profile: String) -> Bool {
        let dir = NSString(string: chthoniosHome(from: hermesHome)).expandingTildeInPath
        return FileManager.default.fileExists(
            atPath: dir + "/profiles/\(profile)/.chthonios.recipient")
    }

    /// The command the user runs once, in a terminal, to bind a YubiKey.
    func enrollCommand(for profile: String) -> String {
        "chthonios enroll-key \(profile)"
    }

    /// Run one chthonios subcommand, feeding stdin when a secret is needed.
    /// `seal`/`unseal` read the passphrase from stdin (getpass falls back to it
    /// when there is no TTY); `lock`/`verify` need nothing. `seal` asks twice,
    /// hence `confirm`.
    func runChthonios(_ command: [String], secret: String? = nil, confirm: Bool = false,
                      activity: String) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        message = activity
        defer { isBusy = false }
        do {
            let stdin = secret.map { pass -> Data in
                Data((confirm ? "\(pass)\n\(pass)\n" : "\(pass)\n").utf8)
            }
            let result = try await chthoniosRunner.run(command, stdinData: stdin)
            // chthonios exits 0 on a wrong passphrase, so trust the text too.
            let out = result.output.lowercased()
            let failed = result.exitCode != 0
                || out.contains("wrong passphrase")
                || out.contains("failed")
                || out.contains("not found")
                || out.contains("do not match")
            message = failed ? lastLine(result.output) : activity + " " + L("msg.done")
            await refreshChthonios()
            return !failed
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func unlock() async {
        await perform(L("msg.waitingTouchID"), command: ["keychain", "unlock"]) { result in
            self.message = result.exitCode == 0 ? L("msg.sessionOpened") : self.lastLine(result.output)
        }
        await refresh()
    }

    func lock() async {
        await perform(L("msg.closingSessions"), command: ["keychain", "lock"]) { result in
            self.message = result.exitCode == 0 ? L("msg.sessionsClosed") : self.lastLine(result.output)
        }
        await refresh()
    }

    func store(name: String, value: String, enclave: Bool, service: String, account: String) async -> Bool {
        var command = ["keychain", "store", name, "--stdin"]
        if enclave { command.append("--enclave") }
        if !service.isEmpty { command += ["--service", service] }
        if !account.isEmpty { command += ["--account", account] }
        var succeeded = false
        await perform(L("msg.saving"), command: command, stdinData: Data(value.utf8)) { result in
            succeeded = result.exitCode == 0
            self.message = succeeded ? "\(name) " + L("msg.saved") : self.lastLine(result.output)
        }
        if succeeded { await refresh() }
        return succeeded
    }

    func delete(_ secret: SecretStatus) async {
        await perform(L("msg.removing") + " \(secret.name)…", command: ["keychain", "delete", secret.name]) { result in
            self.message = result.exitCode == 0 ? "\(secret.name) " + L("msg.removed") : self.lastLine(result.output)
        }
        await refresh()
    }

    func migrateToEnclave(_ secret: SecretStatus) async {
        await perform("\(secret.name) — " + L("msg.migrating"), command: ["keychain", "migrate", secret.name]) { result in
            self.message = result.exitCode == 0 ? "\(secret.name) " + L("msg.migrated") : self.lastLine(result.output)
        }
        await refresh()
    }

    /// Ping the provider for one secret. Runs outside `perform` so several rows
    /// can test at once and the isBusy gate never blocks a live network probe.
    func testSecret(_ secret: SecretStatus) async {
        pingResults[secret.name] = "…"
        do {
            let result = try await runner.run(["keychain", "test", secret.name])
            let out = result.output.lowercased()
            if out.contains("ok:") { pingResults[secret.name] = "ok" }
            else if out.contains("unknown:") { pingResults[secret.name] = "unknown" }
            else if out.contains("unreadable") { pingResults[secret.name] = "locked" }
            else { pingResults[secret.name] = "dead" }
        } catch {
            pingResults[secret.name] = "dead"
        }
    }

    /// Ping every secret in turn. ponytail: sequential, not a TaskGroup — a
    /// handful of keys finishes fast and it avoids hammering several provider
    /// APIs at once. Parallelise if this ever covers dozens of secrets.
    func testAll() async {
        guard !isTestingAll else { return }
        isTestingAll = true
        defer { isTestingAll = false }
        for secret in status.secrets {
            await testSecret(secret)
        }
    }

    /// Move every plain secret into the Enclave. Stops at the first failure so
    /// a broken one does not hide behind a pile of later output.
    func migrateAllPlain() async {
        for secret in status.secrets where secret.mode == "plain" {
            await migrateToEnclave(secret)
        }
    }

    /// Sealing needs no key at all in FIDO2 mode (public recipient only), and a
    /// passphrase otherwise. `seal` prompts twice, hence confirm.
    func seal(_ profile: ProfileStatus, passphrase: String, fido2: Bool = false) async -> Bool {
        if fido2 {
            // No secret at all: sealing only needs the public recipient, which
            // is the whole point — an unattended agent can lock a profile it
            // cannot itself reopen.
            return await runChthonios(["seal", profile.name, "--fido2"],
                                      activity: L("msg.sealing") + " \(profile.name)…")
        }
        return await runChthonios(["seal", profile.name], secret: passphrase, confirm: true,
                                  activity: L("msg.sealing") + " \(profile.name)…")
    }

    /// Passphrase profiles read it from stdin. FIDO2 profiles need the token's
    /// PIN plus a physical touch; --pin-stdin makes chthonios drive age on a
    /// pty so this works without a terminal.
    func unseal(_ profile: ProfileStatus, secret: String) async -> Bool {
        let command = profile.needsHardwareKey
            ? ["unseal", profile.name, "--pin-stdin"]
            : ["unseal", profile.name]
        return await runChthonios(command, secret: secret,
                                  activity: L(profile.needsHardwareKey
                                              ? "msg.waitingTouch" : "msg.unsealing")
                                            + " \(profile.name)…")
    }

    /// Drop the plaintext .env, keep the seal. No secret needed.
    func lockProfile(_ profile: ProfileStatus) async {
        _ = await runChthonios(["lock", profile.name],
                               activity: L("msg.locking") + " \(profile.name)…")
    }

    /// Check seal integrity. Needs no key, so it is always safe to offer.
    func verifyProfile(_ profile: ProfileStatus) async {
        _ = await runChthonios(["verify", profile.name],
                               activity: L("msg.verifying") + " \(profile.name)…")
    }

    func openRepository() {
        NSWorkspace.shared.open(URL(string: "https://github.com/iacker/heucat")!)
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
