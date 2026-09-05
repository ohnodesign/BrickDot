import Foundation
import SwiftData
import CoreData

/// Safe client lookups for entries.
///
/// `entry.client?.name` traps. Not "returns nil" — traps, taking the app with
/// it. The relationship can hand back a Client whose backing row is gone (a
/// delete merged in from another device, or a store that came back from
/// CloudKit mid-import), and SwiftData fatals on any stored-property read of
/// such a model. `isAlive` does not catch it: the model is neither deleted nor
/// detached, its row simply isn't there.
///
/// The only reliable answer comes from the store, because a fetch returns just
/// the rows that exist. Fetching per row is far too slow for a scrolling list,
/// so results are cached by id and the cache is dropped whenever the store
/// changes — a local save, or a merge arriving from another device.
///
/// Identity reads (`persistentModelID`) stay safe on such a model, which is
/// what makes the indirection possible at all.
enum ClientInfoCache {

    struct Info {
        let name: String
        let rate: Double
    }

    private static let lock = NSLock()
    private static var cache: [PersistentIdentifier: Info] = [:]
    private static var missing: Set<PersistentIdentifier> = []
    private static var loaded = false
    private static var observing = false

    // MARK: Lookup

    static func info(for id: PersistentIdentifier, in context: ModelContext) -> Info? {
        startObservingIfNeeded()

        lock.lock()
        let hit = cache[id]
        let knownMissing = missing.contains(id)
        let isLoaded = loaded
        lock.unlock()

        if let hit { return hit }
        if isLoaded && knownMissing { return nil }   // don't refetch a known orphan every frame

        rebuild(context)

        lock.lock()
        defer { lock.unlock() }
        if let fresh = cache[id] { return fresh }
        missing.insert(id)
        return nil
    }

    // MARK: Maintenance

    private static func rebuild(_ context: ModelContext) {
        let clients = (try? context.fetch(FetchDescriptor<Client>())) ?? []
        var fresh: [PersistentIdentifier: Info] = [:]
        fresh.reserveCapacity(clients.count)
        for client in clients {
            fresh[client.persistentModelID] = Info(name: client.name, rate: client.rate)
        }
        lock.lock()
        cache = fresh
        missing.removeAll()
        loaded = true
        lock.unlock()
    }

    static func invalidate() {
        lock.lock()
        cache.removeAll()
        missing.removeAll()
        loaded = false
        lock.unlock()
    }

    /// A rename or a delete has to drop the cache, whether it happened here or
    /// arrived from another device.
    private static func startObservingIfNeeded() {
        lock.lock()
        let already = observing
        observing = true
        lock.unlock()
        guard !already else { return }

        let center = NotificationCenter.default
        for name in [
            NSNotification.Name.NSPersistentStoreRemoteChange,
            NSNotification.Name("NSManagedObjectContextDidSave"),
            ModelContext.didSave
        ] {
            center.addObserver(forName: name, object: nil, queue: nil) { _ in
                invalidate()
            }
        }
    }
}
