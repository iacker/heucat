import Foundation

@main
struct HermesRunnerSelfTest {
    static func main() async throws {
        let echo = HermesRunner(binaryPath: "/bin/sh", hermesHome: "/tmp/hermes-runner-test")
        let result = try await echo.run(["-c", "i=0; while [ $i -lt 20000 ]; do printf x; i=$((i+1)); done; printf err >&2"])
        precondition(result.exitCode == 0)
        precondition(result.output.count == 20_003)
        precondition(result.output.hasSuffix("err"))

        for _ in 0..<20 {
            let fast = try await echo.run(["-c", "printf last-byte; printf error-byte >&2"])
            precondition(fast.output == "last-byteerror-byte")
        }
        let bulk = try await echo.run(["-c", "dd if=/dev/zero bs=65536 count=16 2>/dev/null; dd if=/dev/zero bs=65536 count=16 1>&2 2>/dev/null"])
        precondition(bulk.output.utf8.count == 2_097_152)

        let sleeper = HermesRunner(binaryPath: "/bin/sleep", hermesHome: "/tmp/hermes-runner-test")
        do {
            _ = try await sleeper.run(["5"], timeout: 0.05)
            preconditionFailure("timeout did not fire")
        } catch HermesRunnerError.timedOut {
            print("HermesRunner self-test: OK")
        }
    }
}
