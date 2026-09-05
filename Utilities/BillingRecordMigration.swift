import Foundation
import SwiftData

/// One-time pass that walls off the QuickBooks line items that were already in
/// the store before `Entry.isBillingRecord` existed.
///
/// The rule is deliberately narrow. The importer is the only thing that ever set
/// an `Invoice.number` — invoices built inside BrickDot leave it nil — so a
/// numbered invoice is an imported one, and everything hanging off it is a
/// billing record rather than work. That distinction matters: at the time this
/// was written the store held fourteen numbered QuickBooks invoices (~168 line
/// items) and one invoice created in the app from real tracked work, and a
/// blanket "has an invoice → hide it" rule would have taken that real work out
/// of the lists too.
///
/// Two further guards, because being wrong here means work silently vanishing
/// from the app: an entry that carries time logs or subtasks was worked on
/// inside BrickDot and is never reclassified, whatever it is attached to.
enum BillingRecordMigration {
    static let didRunKey = "billingRecordMigration.v1.didRun"

    @discardableResult
    static func runIfNeeded(ctx: ModelContext) -> Int {
        guard !UserDefaults.standard.bool(forKey: didRunKey) else { return 0 }

        let invoices: [Invoice]
        do {
            invoices = try ctx.fetch(FetchDescriptor<Invoice>())
        } catch {
            // Leave the flag unset so this retries on the next launch rather
            // than quietly deciding the store had nothing in it.
            return 0
        }

        var flagged = 0
        for invoice in invoices {
            guard let number = invoice.number, !number.isEmpty else { continue }
            invoice.isImported = true
            for entry in invoice.entriesList {
                guard !entry.isBillingRecord else { continue }
                let workedOnHere = !(entry.timeLogs ?? []).isEmpty || !(entry.subtasks ?? []).isEmpty
                guard !workedOnHere else { continue }
                entry.isBillingRecord = true
                flagged += 1
            }
        }

        do {
            try ctx.save()
            UserDefaults.standard.set(true, forKey: didRunKey)
        } catch {
            return 0
        }

        #if DEBUG
        print("[BillingRecordMigration] flagged \(flagged) imported line items across \(invoices.filter(\.isImported).count) invoices")
        #endif
        return flagged
    }
}
