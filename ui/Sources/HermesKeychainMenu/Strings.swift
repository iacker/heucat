import Foundation
import SwiftUI

/// UI language. Persisted, and switchable live from Settings.
///
/// ponytail: a plain dictionary rather than Localizable.strings. SwiftPM
/// bundles cannot switch language at runtime without relaunching the app, and
/// the whole point here is a live picker. Move to .strings only if a third
/// language and a translator workflow ever show up.
enum Language: String, CaseIterable, Identifiable {
    case french = "fr"
    case english = "en"

    var id: String { rawValue }

    /// Shown in the picker, each in its own language.
    var label: String {
        switch self {
        case .french: "Français"
        case .english: "English"
        }
    }
}

@MainActor
final class Loc: ObservableObject {
    static let shared = Loc()

    @AppStorage("uiLanguage") private var stored = Language.french.rawValue {
        didSet { objectWillChange.send() }
    }

    var language: Language {
        get { Language(rawValue: stored) ?? .french }
        set { stored = newValue.rawValue }
    }

    /// Look up a key. Returns the key itself when a translation is missing, so
    /// a forgotten string shows up loudly instead of rendering blank.
    func callAsFunction(_ key: String) -> String {
        if language == .english { return Self.english[key] ?? key }
        return Self.french[key] ?? Self.english[key] ?? key
    }

    // MARK: Tables

