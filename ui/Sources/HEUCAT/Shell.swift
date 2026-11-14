import Foundation

struct RunResult {
    let out: String
    let code: Int32
    var ok: Bool { code == 0 }
    /// Last meaningful line, stripped of the CLI's decorative glyphs.
    var summary: String {
        let lines = out.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasSuffix("passphrase:") && !$0.hasPrefix("Confirm") }
        let last = lines.last ?? (ok ? "OK" : "Échec (\(code))")
        return last.trimmingCharacters(in: CharacterSet(charactersIn: "◆◇✓✗•· "))
    }
}

/// Every external call goes through here: one short-lived process, no shell,
/// secrets only ever on stdin (never argv, never the environment).
enum Shell {
    static func expand(_ p: String) -> String { (p as NSString).expandingTildeInPath }

    static func firstExecutable(_ candidates: [String]) -> String? {
        candidates.map(expand).first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static let python = "/usr/bin/python3"
    static var heucatCLI: String { expand("~/.hermes/plugins/keychain-secretsource/heucat.py") }
    static var chthonios: String? {
        firstExecutable(["~/.local/bin/chthonios", "/opt/homebrew/bin/chthonios", "/usr/local/bin/chthonios"])
    }

    static func run(_ exe: String, _ args: [String], hermesHome: String? = nil,
                    stdin: String? = nil, timeout: TimeInterval = 120) async -> RunResult {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: exe)
                p.arguments = args
                var env = ProcessInfo.processInfo.environment
                env.removeValue(forKey: "PYTHONPATH")   // never inherit a foreign venv
                env["NO_COLOR"] = "1"
                env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + expand("~/.local/bin")
                if let hermesHome { env["HERMES_HOME"] = hermesHome }
                p.environment = env
                let out = Pipe(), inp = Pipe()
                p.standardOutput = out
                p.standardError = out
                p.standardInput = inp
                let buffer = Buffer()
                out.fileHandleForReading.readabilityHandler = { buffer.append($0.availableData) }
                do { try p.run() } catch {
                    cont.resume(returning: RunResult(out: error.localizedDescription, code: -1))
                    return
                }
                if let stdin { inp.fileHandleForWriting.write(Data(stdin.utf8)) }
                try? inp.fileHandleForWriting.close()
                let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
                p.waitUntilExit()
                killer.cancel()
                out.fileHandleForReading.readabilityHandler = nil
                buffer.append(out.fileHandleForReading.readDataToEndOfFile())
                cont.resume(returning: RunResult(out: buffer.string, code: p.terminationStatus))
            }
        }
    }
}

private final class Buffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func append(_ d: Data) { lock.lock(); data.append(d); lock.unlock() }
    var string: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }
}
