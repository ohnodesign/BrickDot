import Foundation
import SwiftData

struct CSVImportResult {
    let entriesCreated: Int
    let invoicesCreated: Int
    let clientsCreated: Int
    let skipped: Int
}

struct CSVImporter {

    /// Import entries from a QuickBooks-format CSV into SwiftData.
    /// Matches or creates clients, creates entries as Done, and groups by invoice number.
    static func importQuickBooksCSV(url: URL, ctx: ModelContext) throws -> CSVImportResult {
        let content = try String(contentsOf: url, encoding: .utf8)
        let rows = parseCSV(content)

        guard rows.count > 1 else {
            throw ImportError.emptyFile
        }

        let header = rows[0]
        guard let colMap = mapColumns(header) else {
            throw ImportError.unrecognizedFormat
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
        dateFormatter.dateFormat = "MM/dd/yyyy"

        for i in 1..<rows.count {
            let cols = rows[i]
            guard cols.count >= colMap.minCols else { skipped += 1; continue }

            let customerName = cols[colMap.customer].trimmingCharacters(in: .whitespacesAndNewlines)
            let service = cols[colMap.service].trimmingCharacters(in: .whitespacesAndNewlines)
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

            // Find or create client
            let client: Client
            if let existing = clientCache[customerName.lowercased()] {
                client = existing
            } else {
                let newClient = Client(name: customerName, rate: rate, colorIndex: ClientColors.nextIndex(existingCount: clientCache.count))
                ctx.insert(newClient)
                clientCache[customerName.lowercased()] = newClient
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

            // Create entry
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
            skipped: skipped
        )
    }

    // MARK: - CSV Parsing

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
                        continue
                    } else {
                        inQuotes = false
                        i += 1
                        continue
                    }
                } else {
                    field.append(c)
                    i += 1
                }
            } else {
                if c == "\"" {
                    inQuotes = true
                    i += 1
                } else if c == "," {
                    current.append(field)
                    field = ""
                    i += 1
                } else if c == "\n" || c == "\r" {
                    current.append(field)
                    field = ""
                    if !current.allSatisfy({ $0.isEmpty }) {
                        rows.append(current)
                    }
                    current = []
                    if c == "\r" && i + 1 < chars.count && chars[i + 1] == "\n" {
                        i += 2
                    } else {
                        i += 1
                    }
                } else {
                    field.append(c)
                    i += 1
                }
            }
        }

        if !field.isEmpty || !current.isEmpty {
            current.append(field)
            if !current.allSatisfy({ $0.isEmpty }) {
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
        let h = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "*", with: "") }

        guard let invNo = h.firstIndex(of: "invoiceno"),
              let cust = h.firstIndex(of: "customer"),
              let invDate = h.firstIndex(of: "invoicedate"),
              let svc = h.firstIndex(where: { $0.contains("product/service") || $0 == "item" }),
              let desc = h.firstIndex(of: "itemdescription"),
              let qty = h.firstIndex(of: "itemquantity"),
              let rate = h.firstIndex(of: "itemrate"),
              let amt = h.firstIndex(of: "itemamount"),
              let svcDate = h.firstIndex(of: "service date")
        else { return nil }

        return ColumnMap(
            invoiceNo: invNo,
            customer: cust,
            invoiceDate: invDate,
            service: svc,
            description: desc,
            quantity: qty,
            rate: rate,
            amount: amt,
            serviceDate: svcDate
        )
    }

    enum ImportError: LocalizedError {
        case emptyFile
        case unrecognizedFormat

        var errorDescription: String? {
            switch self {
            case .emptyFile: return "The CSV file is empty."
            case .unrecognizedFormat: return "Could not recognize the CSV column format. Expected QuickBooks import headers."
            }
        }
    }
}