    static let english: [String: String] = [
        // Navigation
        "nav.overview": "Overview",
        "nav.secrets": "Secrets",
        "nav.sessions": "Sessions",
        "nav.profiles": "Sealed Profiles",
        "nav.howitworks": "How it works",
        "nav.diagnostics": "Diagnostics",

        // Chrome
        "app.title": "HEUCAT Keychain",
        "app.wordmark": "HEUCAT KEYCHAIN",
        "app.refresh": "Refresh",
        "app.refresh.help": "Refresh protection status",
        "app.settings": "Settings",
        "app.quit": "Quit",
        "app.addSecretMenu": "Add Secret…",
        "app.agent": "Hermes Agent",
        "app.allSecure": "All systems secure",
        "app.needsAttention": "Needs attention",
        "app.notChecked": "Not checked yet",
        "app.verified": "Verified",

        // Overview
        "overview.eyebrow": "Runtime secret source",
        "overview.motto": "Between worlds,\nshe keeps the keys.",
        "overview.viewSecrets": "View secrets",
        "overview.addSecret": "Add secret",
        "overview.keyOverview": "Key overview",
        "overview.totalKeys": "Total keys",
        "overview.keychain": "Keychain",
        "overview.enclave": "Enclave",
        "overview.protection": "Protection",
        "overview.agentStatus": "Agent status",
        "overview.hermesRuntime": "Hermes runtime",
        "overview.appleStack": "Apple Keychain + Secure Enclave",
        "overview.hardwareBacked": "Hardware-backed. Values never leave this Mac.",
        "overview.quickActions": "Quick actions",

        // Stat tiles
        "stat.secrets": "Secrets",
        "stat.secrets.caption": "under management",
        "stat.enclave": "Enclave",
        "stat.enclave.caption": "hardware-bound",
        "stat.readable": "Readable",
        "stat.readable.open": "session open",
        "stat.readable.closed": "session closed",
        "stat.health": "Health",
        "stat.health.on": "source active",
        "stat.health.off": "source off",

        // Secrets
        "secrets.title": "Secrets",
        "secrets.subtitle": "References are managed here. Values are never revealed.",
        "secrets.search": "Search",
        "secrets.empty.title": "No secrets yet",
        "secrets.empty.body": "Add a credential and the plaintext copy stops being the source of truth.",
        "secrets.copyName": "Copy variable name",
        "secrets.updateValue": "Update value…",
        "secrets.migrate": "Migrate to Secure Enclave",
        "secrets.test": "Test connection",
        "secrets.remove": "Remove",
        "secrets.available": "Available",
        "secrets.modeEnclave": "Secure Enclave",
        "secrets.modeKeychain": "Apple Keychain",
        "secrets.confirmRemove": "Remove this secret?",
        "secrets.cancel": "Cancel",

        // Add / update sheet
        "add.title": "Add a secret",
        "add.title.update": "Update a secret",
        "add.subtitle": "The value is sent directly to protected storage and never displayed again.",
        "add.identity": "Identity",
        "add.envVar": "Environment variable",
        "add.nameRule": "Use letters, numbers and underscores; start with a letter or underscore.",
        "add.protection": "Storage mode",
        "add.enclaveHint": "Recommended. Hardware-bound encryption with Touch ID or macOS authentication.",
        "add.keychainHint": "Stored as a generic password in the macOS login Keychain.",
        "add.value": "Secret value",
        "add.valueField": "Value",
        "add.confirm": "Confirm value",
        "add.mismatch": "Values do not match.",
        "add.advanced": "Advanced options",
        "add.service": "Service (optional)",
        "add.account": "Account (optional)",
        "add.noLogs": "Values never enter command arguments or logs",
        "add.save": "Save securely",
        "add.update": "Update value",

        // Sessions
        "sessions.title": "Sessions",
        "sessions.subtitle": "Temporary access to Secure Enclave secrets.",
        "sessions.headline": "Authenticate once, work securely",
        "sessions.body": "Touch ID opens a time-limited session covering every Enclave secret at once. Hermes startup stays silent, so gateway and cron processes never block on a prompt.",
        "sessions.unlock": "Unlock with Touch ID",
        "sessions.lockAll": "Lock all sessions",
        "sessions.none": "No Enclave secrets are stored yet, so there is nothing to unlock. Add one from the Secrets page and pick Secure Enclave.",
        "sessions.tradeoff": "While a session is open the values sit in TTL-bounded macOS Keychain records, readable by processes running as you. Lock them when you are done rather than relying on the timeout.",

        // How it works
        "how.title": "How it works",
        "how.subtitle": "What actually protects your keys, from silicon up.",
        "how.step": "Step",
        "how.1.title": "A key is born inside the Enclave",
        "how.1.body": "The first time you store an Enclave secret, a P256 private key is generated inside the Secure Enclave, the isolated chip on Apple Silicon. That key can never be exported. Not by you, not by malware, not by macOS. Only its public half comes out.",
        "how.2.title": "Your secret is sealed with ChaChaPoly",
        "how.2.body": "The value is encrypted with the public key using ECDH plus ChaChaPoly. Because encryption only needs the public half, adding a secret never asks for Touch ID. The ciphertext lands in a 0600 file under your profile, useless on any other Mac.",
        "how.3.title": "Touch ID unlocks the whole batch at once",
        "how.3.body": "Decryption is the only step that needs the private key, and the Enclave releases it only after a live human authentication. One fingerprint opens every Enclave secret together, then caches them as short-lived session records.",
        "how.4.title": "Hermes reads them without ever prompting",
        "how.4.body": "At startup Hermes reads only those session records. A locked secret fails fast instead of hanging, so gateway and cron processes never block waiting for a fingerprint no one is there to give.",
        "how.tradeoff.title": "The honest tradeoff",
        "how.tradeoff.body": "While a session is open, the plaintext sits in TTL-bounded records readable by anything running as you. That is the price of never prompting. Lock the session when you are done, or keep the TTL short.",

        // Sealed profiles
        "profiles.title": "Sealed Profiles",
        "profiles.subtitle": "Chthonios seals an entire profile at rest.",
        "profiles.separate": "The two crypto engines stay separate on purpose. Only this dashboard is shared, so neither system has to pretend to be the other. Unsealing is done by you in a terminal, never by this app.",
        "profiles.notInstalled": "Chthonios is not installed",

        // Diagnostics
        "diag.title": "Diagnostics",
        "diag.subtitle": "What the app knows about this machine.",
        "diag.hermesCli": "Hermes CLI",
        "diag.hermesHome": "Hermes home",
        "diag.chthoniosCli": "Chthonios CLI",
        "diag.helper": "Enclave helper",
        "diag.openFolder": "Open keychain folder",
        "diag.openGitHub": "Open GitHub",
        "diag.runtime": "Runtime",
        "diag.viewSource": "View source",
        "overview.recentSecrets": "Recent secrets",
        "overview.vaultHealth": "Vault health",
        "overview.manageSessions": "Manage sessions",
        "overview.useCliHint": "Use `hermes keychain store` to add one safely.",
        "profiles.boundary": "Security boundary",
        "profiles.subtitle2": "Hardware-gated protection for a whole Hermes profile.",
        "diag.subtitle2": "Local paths and runtime health. No secret values appear here.",

        // Settings
        "overview.protected": "PROTECTED",
        "overview.exposed": "EXPOSED",
        "overview.servingN": "Serving %@ secrets from the Keychain.",
        "overview.serving1": "Serving 1 secret from the Keychain.",
        "overview.noneStored": "The source is connected. No secrets are stored yet.",
        "overview.sourceOff": "The Keychain source is not active for this profile.",
        "overview.allReadable": "All %@ secrets are readable.",
        "overview.nLocked": "%@ of %@ locked. Unlock to restore access.",
        "overview.noSecretsYet": "No secrets stored yet.",
        "overview.sourceDisabledCaption": "The secret source is disabled in this profile.",
        "overview.enclaveSessions": "Enclave sessions",
        "overview.keyPresent": "Key present on this Mac",
        "overview.noKey": "No key generated",
        "overview.unlockedSecrets": "Unlocked secrets",
        "overview.nReadable": "%@ of %@ readable",
        "overview.active": "Active",
        "overview.idle": "Idle",
        "overview.readable": "Readable",
        "state.locked": "locked",
        "state.noSession": "no unlock session",
        "state.expired": "session expired",
        "state.noCiphertext": "NO CIPHERTEXT",
        "state.unreadable": "UNREADABLE",
        "state.readable": "readable",
        "state.unlocked": "unlocked",
        "secrets.testAll": "Test all",
        "secrets.testing": "Testing…",
        "secrets.unlockRow": "Unlock",
        "secrets.unlockRowHelp": "One Touch ID opens every Enclave secret at once",
        "migrate.banner": "%@ secrets are not hardware-bound yet.",
        "migrate.banner1": "1 secret is not hardware-bound yet.",
        "migrate.bannerBody": "They sit in the login Keychain, readable by anything running as you. Moving them to the Secure Enclave puts them behind Touch ID.",
        "migrate.action": "Migrate all to Enclave",
        "migrate.busy": "Migrating…",
        "settings.language": "Language",
        "settings.cliExe": "CLI executable",
        "settings.profileHome": "Profile home",
        "settings.verify": "Verify connection",
        "menu.noSecrets": "No secrets configured",
        "menu.sourceEnabled": "Source enabled",
        "menu.sourceDisabled": "Source disabled",
        "menu.enclaveReady": "Enclave ready",
        "menu.noEnclaveKey": "No enclave key",
        "menu.unlock": "Unlock",
        "menu.lock": "Lock",
        "add.updateHint": "Enter a new value for %@. The old value is overwritten.",
        "settings.privacy": "Privacy",
        "settings.privacyBody": "Secret values are accepted in protected fields, piped directly to the local CLI, cleared from the form, and never displayed again.",

        // Status messages
        "msg.ready": "Ready",
        "msg.refreshing": "Refreshing status…",
        "msg.statusOk": "Protection status is up to date",
        "msg.waitingTouchID": "Waiting for Touch ID…",
        "msg.sessionOpened": "Secure session opened",
        "msg.closingSessions": "Closing secure sessions…",
        "msg.sessionsClosed": "All sessions closed",
        "msg.saving": "Encrypting and saving…",
        "msg.copied": "Copied",
        "msg.migrating": "Migrating to the Enclave…",
        "msg.migrated": "is now Enclave-backed",
        "msg.removing": "Removing",
        "msg.removed": "removed",
        "msg.saved": "saved securely",

        "profiles.engineOn": "Engine available",
        "profiles.engineOff": "Engine unavailable",
        "profiles.checkFailed": "Chthonios status check failed",
        "profiles.noProfile": "No profile is managed by Chthonios",
        "profiles.sealed": "Sealed profile:",
        "profiles.unmanaged": "Active, not sealed:",
        "profiles.boundary.enclave": "The Secure Enclave protects individual secrets while Hermes runs.",
        "profiles.boundary.chthonios": "Chthonios seals a whole profile so it is unusable at rest.",
        "profiles.boundary.yubikey": "YubiKey unsealing needs the physical key, its PIN and a touch.",
        "diag.enclaveKey": "Secure Enclave key",
        "diag.present": "Present",
        "diag.missing": "Missing",
        "diag.lastStatus": "Last status",
    ]

