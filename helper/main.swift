// hermes-keychain-helper — Secure Enclave biometric-gated secret store for Hermes.
//
// Why not the Keychain ACL route: biometric ACLs (SecAccessControl) require the
// Data Protection keychain, which requires an application-identifier entitlement
// that ad-hoc signed CLI binaries cannot hold (errSecMissingEntitlement -34018).
// Instead we use the age-plugin-se model: a CryptoKit Secure Enclave P256 key
// (biometry-gated) whose sealed representation is caller-managed. The private
// key NEVER leaves the Secure Enclave; the key blob and secret ciphertexts are
// plain files only THIS device's enclave (+ a live fingerprint) can use.
//
// Crypto: SE P256 KeyAgreement (ECDH, ephemeral pub key per encryption)
//         -> HKDF-SHA256 -> ChaChaPoly AEAD. Encrypt needs NO Touch ID
//         (public key only); decrypt needs ONE Touch ID for the whole batch.
//
// Auth policy: by default the key requires USER PRESENCE (Touch ID when the
// sensor is reachable, otherwise the login password / Apple Watch) so a
// docked MacBook with the lid closed still works. `keygen --strict-biometry`
// binds the key to the currently enrolled fingerprints only.
//
// Commands (value bytes on stdin/stdout; blobs are base64 on argv/stdout):
//   check                        report enclave + biometry availability
//   keygen [--strict-biometry]   create gated SE key -> key blob b64
//   pubkey  <keyblob-b64>        print the key's public part (b64, no touch)
//   encrypt <pubkey-b64>         stdin plaintext -> ciphertext b64 (no touch)
//   decrypt <keyblob-b64> <ct-b64> [<ct-b64>...]
//                                ONE Touch ID -> JSON array of b64 plaintexts
//
// Exit codes: 0 ok, 1 crypto/enclave error, 2 usage, 3 enclave/biometry
//             unavailable, 5 user cancelled.

import CryptoKit
import Foundation
import LocalAuthentication

func stderrPrint(_ msg: String) {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
}

func die(_ msg: String, _ code: Int32) -> Never {
    stderrPrint(msg)
    exit(code)
}

func requireEnclave() {
    guard SecureEnclave.isAvailable else {
        die("Secure Enclave unavailable on this machine", 3)
    }
}

func makeAccessControl(strictBiometry: Bool) -> SecAccessControl {
    var err: Unmanaged<CFError>?
    let flags: SecAccessControlCreateFlags =
        strictBiometry ? [.privateKeyUsage, .biometryCurrentSet]
                       : [.privateKeyUsage, .userPresence]
    guard let ac = SecAccessControlCreateWithFlags(
        kCFAllocatorDefault,
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        flags,
        &err
    ) else {
        die("access-control creation failed: \(err!.takeRetainedValue())", 1)
    }
    return ac
}

/// One evaluated LAContext shared across a decrypt batch: one touch, many secrets.
func evaluatedContext(reason: String) -> LAContext {
    let ctx = LAContext()
    var err: NSError?
    // Prefer biometrics; fall back to the general policy (password / Watch)
    // when the sensor is unreachable (clamshell mode, external keyboard).
    var policy = LAPolicy.deviceOwnerAuthenticationWithBiometrics
    if !ctx.canEvaluatePolicy(policy, error: &err) {
        policy = .deviceOwnerAuthentication
        guard ctx.canEvaluatePolicy(policy, error: &err) else {
            die("no authentication method available: \(err?.localizedDescription ?? "unknown")", 3)
        }
    }
    let sem = DispatchSemaphore(value: 0)
    var ok = false
    var evalError: Error?
    ctx.evaluatePolicy(policy,
                       localizedReason: reason) { success, error in
        ok = success
        evalError = error
        sem.signal()
    }
    sem.wait()
    if !ok {
        if let laErr = evalError as? LAError,
           laErr.code == .userCancel || laErr.code == .appCancel || laErr.code == .systemCancel {
            die("user cancelled biometric prompt", 5)
        }
        die("biometric evaluation failed: \(evalError?.localizedDescription ?? "unknown")", 1)
    }
    return ctx
}

func b64d(_ text: String, what: String) -> Data {
    guard let data = Data(base64Encoded: text) else { die("invalid base64 for \(what)", 2) }
    return data
}

let hkdfSalt = "hermes-keychain-secretsource-v1".data(using: .utf8)!

/// ECDH(shared) + ephemeral pub -> symmetric key. Bound to both key halves.
func symmetricKey(shared: SharedSecret, ephemeralPub: Data) -> SymmetricKey {
    shared.hkdfDerivedSymmetricKey(
        using: SHA256.self, salt: hkdfSalt,
        sharedInfo: ephemeralPub, outputByteCount: 32
    )
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    die("usage: \(args.first ?? "helper") check|keygen|pubkey|encrypt|decrypt ...", 2)
}

