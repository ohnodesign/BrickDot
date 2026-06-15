import Foundation
import SwiftData

struct CSVImportResult {
    let entriesCreated: Int
    let invoicesCreated: Int
    let clientsCreated: Int
    let skipped: Int
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

        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "MM/dd/yyyy"

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

            let serviceDate = dateFormatter.date(from: serviceDateStr) ?? Date()
            let invoiceDate = dateFormatter.date(from: invoiceDateStr) ?? Date()

            // Dedup: skip if an entry with the same client, service, description, and date already exists
            let isDuplicate = existingEntries.contains { e in
                e.clientName.lowercased() == customerName.lowercased()
                && e.service == service
                && e.detail == description
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
            } else {
                let newInv = Invoice(title: "\(customerName) \(invoiceNo)", number: invoiceNo, createdAt: invoiceDate, client: client)
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
            ctx.insert(entry)
            entriesCreated += 1
        }

        try ctx.save()

        return CSVImportResult(
            entriesCreated: entriesCreated,
            invoicesCreated: invoicesCreated,
            clientsCreated: clientsCreated,
            skipped: skipped,
            debugInfo: "Parsed \(rows.count) rows, \(header.count) columns"
        )
    }

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
