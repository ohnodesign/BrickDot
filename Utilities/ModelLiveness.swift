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
/// ## What this does *not* catch
///
/// `isAlive` covers models deleted locally or detached from their context.
/// It does **not** catch an *invalidated* model: one that is neither
/// `isDeleted` nor detached, but whose backing row is already gone — which
/// is what a delete arriving from another device via CloudKit produces.
/// Such a model passes `isAlive` and still traps on the next property read.
///
/// There is no cheap test for that state; the only reliable answer comes from
/// the store. So for children that a remote delete can pull out from under a
/// view — the time logs and subtasks in `EditEntryView` — read them from a
/// `@Query` instead of from the parent's cached relationship array. A query
/// refetches on the same merge that removed the row, so everything it returns
/// exists. Use `isAlive` / `.live` for references the *user* can delete in
/// this app (a selected client, a template, an invoice), where the reference
/// simply needs to degrade to "nothing selected".
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
