import Foundation
import Security

/// A stable, per-install RevenueCat App User ID stored in the **Keychain**.
///
/// Why: RevenueCat's default *anonymous* App User ID lives in UserDefaults,
/// which iOS wipes when the app is deleted. An anonymous user therefore loses
/// their (paid) gem balance on a delete + reinstall. Keychain items survive app
/// deletion on the same device, so seeding RevenueCat with a Keychain-backed ID
/// means a reinstall resolves the *same* RevenueCat customer and the balance is
/// preserved.
///
/// Scope: this fixes same-device reinstall only. It does NOT solve moving to a
/// new phone — a plain (non-synchronizable) Keychain item doesn't travel across
/// devices (it may ride an encrypted backup restore, but that's best-effort).
/// True cross-device continuity needs a real login (Sign in with Apple +
/// `Purchases.logIn`).
enum KeychainAppUserID {
    // Fixed literals — deliberately NOT derived from the bundle ID, so a later
    // bundle-ID change can't orphan an existing user's stored identity.
    private static let service = "RoastMyGallery.revenueCatAppUserID"
    private static let account = "appUserID"

    /// Returns the persisted App User ID, creating and storing one on first
    /// call. Never throws — on any Keychain failure it returns a fresh ID so
    /// configuration can still proceed (that install simply won't persist
    /// across reinstall, matching the old anonymous behavior).
    static func getOrCreate() -> String {
        if let existing = read() { return existing }
        let fresh = "rmg_" + UUID().uuidString
        store(fresh)
        return fresh
    }

    private static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let id = String(data: data, encoding: .utf8),
              !id.isEmpty
        else { return nil }
        return id
    }

    private static func store(_ id: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // Idempotent: clear any stale value first so Add can't fail with
        // errSecDuplicateItem.
        SecItemDelete(base as CFDictionary)

        var attributes = base
        attributes[kSecValueData as String] = Data(id.utf8)
        // AfterFirstUnlock (not ThisDeviceOnly): readable after the first unlock
        // post-boot, and included in encrypted device backups — so it survives
        // reinstall and *may* ride an encrypted backup to a new phone. Not
        // marked synchronizable, so it never syncs to iCloud Keychain.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
