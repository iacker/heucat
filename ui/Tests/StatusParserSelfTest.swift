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

        // chthonios wants the root, the keychain CLI wants the profile dir
        precondition(chthoniosHome(from: "~/.hermes/profiles/ares") == "~/.hermes")
        precondition(chthoniosHome(from: "/Users/x/.hermes/profiles/redteam") == "/Users/x/.hermes")
        precondition(chthoniosHome(from: "~/.hermes") == "~/.hermes")  // already root

        // chthonios status: the real table, a header rule then data rows.
        // Copied verbatim from `chthonios status` (NO_COLOR=1), glyphs included
        // — the previous fixture invented lowercase states and hid a real bug.
        let real = """
         PROFILE        STATE     BACKEND    INTEGRITY  SEALED AT
        ──────────────────────────────────────────────────────────────
         default        ◈ unmanaged
         ares           ◈ unmanaged
         redteam        ◇ OPEN     fido2-hmac ✓ ok        2026-08-22T20:46:14
         vault          ◆ SEALED   passphrase ✓ ok        2026-08-28T02:15:21
        """
        let rows = ChthoniosStatus.rows(real, ok: true)
        precondition(rows.count == 4, "expected 4 profiles, got \(rows.count)")
        precondition(rows.map(\.name) == ["default", "ares", "redteam", "vault"])
        precondition(rows[0].state == .unmanaged)
        precondition(rows[0].backend.isEmpty)
        precondition(rows[2].state == .open)
        precondition(rows[2].backend == "fido2-hmac")
        precondition(rows[2].needsHardwareKey, "fido2 rows must ask for a PIN")
        precondition(rows[3].state == .sealed)
        precondition(!rows[3].needsHardwareKey, "passphrase rows must not ask for a PIN")
        precondition(rows[3].sealedAt == "2026-08-28T02:15:21")

        precondition(ChthoniosStatus.parse(real, ok: true) == .sealed(["vault"]))

        let unmanaged = """
         PROFILE        STATE     BACKEND    INTEGRITY  SEALED AT
        ──────────────────────────────────────────────────────────────
         default        ◈ unmanaged
        """
        precondition(ChthoniosStatus.parse(unmanaged, ok: true) == .unmanaged(["default"]))
        precondition(ChthoniosStatus.parse("", ok: false) == .failed)
        precondition(ChthoniosStatus.rows("", ok: false).isEmpty)
        precondition(ChthoniosStatus.parse("no table here", ok: true) == ChthoniosStatus.none)

        print("StatusParser self-test: OK")
    }
}
