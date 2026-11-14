import AppKit
import Foundation

struct Secret: Identifiable {
    let name: String, mode: String, state: String
    var id: String { name }
    var enclave: Bool { mode == "enclave" }
    var open: Bool { state.hasPrefix("unlocked") || state == "readable" }
    var broken: Bool { state.hasPrefix("UNREADABLE") || state.hasPrefix("NO CIPHERTEXT") }
}

enum SealState { case clear, sealed, open, unmanaged }

struct SealRow: Identifiable {
    let name: String, state: SealState, fido: Bool
    var id: String { name }
}

struct Coffre: Identifiable {
    let url: URL, size: Int64, date: Date
    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var isAge: Bool { url.pathExtension == "age" }
    var isMemory: Bool { name.hasPrefix("hindsight-") }
    /// `hindsight-<bank>-<yyyyMMdd-HHmm>.zip.chthonios` -> `<bank>`
    var bank: String? {
        guard isMemory, let r = name.range(of: ".zip.") else { return nil }
        let core = name[name.index(name.startIndex, offsetBy: 10)..<r.lowerBound]
        return core.count > 14 ? String(core.dropLast(14)) : nil
    }
}

enum Lock: String, CaseIterable { case phrase = "Phrase secrète", yubikey = "YubiKey" }

@MainActor
final class Model: ObservableObject {
    enum Tab: String, CaseIterable { case keys = "Clés", profiles = "Profils", vaults = "Coffres" }

    @Published var tab: Tab = .keys
    @Published var hermesProfiles: [String] = []
    @Published var keyProfile = UserDefaults.standard.string(forKey: "keyProfile") ?? "default" {
        didSet { UserDefaults.standard.set(keyProfile, forKey: "keyProfile"); Task { await refreshKeys() } }
    }
    @Published var secrets: [Secret] = []
    @Published var seals: [SealRow] = []
    @Published var banks: [String] = []
    @Published var coffres: [Coffre] = []
    @Published var busy: String?
    @Published var note: (text: String, ok: Bool)?
    @Published var lockOnScreenLock = UserDefaults.standard.object(forKey: "lockOnScreenLock") as? Bool ?? true {
        didSet { UserDefaults.standard.set(lockOnScreenLock, forKey: "lockOnScreenLock") }
    }

