import Foundation
import SwiftData

/// SwiftData traps on *any* property read of a deleted model — the crash is
/// `This model instance was invalidated because its backing data could no
/// longer be found in the store`. That matters here because views routinely
/// outlive the objects they reference:
///
/// - `@State var selected: Client?` keeps a strong reference that a delete
///   elsewhere in the app (or a CloudKit sync from another device) does not
///   clear.
/// - SwiftUI re-evaluates a view's body at least once while a dismissal or
///   navigation pop is in flight, after the delete has already landed.
/// - Cascade rules mean deleting one object invalidates many: a Client takes
///   its entries, invoices, templates, and saved searches with it.
///
/// Identity reads (`persistentModelID`, `==`) stay safe on a deleted model;
/// it's the stored properties (`name`, `detail`, `addedAt`, …) that trap.
extension PersistentModel {
    /// False once this model has been deleted or detached from its context.
    /// Check before reading any stored property off a reference you've held.
    var isAlive: Bool {
        !isDeleted && modelContext != nil
    }
}

extension Optional where Wrapped: PersistentModel {
    /// The wrapped model, or nil if it has been deleted — so a stale
    /// reference degrades to "nothing selected" instead of crashing.
    /// Use at every *read* site; plain assignment stays as-is.
    var live: Wrapped? {
        guard let model = self, model.isAlive else { return nil }
        return model
    }
}

extension Sequence where Element: PersistentModel {
    /// Drops models that have been deleted but are still present in a
    /// relationship array or a captured snapshot.
    var liveOnly: [Element] {
        filter { $0.isAlive }
    }
}
