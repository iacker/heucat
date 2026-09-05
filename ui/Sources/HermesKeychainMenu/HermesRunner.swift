import Foundation

struct CommandResult {
    let output: String
    let exitCode: Int32
}

enum HermesRunnerError: LocalizedError {
    case binaryNotFound
    case launchFailed(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "Hermes CLI not found. Set its path in Settings."
        case .launchFailed(let message):
            return "Could not launch Hermes: \(message)"
        case .timedOut:
            return "Hermes command timed out."
        }
    }
}

private final class CompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false

    func once(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return }
        completed = true
        body()
    }
}

private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

struct HermesRunner {
    let binaryPath: String
    let hermesHome: String

    func run(
        _ arguments: [String],
        stdinData: Data? = nil,
        timeout: TimeInterval = 120
    ) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            let stdin = Pipe()
            let out = OutputBuffer()
            let err = OutputBuffer()
            let gate = CompletionGate()

            guard FileManager.default.isExecutableFile(atPath: binaryPath) else {
                continuation.resume(throwing: HermesRunnerError.binaryNotFound)
                return
            }

            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = arguments
            process.standardOutput = stdout
            process.standardError = stderr
            process.standardInput = stdin

            let parentEnvironment = ProcessInfo.processInfo.environment
            var environment: [String: String] = [:]
            for key in ["PATH", "HOME", "TMPDIR", "LANG", "LC_ALL"] {
                environment[key] = parentEnvironment[key]
            }
            environment["HERMES_HOME"] = NSString(string: hermesHome).expandingTildeInPath
            environment["NO_COLOR"] = "1"
            process.environment = environment

            let readers = DispatchGroup()
            let deadline = DispatchWorkItem {
                gate.once {
                    if process.isRunning {
                        process.terminate()
                        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                        }
                    }
                    continuation.resume(throwing: HermesRunnerError.timedOut)
                }
            }
            process.terminationHandler = { process in
                readers.notify(queue: .global()) {
                    deadline.cancel()
                    gate.once {
                        let merged = String(decoding: out.snapshot() + err.snapshot(), as: UTF8.self)
                        continuation.resume(returning: CommandResult(
                            output: merged, exitCode: process.terminationStatus
                        ))
                    }
                }
            }

            // One reader owns each pipe through EOF; no termination/read race.
            readers.enter()
            readers.enter()
            do {
                try process.run()
                for (pipe, buffer) in [(stdout, out), (stderr, err)] {
                    DispatchQueue.global().async {
                        defer { readers.leave() }
                        while true {
                            let chunk = pipe.fileHandleForReading.availableData
                            if chunk.isEmpty { break }
                            buffer.append(chunk)
                        }
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
                DispatchQueue.global().async {
                    defer { try? stdin.fileHandleForWriting.close() }
                    if let stdinData { try? stdin.fileHandleForWriting.write(contentsOf: stdinData) }
                }
            } catch {
                readers.leave()
                readers.leave()
                deadline.cancel()
                gate.once {
                    continuation.resume(throwing: HermesRunnerError.launchFailed(error.localizedDescription))
                }
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