switch args[1] {
case "check":
    let ctx = LAContext()
    var err: NSError?
    let bio = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
    var err2: NSError?
    let anyAuth = ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err2)
    print("secure_enclave=\(SecureEnclave.isAvailable) biometry=\(bio) user_auth=\(anyAuth)")
    if !SecureEnclave.isAvailable || !anyAuth { exit(3) }

case "keygen":
    requireEnclave()
    let strict = args.contains("--strict-biometry")
    if strict {
        let probe = LAContext()
        var bioErr: NSError?
        guard probe.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &bioErr) else {
            die("--strict-biometry requires a reachable, enrolled sensor: \(bioErr?.localizedDescription ?? "unknown")", 3)
        }
    }
    do {
        let key = try SecureEnclave.P256.KeyAgreement.PrivateKey(
            accessControl: makeAccessControl(strictBiometry: strict)
        )
        print(key.dataRepresentation.base64EncodedString())
    } catch {
        die("keygen failed: \(error.localizedDescription)", 1)
    }

case "pubkey":
    guard args.count == 3 else { die("pubkey needs <keyblob-b64>", 2) }
    requireEnclave()
    do {
        // Loading the blob does not require biometry; only ECDH does.
        let key = try SecureEnclave.P256.KeyAgreement.PrivateKey(
            dataRepresentation: b64d(args[2], what: "key blob")
        )
        print(key.publicKey.rawRepresentation.base64EncodedString())
    } catch {
        die("invalid key blob: \(error.localizedDescription)", 1)
    }

case "encrypt":
    guard args.count == 3 else { die("encrypt needs <pubkey-b64>", 2) }
    var plaintext = FileHandle.standardInput.readDataToEndOfFile()
    if plaintext.last == 0x0A { plaintext.removeLast() }
    if plaintext.last == 0x0D { plaintext.removeLast() }
    guard !plaintext.isEmpty else { die("refusing to encrypt an empty value", 2) }
    do {
        let recipient = try P256.KeyAgreement.PublicKey(
            rawRepresentation: b64d(args[2], what: "public key")
        )
        let ephemeral = P256.KeyAgreement.PrivateKey()
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: recipient)
        let ephPub = ephemeral.publicKey.rawRepresentation
        let sealed = try ChaChaPoly.seal(
            plaintext, using: symmetricKey(shared: shared, ephemeralPub: ephPub)
        )
        // Blob layout: ephemeral pub (65 raw bytes) || ChaChaPoly combined.
        var blob = Data()
        blob.append(ephPub)
        blob.append(sealed.combined)
        print(blob.base64EncodedString())
    } catch {
        die("encrypt failed: \(error.localizedDescription)", 1)
    }

case "decrypt":
    guard args.count >= 4 else { die("decrypt needs <keyblob-b64> <ct-b64> [...]", 2) }
    requireEnclave()
    let ctx = evaluatedContext(
        reason: "unlock \(args.count - 3) Hermes secret\(args.count - 3 == 1 ? "" : "s")"
    )
    do {
        let key = try SecureEnclave.P256.KeyAgreement.PrivateKey(
            dataRepresentation: b64d(args[2], what: "key blob"),
            authenticationContext: ctx
        )
        var out: [String] = []
        for (idx, ctB64) in args[3...].enumerated() {
            let blob = b64d(ctB64, what: "ciphertext #\(idx)")
            let pubLen = 64  // P256 rawRepresentation: x||y, no 0x04 prefix
            guard blob.count > pubLen + 16 else { die("ciphertext #\(idx) too short", 2) }
            let ephPub = blob.prefix(pubLen)
            let combined = blob.dropFirst(pubLen)
            let sender = try P256.KeyAgreement.PublicKey(rawRepresentation: ephPub)
            let shared = try key.sharedSecretFromKeyAgreement(with: sender)
            let sealed = try ChaChaPoly.SealedBox(combined: combined)
            let plain = try ChaChaPoly.open(
                sealed, using: symmetricKey(shared: shared, ephemeralPub: Data(ephPub))
            )
            out.append(plain.base64EncodedString())
        }
        let json = try JSONSerialization.data(withJSONObject: out)
        FileHandle.standardOutput.write(json)
        FileHandle.standardOutput.write("\n".data(using: .utf8)!)
    } catch {
        let desc = error.localizedDescription
        if desc.localizedCaseInsensitiveContains("cancel") {
            die("user cancelled biometric prompt", 5)
        }
        die("decrypt failed: \(desc)", 1)
    }

default:
    die("unknown command: \(args[1])", 2)
}
