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
    /// ponytail: substring match on the state word, not a column parser. The
    /// CLI is ours and the states are a closed set; widen only if a state ever
    /// needs its own wording.
    static func parse(_ output: String, ok: Bool) -> ChthoniosStatus {
        guard ok else { return .failed }
        let rows = output
            .split(separator: "\n")
            .drop { !$0.contains("\u{2500}") }
            .dropFirst()
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !rows.isEmpty else { return .none }

        let name = { (row: String) in row.split(separator: " ").first.map(String.init) }
        let sealed = rows.filter { $0.contains("sealed") }.compactMap(name)
        return sealed.isEmpty ? .unmanaged(rows.compactMap(name)) : .sealed(sealed)
    }
}