    static let french: [String: String] = [
        // Navigation
        "nav.overview": "Vue d'ensemble",
        "nav.secrets": "Secrets",
        "nav.sessions": "Sessions",
        "nav.profiles": "Profils scellés",
        "nav.howitworks": "Fonctionnement",
        "nav.diagnostics": "Diagnostic",

        // Chrome
        "app.title": "HEUCAT Keychain",
        "app.wordmark": "HEUCAT KEYCHAIN",
        "app.refresh": "Actualiser",
        "app.refresh.help": "Actualiser l'état de protection",
        "app.settings": "Réglages",
        "app.quit": "Quitter",
        "app.addSecretMenu": "Ajouter un secret…",
        "app.agent": "Hermes Agent",
        "app.allSecure": "Tout est protégé",
        "app.needsAttention": "Attention requise",
        "app.notChecked": "Pas encore vérifié",
        "app.verified": "Vérifié",

        // Overview
        "overview.eyebrow": "Source de secrets à l'exécution",
        "overview.motto": "Entre les mondes,\nelle garde les clés.",
        "overview.viewSecrets": "Voir les secrets",
        "overview.addSecret": "Ajouter un secret",
        "overview.keyOverview": "Aperçu des clés",
        "overview.totalKeys": "Clés au total",
        "overview.keychain": "Trousseau",
        "overview.enclave": "Enclave",
        "overview.protection": "Protection",
        "overview.agentStatus": "État de l'agent",
        "overview.hermesRuntime": "Exécution Hermes",
        "overview.appleStack": "Trousseau Apple + Secure Enclave",
        "overview.hardwareBacked": "Ancré au matériel. Les valeurs ne quittent jamais ce Mac.",
        "overview.quickActions": "Actions rapides",

        // Stat tiles
        "stat.secrets": "Secrets",
        "stat.secrets.caption": "sous gestion",
        "stat.enclave": "Enclave",
        "stat.enclave.caption": "ancrés au matériel",
        "stat.readable": "Lisibles",
        "stat.readable.open": "session ouverte",
        "stat.readable.closed": "session fermée",
        "stat.health": "Santé",
        "stat.health.on": "source active",
        "stat.health.off": "source inactive",

        // Secrets
        "secrets.title": "Secrets",
        "secrets.subtitle": "Les références se gèrent ici. Les valeurs ne sont jamais affichées.",
        "secrets.search": "Rechercher",
        "secrets.empty.title": "Aucun secret pour l'instant",
        "secrets.empty.body": "Ajoutez une clé et la copie en clair cesse d'être la source de vérité.",
        "secrets.copyName": "Copier le nom de la variable",
        "secrets.updateValue": "Modifier la valeur…",
        "secrets.migrate": "Migrer vers la Secure Enclave",
        "secrets.test": "Tester la connexion",
        "secrets.remove": "Supprimer",
        "secrets.available": "Disponible",
        "secrets.modeEnclave": "Secure Enclave",
        "secrets.modeKeychain": "Trousseau Apple",
        "secrets.confirmRemove": "Supprimer ce secret ?",
        "secrets.cancel": "Annuler",

        // Add / update sheet
        "add.title": "Ajouter un secret",
        "add.title.update": "Modifier un secret",
        "add.subtitle": "La valeur part directement vers le stockage protégé et ne sera plus jamais affichée.",
        "add.identity": "Identité",
        "add.envVar": "Variable d'environnement",
        "add.nameRule": "Lettres, chiffres et tirets bas ; commencez par une lettre ou un tiret bas.",
        "add.protection": "Mode de stockage",
        "add.enclaveHint": "Recommandé. Chiffrement ancré au matériel, déverrouillé par Touch ID ou le mot de passe macOS.",
        "add.keychainHint": "Stocké comme mot de passe générique dans le trousseau de session macOS.",
        "add.value": "Valeur du secret",
        "add.valueField": "Valeur",
        "add.confirm": "Confirmer la valeur",
        "add.mismatch": "Les valeurs ne correspondent pas.",
        "add.advanced": "Options avancées",
        "add.service": "Service (facultatif)",
        "add.account": "Compte (facultatif)",
        "add.noLogs": "Les valeurs n'apparaissent jamais dans les arguments ni les journaux",
        "add.save": "Enregistrer en sécurité",
        "add.update": "Modifier la valeur",

        // Sessions
        "sessions.title": "Sessions",
        "sessions.subtitle": "Accès temporaire aux secrets de la Secure Enclave.",
        "sessions.headline": "Authentifiez-vous une fois, travaillez en sécurité",
        "sessions.body": "Touch ID ouvre une session limitée dans le temps qui couvre tous les secrets Enclave d'un coup. Le démarrage de Hermes reste silencieux, donc la passerelle et les tâches cron ne bloquent jamais sur une demande.",
        "sessions.unlock": "Déverrouiller avec Touch ID",
        "sessions.lockAll": "Verrouiller toutes les sessions",
        "sessions.none": "Aucun secret Enclave n'est stocké, il n'y a donc rien à déverrouiller. Ajoutez-en un depuis la page Secrets en choisissant Secure Enclave.",
        "sessions.tradeoff": "Pendant qu'une session est ouverte, les valeurs se trouvent dans des enregistrements du trousseau à durée limitée, lisibles par les processus lancés sous votre compte. Verrouillez quand vous avez fini plutôt que d'attendre l'expiration.",

        // How it works
        "how.title": "Fonctionnement",
        "how.subtitle": "Ce qui protège réellement vos clés, depuis le silicium.",
        "how.step": "Étape",
        "how.1.title": "Une clé naît dans l'Enclave",
        "how.1.body": "La première fois que vous stockez un secret Enclave, une clé privée P256 est générée dans la Secure Enclave, la puce isolée des Mac Apple Silicon. Cette clé ne peut jamais en sortir. Ni par vous, ni par un logiciel malveillant, ni par macOS. Seule sa moitié publique en sort.",
        "how.2.title": "Votre secret est scellé avec ChaChaPoly",
        "how.2.body": "La valeur est chiffrée avec la clé publique via ECDH puis ChaChaPoly. Comme le chiffrement n'a besoin que de la moitié publique, ajouter un secret ne demande jamais Touch ID. Le chiffré atterrit dans un fichier en 0600 sous votre profil, inutilisable sur un autre Mac.",
        "how.3.title": "Touch ID déverrouille tout le lot d'un coup",
        "how.3.body": "Le déchiffrement est la seule étape qui réclame la clé privée, et l'Enclave ne la libère qu'après une authentification humaine réelle. Une empreinte ouvre tous les secrets Enclave ensemble, puis les met en cache dans des enregistrements de courte durée.",
        "how.4.title": "Hermes les lit sans jamais rien demander",
        "how.4.body": "Au démarrage, Hermes lit uniquement ces enregistrements de session. Un secret verrouillé échoue immédiatement au lieu de rester bloqué, donc la passerelle et les tâches cron n'attendent jamais une empreinte que personne n'est là pour donner.",
        "how.tradeoff.title": "Le compromis, sans détour",
        "how.tradeoff.body": "Pendant qu'une session est ouverte, le texte en clair se trouve dans des enregistrements à durée limitée, lisibles par tout ce qui tourne sous votre compte. C'est le prix à payer pour ne jamais être interrompu. Verrouillez quand vous avez fini, ou gardez une durée courte.",

        // Sealed profiles
        "profiles.title": "Profils scellés",
        "profiles.subtitle": "Chthonios scelle un profil entier au repos.",
        "profiles.separate": "Les deux moteurs de chiffrement restent séparés volontairement. Seul ce tableau de bord est partagé, donc aucun système n'a besoin de faire semblant d'être l'autre. Le descellement se fait par vous dans un terminal, jamais par cette application.",
        "profiles.notInstalled": "Chthonios n'est pas installé",

        // Diagnostics
        "diag.title": "Diagnostic",
        "diag.subtitle": "Ce que l'application sait de cette machine.",
        "diag.hermesCli": "CLI Hermes",
        "diag.hermesHome": "Dossier Hermes",
        "diag.chthoniosCli": "CLI Chthonios",
        "diag.helper": "Assistant Enclave",
        "diag.openFolder": "Ouvrir le dossier du trousseau",
        "diag.openGitHub": "Ouvrir GitHub",
        "diag.runtime": "Exécution",
        "diag.viewSource": "Voir le code source",
        "overview.recentSecrets": "Secrets récents",
        "overview.vaultHealth": "Santé du coffre",
        "overview.manageSessions": "Gérer les sessions",
        "overview.useCliHint": "Utilisez `hermes keychain store` pour en ajouter un en toute sécurité.",
        "profiles.boundary": "Frontière de sécurité",
        "profiles.subtitle2": "Protection ancrée au matériel pour un profil Hermes entier.",
        "diag.subtitle2": "Chemins locaux et état d'exécution. Aucune valeur de secret n'apparaît ici.",

        // Settings
        "overview.protected": "PROTÉGÉ",
        "overview.exposed": "EXPOSÉ",
        "overview.servingN": "%@ secrets servis depuis le trousseau.",
        "overview.serving1": "1 secret servi depuis le trousseau.",
        "overview.noneStored": "La source est connectée. Aucun secret n'est encore stocké.",
        "overview.sourceOff": "La source Trousseau n'est pas active pour ce profil.",
        "overview.allReadable": "Les %@ secrets sont lisibles.",
        "overview.nLocked": "%@ sur %@ verrouillés. Déverrouillez pour rétablir l'accès.",
        "overview.noSecretsYet": "Aucun secret stocké pour l'instant.",
        "overview.sourceDisabledCaption": "La source de secrets est désactivée dans ce profil.",
        "overview.enclaveSessions": "Sessions Enclave",
        "overview.keyPresent": "Clé présente sur ce Mac",
        "overview.noKey": "Aucune clé générée",
        "overview.unlockedSecrets": "Secrets déverrouillés",
        "overview.nReadable": "%@ sur %@ lisibles",
        "overview.active": "Active",
        "overview.idle": "En veille",
        "overview.readable": "Lisibles",
        "state.locked": "verrouillé",
        "state.noSession": "session fermée",
        "state.expired": "session expirée",
        "state.noCiphertext": "AUCUN CHIFFRÉ",
        "state.unreadable": "ILLISIBLE",
        "state.readable": "lisible",
        "state.unlocked": "déverrouillé",
        "secrets.testAll": "Tout tester",
        "secrets.testing": "Test en cours…",
        "secrets.unlockRow": "Déverrouiller",
        "secrets.unlockRowHelp": "Une empreinte ouvre tous les secrets Enclave d'un coup",
        "migrate.banner": "%@ secrets ne sont pas encore ancrés au matériel.",
        "migrate.banner1": "1 secret n'est pas encore ancré au matériel.",
        "migrate.bannerBody": "Ils sont dans le trousseau de session, lisibles par tout ce qui tourne sous votre compte. Les déplacer vers la Secure Enclave les met derrière Touch ID.",
        "migrate.action": "Tout migrer vers l'Enclave",
        "migrate.busy": "Migration…",
        "settings.language": "Langue",
        "settings.cliExe": "Exécutable CLI",
        "settings.profileHome": "Dossier du profil",
        "settings.verify": "Vérifier la connexion",
        "menu.noSecrets": "Aucun secret configuré",
        "menu.sourceEnabled": "Source active",
        "menu.sourceDisabled": "Source inactive",
        "menu.enclaveReady": "Enclave prête",
        "menu.noEnclaveKey": "Pas de clé Enclave",
        "menu.unlock": "Déverrouiller",
        "menu.lock": "Verrouiller",
        "add.updateHint": "Saisissez une nouvelle valeur pour %@. L'ancienne sera écrasée.",
        "settings.privacy": "Confidentialité",
        "settings.privacyBody": "Les valeurs des secrets sont saisies dans des champs protégés, transmises directement au CLI local, effacées du formulaire, et ne sont plus jamais affichées.",

        // Status messages
        "msg.ready": "Prêt",
        "msg.refreshing": "Actualisation de l'état…",
        "msg.statusOk": "L'état de protection est à jour",
        "msg.waitingTouchID": "En attente de Touch ID…",
        "msg.sessionOpened": "Session sécurisée ouverte",
        "msg.closingSessions": "Fermeture des sessions…",
        "msg.sessionsClosed": "Toutes les sessions sont fermées",
        "msg.saving": "Chiffrement et enregistrement…",
        "msg.copied": "Copié",
        "msg.migrating": "Migration vers l'Enclave…",
        "msg.migrated": "est maintenant protégé par l'Enclave",
        "msg.removing": "Suppression de",
        "msg.removed": "supprimé",
        "msg.saved": "enregistré en sécurité",

        "profiles.engineOn": "Moteur disponible",
        "profiles.engineOff": "Moteur indisponible",
        "profiles.checkFailed": "La vérification Chthonios a échoué",
        "profiles.noProfile": "Aucun profil géré par Chthonios",
        "profiles.sealed": "Profil scellé :",
        "profiles.unmanaged": "Actif, non scellé :",
        "profiles.boundary.enclave": "La Secure Enclave protège chaque secret pendant que Hermes tourne.",
        "profiles.boundary.chthonios": "Chthonios scelle un profil entier pour le rendre inutilisable au repos.",
        "profiles.boundary.yubikey": "Le descellement YubiKey réclame la clé physique, son code PIN et un contact.",
        "diag.enclaveKey": "Clé Secure Enclave",
        "diag.present": "Présente",
        "diag.missing": "Absente",
        "diag.lastStatus": "Dernier état",
    ]
}

/// Convenience so views read `L("nav.secrets")` instead of the full singleton.
@MainActor func L(_ key: String) -> String { Loc.shared(key) }

/// Same, with positional `%@` placeholders filled in order.
@MainActor func L(_ key: String, _ args: CustomStringConvertible...) -> String {
    var out = Loc.shared(key)
    for arg in args {
        guard let r = out.range(of: "%@") else { break }
        out.replaceSubrange(r, with: arg.description)
    }
    return out
}

/// Translate a raw per-secret state string coming from the CLI, e.g.
/// "locked (no unlock session)". The leading state word and the known
/// parenthetical reasons are translated; anything unrecognised is passed
/// through verbatim so a new CLI message shows up rather than vanishing.
@MainActor func LState(_ raw: String) -> String {
    var out = raw
    for (en, key) in [("no unlock session", "state.noSession"),
                      ("session expired", "state.expired"),
                      ("NO CIPHERTEXT", "state.noCiphertext"),
                      ("UNREADABLE", "state.unreadable")] {
        out = out.replacingOccurrences(of: en, with: L(key))
    }
    for word in ["locked", "readable", "unlocked"] where out.hasPrefix(word) {
        out = L("state.\(word)") + out.dropFirst(word.count)
        break
    }
    return out
}
