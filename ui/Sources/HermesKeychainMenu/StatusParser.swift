import Foundation

struct SecretStatus: Identifiable, Equatable {
    let name: String
    let mode: String
    let state: String

    var id: String { name }
    var isUnlocked: Bool {
        state == "unlocked" || state == "readable"
    }
}

struct KeychainStatus: Equatable {
    var sourceEnabled = false
    var helperPath = "unknown"
    var enclaveKeyPresent = false
    var configuredCount = 0
    var secrets: [SecretStatus] = []

    static func parse(_ output: String) -> KeychainStatus {
        var status = KeychainStatus()

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if let value = value(after: "source enabled :", in: line) {
                status.sourceEnabled = value.lowercased() == "true"
            } else if let value = value(after: "helper binary  :", in: line) {
                status.helperPath = value
            } else if let value = value(after: "enclave key    :", in: line) {
                status.enclaveKeyPresent = value == "present"
            } else if let value = value(after: "configured     :", in: line) {
                status.configuredCount = Int(value.split(separator: " ").first ?? "0") ?? 0
            } else if line.hasPrefix("  ") {
                let fields = line.trimmingCharacters(in: .whitespaces)
                    .split(whereSeparator: { $0.isWhitespace })
                guard fields.count >= 3 else { continue }
                let mode = String(fields[1])
                guard mode == "plain" || mode == "enclave" else { continue }
                status.secrets.append(
                    SecretStatus(
                        name: String(fields[0]),
                        mode: mode,
                        state: fields.dropFirst(2).map(String.init).joined(separator: " ")
                    )
                )
            }
        }
        return status
    }

    private static func value(after prefix: String, in line: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }
}

/// Chthonios wants the Hermes ROOT (`~/.hermes`) and derives `profiles/<name>`
/// itself, while the keychain CLI wants the profile dir (`~/.hermes/profiles/ares`).
/// Passing the app's hermesHome straight through made chthonios see one profile
/// instead of all of them. ponytail: string trim, not a filesystem probe — the
/// layout is fixed by Hermes itself.
func chthoniosHome(from hermesHome: String) -> String {
    guard let r = hermesHome.range(of: "/profiles/") else { return hermesHome }
    return String(hermesHome[..<r.lowerBound])
}

/// One row of `chthonios status`, i.e. one Hermes profile.
struct ProfileStatus: Identifiable, Equatable {
    let name: String
    let state: State
    let backend: String     // "passphrase", "fido2-hmac", or "" when unmanaged
    let integrity: String   // "ok", "BAD", or "" when unmanaged
    let sealedAt: String

    var id: String { name }
    /// FIDO2 unsealing needs the YubiKey's PIN, so the UI must offer a PIN field.
    var needsHardwareKey: Bool { backend.hasPrefix("fido2") }

    enum State: String, Equatable {
        case sealed     // ciphertext at rest, no .env
        case open       // unsealed for this session
        case unmanaged  // chthonios does not know this profile
    }
}

/// Result of `chthonios status`, as a case plus the profile names it names.
///
/// Kept out of AppModel so the self-test can compile this file alone, without
/// SwiftUI. The view turns a case into translated text; this file stays pure.
enum ChthoniosStatus: Equatable {
    case failed
    case none
    case sealed([String])
    case unmanaged([String])

    /// The table is `PROFILE STATE BACKEND INTEGRITY SEALED AT` under a rule,
    /// so data rows are whatever follows the rule line.
    ///
    /// ponytail: split on whitespace runs, not fixed columns. The state glyph
    /// (◆ ◇ ◈) is dropped and the state word drives everything; widen only if
    /// a column ever holds a value with a space in it.
    static func rows(_ output: String, ok: Bool) -> [ProfileStatus] {
        guard ok else { return [] }
        return output
            .split(separator: "\n")
            .drop { !$0.contains("\u{2500}") }   // ── header rule
            .dropFirst()
            .compactMap { line -> ProfileStatus? in
                let glyphs: Set<Character> = ["\u{25C6}", "\u{25C7}", "\u{25C8}", "\u{2713}"]
                let fields: [String] = line
                    .split(whereSeparator: { $0.isWhitespace })
                    .map(String.init)
                    .filter { $0.count != 1 || !glyphs.contains($0.first!) }
                guard fields.count >= 2,
                      let state = ProfileStatus.State(fields[1]) else { return nil }
                return ProfileStatus(
                    name: fields[0],
                    state: state,
                    backend: fields.count > 2 ? fields[2] : "",
                    integrity: fields.count > 3 ? fields[3] : "",
                    sealedAt: fields.count > 4 ? fields[4] : ""
                )
            }
    }

    static func parse(_ output: String, ok: Bool) -> ChthoniosStatus {
        guard ok else { return .failed }
        let rows = rows(output, ok: ok)
        guard !rows.isEmpty else { return .none }
        let sealed = rows.filter { $0.state == .sealed }.map(\.name)
        return sealed.isEmpty ? .unmanaged(rows.map(\.name)) : .sealed(sealed)
    }
}

private extension ProfileStatus.State {
    /// The CLI prints SEALED / OPEN / unmanaged. Match case-insensitively so a
    /// cosmetic change in the CLI cannot silently empty the table.
    init?(_ word: String) {
        switch word.lowercased() {
        case "sealed": self = .sealed
        case "open": self = .open
        case "unmanaged": self = .unmanaged
        default: return nil
        }
    }
}
