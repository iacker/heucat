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
        print("StatusParser self-test: OK")
    }
}
