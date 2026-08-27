import Foundation

struct CommandResult {
    let output: String
    let exitCode: Int32
}

enum HermesRunnerError: LocalizedError {
    case binaryNotFound
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "Hermes CLI not found. Set its path in Settings."
        case .launchFailed(let message):
            return "Could not launch Hermes: \(message)"
        }
    }
}

struct HermesRunner {
    let binaryPath: String
    let hermesHome: String

    func run(_ arguments: [String]) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()

            guard FileManager.default.isExecutableFile(atPath: binaryPath) else {
                continuation.resume(throwing: HermesRunnerError.binaryNotFound)
                return
            }

            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = arguments
            process.standardOutput = stdout
            process.standardError = stderr

            let parentEnvironment = ProcessInfo.processInfo.environment
            var environment: [String: String] = [:]
            for key in ["PATH", "HOME", "TMPDIR", "LANG", "LC_ALL"] {
                environment[key] = parentEnvironment[key]
            }
            environment["HERMES_HOME"] = NSString(string: hermesHome).expandingTildeInPath
            environment["NO_COLOR"] = "1"
            process.environment = environment

            process.terminationHandler = { process in
                let out = stdout.fileHandleForReading.readDataToEndOfFile()
                let err = stderr.fileHandleForReading.readDataToEndOfFile()
                let merged = String(decoding: out + err, as: UTF8.self)
                continuation.resume(returning: CommandResult(output: merged, exitCode: process.terminationStatus))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: HermesRunnerError.launchFailed(error.localizedDescription))
            }
        }
    }
}

private extension Data {
    static func + (lhs: Data, rhs: Data) -> Data {
        var data = lhs
        data.append(rhs)
        return data
    }
}
