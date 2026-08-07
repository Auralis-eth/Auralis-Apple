import Foundation
import Security

/// One-shot migration that consolidates every WalletConnector keychain item for a
/// given service into a shared access group.
///
/// When a host opts an app + extension into Keychain Sharing (see the three
/// stores' `accessGroup:` parameters), items written by earlier builds still live
/// in the app's **private default** access group and are invisible to queries
/// scoped to the new shared group — so a user's existing sessions/relay identity
/// would appear lost the first time the shared group is used. This migrator moves
/// them across.
///
/// Design:
/// - Everything under the WalletConnect service (`session-topic:`, `session-record:`,
///   `relay-auth-identity`, and any legacy un-prefixed record) belongs to the same
///   shared namespace, so the migration is intentionally **kind-agnostic**: it moves
///   *every* item for the service that is not already in the target group. Per-kind
///   account layout is then reconciled by each store's own legacy migration, which
///   now runs scoped to the shared group.
/// - It preserves the topic store's `kSecAttrLabel` (chain) and `kSecAttrDescription`
///   (verified flag) so no session metadata is dropped in transit.
/// - It is **copy-before-delete**: the original is removed only after the shared-group
///   copy is confirmed, so an interruption never loses an item.
/// - It is idempotent and best-effort. Before the Keychain Sharing entitlement is
///   actually present, the copy fails with `errSecMissingEntitlement`; the migration
///   is simply not marked complete and retries on the next call — so wiring the group
///   in code ahead of the entitlement never destroys anything.
enum KeychainAccessGroupMigration {
    private static let lock = NSLock()
    /// `"service|targetGroup"` keys for which consolidation is fully complete, so
    /// steady-state operations skip the extra enumeration.
    private static var completed: Set<String> = []

    /// Runs the consolidation once per `(service, targetGroup)` per process. Cheap
    /// no-op after the first fully-successful run.
    static func migrateServiceIfNeeded(service: String, targetGroup: String) {
        let key = "\(service)|\(targetGroup)"
        lock.lock()
        let alreadyDone = completed.contains(key)
        lock.unlock()
        guard !alreadyDone else { return }

        if migrate(service: service, targetGroup: targetGroup) {
            lock.lock()
            completed.insert(key)
            lock.unlock()
        }
    }

    /// Returns `true` when the service is fully consolidated into `targetGroup`
    /// (nothing left outside it), so the caller can stop retrying.
    private static func migrate(service: String, targetGroup: String) -> Bool {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
        ]
#if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
#endif

        var result: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecItemNotFound:
            return true // Nothing stored anywhere yet.
        case errSecSuccess:
            break
        default:
            return false // Momentarily unreadable (device locked); retry later.
        }
        guard let rows = result as? [[String: Any]] else { return true }

        var allMoved = true
        for row in rows {
            guard let group = row[kSecAttrAccessGroup as String] as? String,
                  group != targetGroup,
                  let account = row[kSecAttrAccount as String] as? String,
                  let data = row[kSecValueData as String] as? Data else {
                continue
            }

            var addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecAttrAccessGroup as String: targetGroup,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                kSecAttrSynchronizable as String: false,
            ]
            // Preserve the topic store's chain (label) and verified (description).
            if let label = row[kSecAttrLabel as String] as? String {
                addQuery[kSecAttrLabel as String] = label
            }
            if let description = row[kSecAttrDescription as String] as? String {
                addQuery[kSecAttrDescription as String] = description
            }
#if os(macOS)
            addQuery[kSecUseDataProtectionKeychain as String] = true
#endif

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else {
                // e.g. `errSecMissingEntitlement` before Keychain Sharing is wired.
                allMoved = false
                continue
            }

            // Copy confirmed — remove the original from its old group.
            var deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecAttrAccessGroup as String: group,
                kSecAttrSynchronizable as String: false,
            ]
#if os(macOS)
            deleteQuery[kSecUseDataProtectionKeychain as String] = true
#endif
            let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)
            if deleteStatus != errSecSuccess, deleteStatus != errSecItemNotFound {
                allMoved = false
            }
        }
        return allMoved
    }
}
