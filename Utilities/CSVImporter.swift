import Foundation
import SwiftData

struct CSVImportResult {
    let entriesCreated: Int
    let invoicesCreated: Int
    let clientsCreated: Int
    let skipped: Int
    /// Rows whose date column could not be read. Surfaced rather than swallowed
    /// — the previous version silently substituted today's date, so a file in a
    /// format the parser did not know would import looking perfectly fine.
    let unreadableDates: Int
    let debugInfo: String
}

struct CSVImporter {

    static func importQuickBooksCSV(url: URL, ctx: ModelContext) throws -> CSVImportResult {
        // Security-scoped resource access for files from document picker
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        // Try multiple encodings
        var content: String?
        for encoding in [String.Encoding.utf8, .isoLatin1, .windowsCP1252, .macOSRoman] {
            if let s = try? String(contentsOf: url, encoding: encoding), !s.isEmpty {
                content = s
                break
            }
        }

        // Strip BOM if present
        if let c = content, c.hasPrefix("\u{FEFF}") {
            content = String(c.dropFirst())
        }

        guard let rawCSV = content, !rawCSV.isEmpty else {
            throw ImportError.emptyFile
        }

        // Normalize line endings: \r\n → \n, then bare \r → \n
        let csv = rawCSV
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let rows = parseCSV(csv)

        guard rows.count > 1 else {
            // Debug: show what line ending characters exist
            let hasLF = csv.contains("\n")
            let hasCR = csv.contains("\r")
            let lineInfo = "LF:\(hasLF) CR:\(hasCR)"
            throw ImportError.custom("Parsed \(rows.count) rows from file (\(csv.count) chars, \(lineInfo)). First 200 chars: \(String(csv.prefix(200)))")
        }

        let header = rows[0]
        guard let colMap = mapColumns(header) else {
            let headerStr = header.joined(separator: " | ")
            throw ImportError.custom("Could not map columns. Header (\(header.count) cols): \(headerStr)")
        }

        let existingClients = (try? ctx.fetch(FetchDescriptor<Client>())) ?? []
        let existingInvoices = (try? ctx.fetch(FetchDescriptor<Invoice>())) ?? []
        // Unfiltered on purpose: dedup has to see the billing records it is
        // comparing against, and they are exactly what the filter hides.
        let existingEntries = (try? ctx.fetch(FetchDescriptor<Entry>())) ?? []

        var clientCache: [String: Client] = [:]
        for c in existingClients { clientCache[c.name.lowercased()] = c }

        var invoiceCache: [String: Invoice] = [:]
        for inv in existingInvoices {
            if let num = inv.number { invoiceCache[num] = inv }
        }

        var clientsCreated = 0
        var invoicesCreated = 0
        var entriesCreated = 0
        var skipped = 0

        var unreadableDates = 0

        for i in 1..<rows.count {
            let cols = rows[i]
            guard cols.count >= colMap.minCols else { skipped += 1; continue }

            let customerName = cols[colMap.customer].trimmingCharacters(in: .whitespacesAndNewlines)
            let service = cols[colMap.service].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let description = cols[colMap.description].trimmingCharacters(in: .whitespacesAndNewlines)
            let invoiceNo = cols[colMap.invoiceNo].trimmingCharacters(in: .whitespacesAndNewlines)
            let invoiceDateStr = cols[colMap.invoiceDate].trimmingCharacters(in: .whitespacesAndNewlines)
            let serviceDateStr = cols[colMap.serviceDate].trimmingCharacters(in: .whitespacesAndNewlines)

            let qty = Double(cols[colMap.quantity].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            let rate = Double(cols[colMap.rate].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0

            guard !customerName.isEmpty else { skipped += 1; continue }

            // Never substitute today for a date we could not read. A wrong-but-
            // plausible date is worse than an obviously missing one: it looks
            // right in a list and quietly poisons every period report.
            let parsedServiceDate = parseDate(serviceDateStr)
            let parsedInvoiceDate = parseDate(invoiceDateStr)
            if parsedServiceDate == nil || parsedInvoiceDate == nil { unreadableDates += 1 }

            // Each stands in for the other before either falls back to now —
            // on a QuickBooks invoice the two are days apart at most.
            guard let serviceDate = parsedServiceDate ?? parsedInvoiceDate else { skipped += 1; continue }
            let invoiceDate = parsedInvoiceDate ?? serviceDate

            // Dedup only against other billing records, never against real work
            // entries. An imported line item and a hand-logged entry can describe
            // the same afternoon; that is not a duplicate, it is the point — the
            // import is the failsafe copy of what was billed and lives behind the
            // isBillingRecord wall. Matching on invoice number + date + qty + rate
            // rather than the description, because QuickBooks rewrites descriptions
            // between exports and an exact-string match missed every one of them.
            let isDuplicate = existingEntries.contains { e in
                e.isBillingRecord
                && e.invoice?.number == invoiceNo
                && e.service == service
                && e.hours == qty
                && e.rate == rate
                && Calendar.current.isDate(e.serviceDate, inSameDayAs: serviceDate)
            }
            if isDuplicate { skipped += 1; continue }

            // Find or create client (exact match first, then substring match)
            let client: Client
            let csvNameLower = customerName.lowercased()
            if let existing = clientCache[csvNameLower] {
                client = existing
            } else if let match = clientCache.first(where: { key, _ in
                csvNameLower.contains(key) || key.contains(csvNameLower)
            }) {
                client = match.value
                clientCache[csvNameLower] = match.value
            } else {
                let newClient = Client(name: customerName, rate: rate, colorIndex: ClientColors.nextIndex(existingCount: clientCache.count))
                ctx.insert(newClient)
                clientCache[csvNameLower] = newClient
                client = newClient
                clientsCreated += 1
            }

            // Find or create invoice
            let invoice: Invoice
            if let existing = invoiceCache[invoiceNo] {
                invoice = existing
                existing.isImported = true
                // Deliberately does not touch existing.createdAt. A re-import is
                // not authority over a date that may have been corrected by hand
                // in the app since.
            } else {
                let newInv = Invoice(title: "\(customerName) \(invoiceNo)", number: invoiceNo, createdAt: invoiceDate, client: client, isImported: true)
                ctx.insert(newInv)
                invoiceCache[invoiceNo] = newInv
                invoice = newInv
                invoicesCreated += 1
            }

            let entry = Entry(
                serviceDate: serviceDate,
                service: service,
                detail: description,
                hours: qty,
                rate: rate,
                client: client,
                status: .done,
                completedAt: serviceDate,
                invoice: invoice
            )
            // Walled off from every regular list — a billing record, not a task.
            entry.isBillingRecord = true
            ctx.insert(entry)
            entriesCreated += 1
        }

        try ctx.save()

        return CSVImportResult(
            entriesCreated: entriesCreated,
            invoicesCreated: invoicesCreated,
            clientsCreated: clientsCreated,
            skipped: skipped,
            unreadableDates: unreadableDates,
            debugInfo: "Parsed \(rows.count) rows, \(header.count) columns"
        )
    }

    // MARK: - Dates

    /// QuickBooks does not export one date format, it exports whichever one the
    /// exporting machine's locale produced. The original parser accepted only
    /// "MM/dd/yyyy", so a file written as 6/9/25 failed every row and fell back
    /// to `Date()` — which is why eight invoices are filed on the day they were
    /// imported rather than the day they were issued.
    ///
    /// Order matters: four-digit-year patterns are tried before two-digit ones,
    /// and ISO before US, so an unambiguous string is never read by a looser
    /// pattern that happens to also match. Day-first formats are deliberately
    /// absent — 03/04/2025 cannot be told apart from its US reading, and
    /// guessing there would trade a visible failure for an invisible one.
    static func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Drop a time component if one came along ("6/9/25 0:00").
        let datePart = trimmed.split(separator: " ").first.map(String.init) ?? trimmed

        // Round-trip first. `DateFormatter.date(from:)` parses a *prefix* and
        // ignores the rest, so "MM/dd/yy" will read "6/9/2025" as the year 20
        // and "M/d/yyyy" will read "6/9/25" as the year 25 — both succeed, both
        // silently wrong. Re-formatting the parsed date and requiring it to
        // equal the input is what actually pins the format down.
        for formatter in dateFormatters {
            if let d = formatter.date(from: datePart),
               formatter.string(from: d) == datePart,
               isPlausible(d) {
                return d
            }
        }

        // Nothing matched exactly — a stray zero-pad or a format not in the
        // list. Take the first parse that lands in a sane range rather than
        // giving up on the row.
        for formatter in dateFormatters {
            if let d = formatter.date(from: datePart), isPlausible(d) { return d }
        }
        return nil
    }

    /// A guard, not a business rule. Its only job is to catch the year-25-AD
    /// class of misparse before it reaches the store.
    private static func isPlausible(_ date: Date) -> Bool {
        let year = Calendar(identifier: .gregorian).component(.year, from: date)
        return year >= 1990 && year <= 2100
    }

    private static let dateFormatters: [DateFormatter] = {
        let patterns = [
            "yyyy-MM-dd",
            "yyyy/MM/dd",
            "MM/dd/yyyy",
            "M/d/yyyy",
            "MM-dd-yyyy",
            "M-d-yyyy",
            "MM/dd/yy",
            "M/d/yy",
            "MM-dd-yy",
            "M-d-yy",
            "MMM d, yyyy",
            "MMMM d, yyyy"
        ]
        return patterns.map { pattern in
            let f = DateFormatter()
            f.calendar = Calendar(identifier: .gregorian)
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = .current
            // Without this, "6/9/2025" is happily accepted by "MM/dd/yy" as
            // year 20, and the first pattern in the list wins every time.
            f.isLenient = false
            f.dateFormat = pattern
            return f
        }
    }()

    // MARK: - CSV Parsing

    /// Parse CSV content (assumes line endings already normalized to \n)
    private static func parseCSV(_ content: String) -> [[String]] {
        var rows: [[String]] = []
        var current: [String] = []
        var field = ""
        var inQuotes = false
        let chars = Array(content)
        var i = 0

        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        field.append("\"")
                        i += 2
                    } else {
                        inQuotes = false
                        i += 1
                    }
                } else {
                    field.append(c)
                    i += 1
                }
            } else {
                switch c {
                case "\"":
                    inQuotes = true
                    i += 1
                case ",":
                    current.append(field)
                    field = ""
                    i += 1
                case "\n":
                    current.append(field)
                    field = ""
                    if !current.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                        rows.append(current)
                    }
                    current = []
                    i += 1
                default:
                    field.append(c)
                    i += 1
                }
            }
        }

        if !field.isEmpty || !current.isEmpty {
            current.append(field)
            if !current.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                rows.append(current)
            }
        }

        return rows
    }

    // MARK: - Column Mapping

    private struct ColumnMap {
        let invoiceNo: Int
        let customer: Int
        let invoiceDate: Int
        let service: Int
        let description: Int
        let quantity: Int
        let rate: Int
        let amount: Int
        let serviceDate: Int
        var minCols: Int { [invoiceNo, customer, invoiceDate, service, description, quantity, rate, amount, serviceDate].max()! + 1 }
    }

    private static func mapColumns(_ header: [String]) -> ColumnMap? {
        let h = header.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
              .lowercased()
              .replacingOccurrences(of: "*", with: "")
        }

        func find(_ candidates: [String]) -> Int? {
            for candidate in candidates {
                if let idx = h.firstIndex(where: { $0.contains(candidate) }) {
                    return idx
                }
            }
            return nil
        }

        guard let invNo = find(["invoiceno"]),
              let cust = find(["customer"]),
              let invDate = find(["invoicedate"]),
              let svc = find(["product/service", "item(product"]),
              let desc = find(["itemdescription"]),
              let qty = find(["itemquantity"]),
              let rate = find(["itemrate"]),
              let amt = find(["itemamount"])
        else { return nil }

        // Service Date / Item Date is the last date column
        let svcDate = h.lastIndex(where: {
            ($0 == "service date" || $0 == "item date" || $0.hasPrefix("service date") || $0.hasPrefix("item date"))
        })

        guard let serviceDateIdx = svcDate else { return nil }

        return ColumnMap(
            invoiceNo: invNo,
            customer: cust,
            invoiceDate: invDate,
            service: svc,
            description: desc,
            quantity: qty,
            rate: rate,
            amount: amt,
            serviceDate: serviceDateIdx
        )
    }

    enum ImportError: LocalizedError {
        case emptyFile
        case custom(String)

        var errorDescription: String? {
            switch self {
            case .emptyFile: return "The CSV file appears to be empty or could not be read."
            case .custom(let msg): return msg
            }
        }
    }
}
