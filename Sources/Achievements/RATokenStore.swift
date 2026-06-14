// T3d Boy — RetroAchievements credential storage.
//
// We persist ONLY the RA login token (and the username it belongs to) — never the
// password. The token is stored in the macOS Keychain via the Security framework.
// The store sits behind a tiny protocol so a Windows/Linux port can drop in a
// different backend (DPAPI / libsecret / a file) without touching the runtime.

import Foundation
import Security

/// A saved RA credential: the username plus the server-issued login token.
struct RACredential {
    var username: String
    var token: String
}

/// Platform-agnostic seam for persisting the RA login token.
protocol RATokenStoring {
    func load() -> RACredential?
    func save(_ credential: RACredential)
    func clear()
}

/// Selects the token backend. In normal use this is the Keychain. During local
/// development, ad-hoc re-signing changes the binary's identity on every build, so
/// the Keychain re-prompts for the login password to grant access — which makes
/// unattended rebuild/relaunch loops impossible. Setting the `T3DBOY_DEV_TOKEN`
/// environment variable switches to a plain on-disk store that never prompts, so
/// builds can run while you're away. Never enable this for a shipped build.
func makeTokenStore() -> RATokenStoring {
    if ProcessInfo.processInfo.environment["T3DBOY_DEV_TOKEN"] != nil {
        return FileTokenStore()
    }
    return KeychainTokenStore()
}

/// Dev-only: stores the token as a JSON file under Application Support. No ACL, so
/// no Keychain password prompt across ad-hoc rebuilds. Lower security than the
/// Keychain (plaintext token on disk) — gated behind `T3DBOY_DEV_TOKEN`, dev use only.
struct FileTokenStore: RATokenStoring {
    private var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("T3dBoy", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("dev-ra-token.json")
    }

    func load() -> RACredential? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONDecoder().decode(StoredCredential.self, from: data)
        else { return nil }
        return RACredential(username: json.username, token: json.token)
    }

    func save(_ credential: RACredential) {
        let stored = StoredCredential(username: credential.username, token: credential.token)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func clear() { try? FileManager.default.removeItem(at: url) }

    private struct StoredCredential: Codable { let username: String; let token: String }
}

/// macOS Keychain-backed implementation (generic password item).
struct KeychainTokenStore: RATokenStoring {
    private let service = "com.t3dboy.retroachievements"
    private let account = "ra-login-token"

    func load() -> RACredential? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data,
              let json = try? JSONDecoder().decode(StoredCredential.self, from: data)
        else { return nil }
        return RACredential(username: json.username, token: json.token)
    }

    func save(_ credential: RACredential) {
        let stored = StoredCredential(username: credential.username, token: credential.token)
        guard let data = try? JSONEncoder().encode(stored) else { return }

        // Replace any existing item: delete then add (idempotent, avoids dupes).
        SecItemDelete(baseQuery() as CFDictionary)

        var add = baseQuery()
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private struct StoredCredential: Codable {
        let username: String
        let token: String
    }
}
