import Foundation
import Security

/// A stable RevenueCat App User ID stored in the **iCloud Keychain**.
///
/// Why not the default: RevenueCat's *anonymous* App User ID lives in
/// UserDefaults, which iOS wipes when the app is deleted — so an anonymous user
/// loses their (paid) gem balance on a delete + reinstall. A Keychain item
/// survives app deletion, so seeding RevenueCat with a Keychain-backed ID means
/// a reinstall resolves the *same* customer and the balance is preserved.
///
/// Why **synchronizable**: gems are bought with real money, and App Store
/// Review Guideline 3.1.1 is explicit that purchased currency may not expire.
/// A device-local item covers reinstall but not a new phone, which is exactly
/// where a paying user would notice their balance gone. Marking the item
/// synchronizable puts it in the user's iCloud Keychain, so a new device reads
/// the same ID and resolves the same RevenueCat customer.
///
/// Honest limits:
/// - It rides iCloud Keychain, so a user who has that turned off is back to
///   device-local behavior. Nothing here can fix that.
/// - If two devices each mint an ID before sync lands, one of them wins and the
///   other's balance is stranded. Rare, and strictly better than the previous
///   guaranteed loss — but the only complete fix is a real login (Sign in with
///   Apple + `Purchases.logIn`), which would also pull in Guideline 5.1.1(v)
///   account-deletion obligations.
enum KeychainAppUserID {
    // Fixed literals — deliberately NOT derived from the bundle ID, so a later
    // bundle-ID change can't orphan an existing user's stored identity.
    private static let service = "RoastMyGallery.revenueCatAppUserID"
    private static let account = "appUserID"

    /// Returns the persisted App User ID, creating and storing one on first
    /// call. Never throws — on any Keychain failure it returns a fresh ID so
    /// configuration can still proceed (that install simply won't persist
    /// across reinstall, matching the old anonymous behavior).
    ///
    /// The returned string is what `Purchases.configure` is seeded with, so the
    /// one rule this function must never break is: if an ID already exists
    /// anywhere, return *that* value unchanged. Minting a new one would orphan
    /// the customer holding the gems.
    static func getOrCreate() -> String {
        // A synced ID wins. On a device that has received one from iCloud
        // Keychain, that is the identity carrying this user's purchase history,
        // so it must take precedence over anything stored locally beforehand.
        if let synced = read(synchronizable: true) { return synced }

        // Installs from before the sync change stored the ID device-locally.
        // Re-store the SAME value as synchronizable so it starts travelling —
        // the string is untouched, so RevenueCat keeps resolving the same
        // customer and the balance carries over silently.
        if let local = read(synchronizable: false) {
            store(local)
            return local
        }

        let fresh = "rmg_" + UUID().uuidString
        store(fresh)
        return fresh
    }

    /// Reads the stored ID from one of the two keychain variants.
    ///
    /// `kSecAttrSynchronizable` is passed explicitly because omitting it
    /// defaults the query to `false` — which silently hides every synced item.
    /// That default is exactly how a new phone would ignore the ID iCloud
    /// Keychain had just delivered to it.
    private static func read(synchronizable: Bool) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: synchronizable,
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
        // Delete BOTH variants: it keeps Add from failing with
        // errSecDuplicateItem, and it's what stops a leftover device-local copy
        // from shadowing the synced item on the next launch (`read` checks the
        // synced variant first, so a stale local twin would just sit there —
        // but only one item should ever exist).
        var deleteQuery = base
        deleteQuery[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        SecItemDelete(deleteQuery as CFDictionary)

        var attributes = base
        attributes[kSecValueData as String] = Data(id.utf8)
        // AfterFirstUnlock is the strictest protection class that can still
        // sync: every `...ThisDeviceOnly` variant is barred from iCloud Keychain
        // by definition, which would defeat the point.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        attributes[kSecAttrSynchronizable as String] = true
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