    init() {
        // Screen locks -> close every profile's Touch ID sessions.
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.lockAllSessions() }
        }
    }

    func lockAllSessions() async {
        guard lockOnScreenLock else { return }
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(atPath: root + "/profiles")) ?? []
        for h in [root] + dirs.map({ root + "/profiles/" + $0 }) where fm.fileExists(atPath: h + "/keychain/enclave-key.b64") {
            _ = await Shell.run(Shell.python, [Shell.heucatCLI, "lock"], hermesHome: h, timeout: 20)
        }
    }

    let root = Shell.expand("~/.hermes")
    let coffreDir = Shell.expand("~/Coffres")
    private let hindsight = "http://127.0.0.1:8888/v1/default"

    func home(_ profile: String) -> String { profile == "default" ? root : root + "/profiles/" + profile }

    // MARK: refresh

    func refresh() async {
        let dirs = (try? FileManager.default.contentsOfDirectory(atPath: root + "/profiles")) ?? []
        hermesProfiles = ["default"] + dirs.filter { !$0.hasPrefix(".") && $0 != "default" }.sorted()
        async let k: Void = refreshKeys()
        async let s: Void = refreshSeals()
        _ = await (k, s)
        refreshCoffres()
    }

    func refreshKeys() async {
        guard FileManager.default.fileExists(atPath: Shell.heucatCLI) else {
            secrets = []; note = ("Plugin keychain introuvable dans ~/.hermes/plugins", false); return
        }
        let r = await Shell.run(Shell.python, [Shell.heucatCLI, "status"], hermesHome: home(keyProfile))
        secrets = r.out.split(whereSeparator: \.isNewline).compactMap { line in
            guard line.hasPrefix("  ") else { return nil }
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, ["plain", "enclave"].contains(String(parts[1])) else { return nil }
            return Secret(name: String(parts[0]), mode: String(parts[1]), state: String(parts[2]))
        }
    }

    func refreshSeals() async {
        guard let bin = Shell.chthonios else { seals = []; return }
        let r = await Shell.run(bin, ["status"], hermesHome: root)
        var rows: [SealRow] = []
        var body = false
        for line in r.out.split(whereSeparator: \.isNewline) {
            if line.contains("─") { body = true; continue }
            guard body, let name = line.split(separator: " ").first else { continue }
            let state: SealState = line.contains("unmanaged") ? .unmanaged
                : line.contains("OPEN") ? .open : line.contains("SEALED") ? .sealed : .clear
            rows.append(SealRow(name: String(name), state: state, fido: line.contains("fido")))
        }
        seals = rows
    }

    func refreshCoffres() {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: URL(fileURLWithPath: coffreDir),
                                                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []
        coffres = urls.filter { ["chthonios", "age"].contains($0.pathExtension) }.map { u in
            let v = try? u.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return Coffre(url: u, size: Int64(v?.fileSize ?? 0), date: v?.contentModificationDate ?? .distantPast)
        }.sorted { $0.date > $1.date }
    }

    func refreshBanks() async {
        guard let (data, _) = try? await URLSession.shared.data(from: URL(string: hindsight + "/banks")!),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = obj["banks"] as? [[String: Any]] else { banks = []; return }
        banks = list.compactMap { $0["bank_id"] as? String }.sorted()
    }

    // MARK: YubiKey

    /// Profile dir holding an enrolled YubiKey recipient (non-secret), if any.
    var fidoProfileDir: String? {
        ([root] + hermesProfiles.filter { $0 != "default" }.map(home))
            .first { FileManager.default.fileExists(atPath: $0 + "/.chthonios.recipient") }
    }
    func fidoEnrolled(_ profile: String) -> Bool {
        FileManager.default.fileExists(atPath: home(profile) + "/.chthonios.recipient")
    }

    // MARK: actions

    private func act(_ label: String, _ work: () async -> (Bool, String)) async {
        busy = label
        let (ok, text) = await work()
        busy = nil
        note = (text, ok)
        await refresh()
    }

    private func cli(_ args: [String], home: String, stdin: String? = nil, timeout: TimeInterval = 120) async -> (Bool, String) {
        let r = await Shell.run(Shell.python, [Shell.heucatCLI] + args, hermesHome: home, stdin: stdin, timeout: timeout)
        return (r.ok, r.summary)
    }

    private func chth(_ args: [String], stdin: String? = nil, timeout: TimeInterval = 300) async -> RunResult {
        guard let bin = Shell.chthonios else { return RunResult(out: "chthonios introuvable", code: -1) }
        return await Shell.run(bin, args, hermesHome: root, stdin: stdin, timeout: timeout)
    }

    // Keys
    func unlockKeys() async { await act("Touch ID…") { await cli(["unlock"], home: home(keyProfile)) } }
    func lockKeys() async { await act("Verrouillage…") { await cli(["lock"], home: home(keyProfile)) } }
    func store(_ name: String, _ value: String, enclave: Bool) async {
        await act("Enregistrement…") {
            await cli(["store", name, "--stdin"] + (enclave ? ["--enclave"] : []), home: home(keyProfile), stdin: value)
        }
    }
    func delete(_ name: String) async { await act("Suppression…") { await cli(["delete", name], home: home(keyProfile)) } }

    // Profiles
    func seal(_ p: String, secret: String, fido: Bool) async {
        await act("Scellement de \(p)…") {
            let r = await chth(["seal", p] + (fido ? ["--fido2"] : []), stdin: fido ? nil : "\(secret)\n\(secret)\n")
            return (r.ok, r.summary)
        }
    }
    func unseal(_ p: String, secret: String, fido: Bool) async {
        await act(fido ? "Touche ta YubiKey…" : "Ouverture de \(p)…") {
            let r = await chth(["unseal", p] + (fido ? ["--pin-stdin"] : []), stdin: secret + "\n")
            return (r.ok, r.summary)
        }
    }
    func relock(_ p: String) async { await act("Fermeture…") { let r = await chth(["lock", p]); return (r.ok, r.summary) } }

    // Vaults
    private var stamp: String { let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmm"; return f.string(from: Date()) }

    private func ensureCoffreDir() {
        try? FileManager.default.createDirectory(atPath: coffreDir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
    }

    private func packArgs(_ path: String, lock: Lock, remove: Bool) -> [String]? {
        var a = ["pack", path] + (remove ? ["--remove"] : [])
        if lock == .yubikey {
            guard let dir = fidoProfileDir else { return nil }
            a += ["--fido2", "--recipient-file", dir + "/.chthonios.recipient"]
        }
        return a
    }

    func sealFolder(_ url: URL, lock: Lock, secret: String) async {
        await act("Chiffrement de \(url.lastPathComponent)…") {
            ensureCoffreDir()
            guard let args = packArgs(url.path, lock: lock, remove: false) else { return (false, "Aucune YubiKey enrôlée") }
            let r = await chth(args, stdin: lock == .phrase ? "\(secret)\n\(secret)\n" : nil, timeout: 3600)
            guard r.ok, let out = r.out.components(separatedBy: "→").last?
                .split(whereSeparator: \.isNewline).first?.trimmingCharacters(in: .whitespaces) else { return (false, r.summary) }
            let src = URL(fileURLWithPath: out, relativeTo: url.deletingLastPathComponent())
            let ext = src.lastPathComponent.dropFirst(url.lastPathComponent.count)   // ".tar.chthonios" …
            let dst = URL(fileURLWithPath: coffreDir + "/\(url.lastPathComponent)-\(stamp)\(ext)")
            do { try FileManager.default.moveItem(at: src, to: dst) } catch { return (false, error.localizedDescription) }
            return (true, "Coffre créé : \(dst.lastPathComponent). L'original est intact.")
        }
    }

    func sealBank(_ bank: String, lock: Lock, secret: String) async {
        await act("Export de la mémoire \(bank)…") {
            ensureCoffreDir()
            guard let op = await post("/banks/\(bank)/transfer/export")?["operation_id"] as? String
            else { return (false, "Hindsight injoignable (127.0.0.1:8888)") }
            guard let meta = await waitOp(bank, op)?["result_metadata"] as? [String: Any],
                  let dl = meta["download_url"] as? String,
                  let (data, _) = try? await URLSession.shared.data(from: URL(string: "http://127.0.0.1:8888" + dl)!)
            else { return (false, "Export Hindsight échoué") }
            _ = await request("/banks/\(bank)/operations/\(op)/delete", method: "DELETE")   // drop server-side copy
            let zip = coffreDir + "/hindsight-\(bank)-\(stamp).zip"
            FileManager.default.createFile(atPath: zip, contents: data, attributes: [.posixPermissions: 0o600])
            guard let args = packArgs(zip, lock: lock, remove: true) else {
                try? FileManager.default.removeItem(atPath: zip); return (false, "Aucune YubiKey enrôlée")
            }
            let r = await chth(args, stdin: lock == .phrase ? "\(secret)\n\(secret)\n" : nil)
            if !r.ok { try? FileManager.default.removeItem(atPath: zip) }
            return (r.ok, r.ok ? "Mémoire \(bank) scellée (\(data.count / 1_000_000) Mo). La banque vivante est intacte." : r.summary)
        }
    }

    func open(_ c: Coffre, secret: String) async {
        await act("Ouverture…") {
            let dest = coffreDir + "/ouverts"
            try? FileManager.default.createDirectory(atPath: dest, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
            let r = await chth(["unpack", c.url.path, "--dest", dest], stdin: secret + "\n", timeout: 3600)
            if r.ok { NSWorkspace.shared.open(URL(fileURLWithPath: dest)) }
            return (r.ok, r.ok ? "Ouvert dans ~/Coffres/ouverts" : r.summary)
        }
    }

    func restore(_ c: Coffre, secret: String) async {
        guard let bank = c.bank else { return }
        await act("Restauration de \(bank)…") {
            let tmp = coffreDir + "/.restore-\(UUID().uuidString.prefix(8))"
            try? FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(atPath: tmp) }
            let r = await chth(["unpack", c.url.path, "--dest", tmp], stdin: secret + "\n")
            guard r.ok, let zip = (try? FileManager.default.contentsOfDirectory(atPath: tmp))?.first,
                  let data = FileManager.default.contents(atPath: tmp + "/" + zip) else { return (false, r.summary) }
            let target = "\(bank)-restaure-\(stamp)".lowercased()
            guard let op = await upload("/banks/\(bank)/transfer/import?mode=restore&target_bank_id=\(target)", data)?["operation_id"] as? String,
                  (await waitOp(bank, op, limit: 600)?["status"] as? String) == "completed"
            else { return (false, "Import Hindsight échoué") }
            return (true, "Restaurée dans la banque « \(target) »")
        }
    }

    func yubikeyOpenCommand(_ c: Coffre) -> String {
        let id = (fidoProfileDir ?? "~/.hermes/profiles/<profil>") + "/.chthonios.identity"
        return "chthonios unpack '\(c.url.path)' --identity '\(id)' --dest ~/Coffres/ouverts"
    }

    // MARK: Hindsight HTTP

    private func request(_ path: String, method: String, body: Data? = nil, type: String? = nil) async -> [String: Any]? {
        var req = URLRequest(url: URL(string: hindsight + path)!)
        req.httpMethod = method
        req.httpBody = body
        if let type { req.setValue(type, forHTTPHeaderField: "Content-Type") }
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
    private func post(_ path: String) async -> [String: Any]? { await request(path, method: "POST") }

    private func upload(_ path: String, _ file: Data) async -> [String: Any]? {
        let b = "heucat-\(UUID().uuidString)"
        var body = Data("--\(b)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"bank.zip\"\r\nContent-Type: application/zip\r\n\r\n".utf8)
        body.append(file)
        body.append(Data("\r\n--\(b)--\r\n".utf8))
        return await request(path, method: "POST", body: body, type: "multipart/form-data; boundary=\(b)")
    }

    private func waitOp(_ bank: String, _ op: String, limit: Int = 300) async -> [String: Any]? {
        for _ in 0..<limit {
            let r = await request("/banks/\(bank)/operations/\(op)", method: "GET")
            switch r?["status"] as? String {
            case "completed": return r
            case "failed", "cancelled": return nil
            default: try? await Task.sleep(for: .seconds(1))
            }
        }
        return nil
    }
}
