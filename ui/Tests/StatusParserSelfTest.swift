import Foundation

@main
struct StatusParserSelfTest {
    static func main() {
        let output = """
          HashiCorp Vault: this startup warning is not a secret row
          Apple Keychain / Secure Enclave: another startup warning
        source enabled : True
        helper binary  : /tmp/helper
        enclave key    : present
        configured     : 3 secret(s)
          OPENROUTER_API_KEY           plain    readable
          GITHUB_TOKEN                 enclave  unlocked
          BRAVE_API_KEY                enclave  locked (no unlock session)
        """
        let status = KeychainStatus.parse(output)
        precondition(status.sourceEnabled)
        precondition(status.helperPath == "/tmp/helper")
        precondition(status.enclaveKeyPresent)
        precondition(status.configuredCount == 3)
        precondition(status.secrets.count == 3)
        precondition(status.secrets[0].isUnlocked)
        precondition(status.secrets[1].isUnlocked)
        precondition(!status.secrets[2].isUnlocked)
        precondition(status.secrets[2].state == "locked (no unlock session)")

        // chthonios status: the real table, a header rule then data rows
        let unmanaged = """
        PROFILE        STATE     BACKEND    INTEGRITY  SEALED AT
        ──────────────────────────────────────────────
         default        ◈ unmanaged
        """
        precondition(ChthoniosStatus.parse(unmanaged, ok: true) == .unmanaged(["default"]))

        let sealed = """
        PROFILE        STATE     BACKEND    INTEGRITY  SEALED AT
        ──────────────────────────────────────────────
         redteam        ◈ sealed    age        ok         2026-08-28
         default        ◈ unmanaged
        """
        precondition(ChthoniosStatus.parse(sealed, ok: true) == .sealed(["redteam"]))
        precondition(ChthoniosStatus.parse("", ok: false) == .failed)
        precondition(ChthoniosStatus.parse("no table here", ok: true) == ChthoniosStatus.none)

        print("StatusParser self-test: OK")
    }
}
