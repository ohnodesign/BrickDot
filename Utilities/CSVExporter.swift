// Utilities/CSVExporter.swift
import Foundation
import SwiftData

// MARK: - Optional (legacy) header mapping you already support
struct ExportHeaders {
    var columns: [String] = [
        "Service Date","Customer","Service","Description","Quantity","Rate","Amount"
    ]
    static let quickBooks = ExportHeaders(columns: [
        "TxnDate","Customer","Service","Description","Qty","Rate","Amount"
    ])
}

struct CSVExporter {

    // =========================================================================
    // MARK: - YOUR EXISTING EXPORTS (unchanged behavior)
    // =========================================================================

    /// Export one CSV to a temporary URL with a safe filename.
    static func export(entries: [Entry],
                       fileName: String,
                       headers: ExportHeaders = ExportHeaders()) -> URL {
        let headerLine = headers.columns.joined(separator: ",") + "\n"
        let rows = entries.map { makeRow(for: $0, columns: headers.columns) }.joined(separator: "\n")
        let csv = headerLine + rows + (rows.isEmpty ? "" : "\n")

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeFilename(fileName) + ".csv")
        if let data = csv.data(using: .utf8) {
            try? data.write(to: url, options: .atomic)
        }
        return url
    }

    /// Export one CSV per month and return their file URLs.
    static func exportPerMonth(entries: [Entry],
                               clientName: String,
                               months: [Date],
                               headers: ExportHeaders = ExportHeaders()) -> [URL] {
        var urls: [URL] = []
        for month in months {
            let start = month.startOfMonth
            let end   = month.endOfMonth
            let monthEntries = entries.filter { $0.serviceDate >= start && $0.serviceDate <= end }
            let name = "\(clientName)_\(month.yearMonthLabel)"
            let url = export(entries: monthEntries, fileName: name, headers: headers)
            urls.append(url)
        }
        return urls
    }

    /// Builds one row for your legacy/simple exports (non-QuickBooks).
    private static func makeRow(for e: Entry, columns: [String]) -> String {
        let df = DateFormatter.iso8601Day
        let billingDate = e.billOnCompletion ? (e.completedAt ?? e.serviceDate) : e.serviceDate
        let values: [String] = columns.map { col in
            switch col {
            case "Service Date", "TxnDate":
                return df.string(from: billingDate)
            case "Customer":
                return escape(e.clientName)
            case "Service":
                return escape(e.service)
            case "Description":
                return escape(descriptionWithSubtasks(e))
            case "Quantity", "Qty":
                return String(format: "%.2f", e.hours)
            case "Rate":
                return String(format: "%.2f", e.rate)
            case "Amount":
                return String(format: "%.2f", e.hours * e.rate)
            default:
                return ""
            }
        }
        return values.joined(separator: ",")
    }

    // =========================================================================
    // MARK: - QUICKBOOKS IMPORT CSV (matches proven format)
    // =========================================================================

    // Header matching the user's successful QuickBooks import format (12 columns)
    private static let qbImportHeader =
        "*InvoiceNo,*Customer,*InvoiceDate,*DueDate,Terms,Item(Product/Service),ItemDescription,ItemQuantity,ItemRate,*ItemAmount,Taxable,Service Date"

    // US-style date format for QuickBooks Online
    private static let qbDF: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.dateFormat = "MM/dd/yyyy"
        return df
    }()

    /// Export a QuickBooks-compatible import CSV matching the proven 12-column format.
    ///
    /// Each line item becomes a row. All rows share the same invoice number, customer,
    /// invoice date, due date, and terms.
    ///
    /// - Parameters:
    ///   - entries: Line items for the invoice.
    ///   - client: Customer name source.
    ///   - terms: e.g. "Due on receipt", "Net 30".
    ///   - invoiceDate: Date printed on the invoice.
    ///   - dueDate: Defaults to invoiceDate when terms is "Due on receipt", or +30 days for "Net 30".
    ///   - forceInvoiceNo: Override the auto-generated invoice number.
    ///   - fileName: Custom file name base (without extension).
    /// - Returns: URL to the generated CSV in the Temporary directory.
    @discardableResult
    static func exportQuickBooksSingleInvoice(
        entries: [Entry],
        client: Client,
        terms: String = "Due on receipt",
        invoiceDate: Date = Date(),
        dueDate: Date? = nil,
        forceInvoiceNo: String? = nil,
        fileName: String? = nil
    ) -> URL {
        let invNo = forceInvoiceNo ?? InvoiceNumberManager.nextAndAdvance()
        let invDateStr = qbDF.string(from: invoiceDate)

        let computedDue: Date
        if let explicit = dueDate {
            computedDue = explicit
        } else if terms.lowercased().contains("net 30") {
            computedDue = Calendar(identifier: .gregorian).date(byAdding: .day, value: 30, to: invoiceDate) ?? invoiceDate
        } else {
            // "Due on receipt" — due date matches invoice date
            computedDue = invoiceDate
        }
        let dueStr = qbDF.string(from: computedDue)

        var rows: [String] = [qbImportHeader]

        for e in entries.sorted(by: { $0.serviceDate < $1.serviceDate }) {
            let qty: String
            if e.hours == 0 {
                qty = ""  // Match user's pattern: empty when no hours
            } else if e.hours == e.hours.rounded() && e.hours >= 1 {
                qty = String(Int(e.hours))  // "5" not "5.00"
            } else {
                // Use minimal decimal precision: "0.3" not "0.30"
                let formatted = String(format: "%g", e.hours)
                qty = formatted
            }

            let rate = String(format: "%.2f", e.rate)
            let amount = String(format: "%.2f", e.hours * e.rate)
            let billingDate = e.billOnCompletion ? (e.completedAt ?? e.serviceDate) : e.serviceDate
            let serviceDate = qbDF.string(from: billingDate)

            let cols: [String] = [
                escapeQB(invNo),                          // *InvoiceNo
                escapeQB(client.name),                    // *Customer
                invDateStr,                               // *InvoiceDate
                dueStr,                                   // *DueDate
                escapeQB(terms),                          // Terms
                escapeQB(e.service),                      // Item(Product/Service)
                escapeQB(descriptionWithSubtasks(e)),     // ItemDescription
                qty,                                      // ItemQuantity
                rate,                                     // ItemRate
                amount,                                   // *ItemAmount
                "N",                                      // Taxable
                serviceDate                               // Service Date
            ]
            rows.append(cols.joined(separator: ","))
        }

        let name = fileName ?? "\(client.name)_Invoice_\(invNo)"
        return writeCSVFile(named: name, rows: rows)
    }

    /// Export MULTIPLE QuickBooks invoices (e.g., one per month or per grouping).
    /// Each group gets its own auto-incremented invoice number.
    @discardableResult
    static func exportQuickBooksGrouped(
        groups: [(title: String, client: Client, entries: [Entry])],
        terms: String = "Due on receipt"
    ) -> [URL] {
        var urls: [URL] = []
        for g in groups {
            let invNo = InvoiceNumberManager.nextAndAdvance()
            let url = exportQuickBooksSingleInvoice(
                entries: g.entries,
                client: g.client,
                terms: terms,
                forceInvoiceNo: invNo,
                fileName: "\(g.client.name)_Invoice_\(g.title)"
            )
            urls.append(url)
        }
        return urls
    }

    // =========================================================================
    // MARK: - Internals (escaping, writing, helpers)
    // =========================================================================

    private static func writeCSVFile(named: String, rows: [String]) -> URL {
        let csv = rows.joined(separator: "\n") + "\n"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeFilename(named) + ".csv")
        try? csv.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }

    /// Escape for simple CSV (your legacy format).
    private static func escape(_ value: String) -> String {
        var v = value.replacingOccurrences(of: "\"", with: "\"\"")
        if v.contains(",") || v.contains("\n") || v.contains("\"") {
            v = "\"" + v + "\""
        }
        return v
    }

    /// Escape for QuickBooks CSV cells (quoted when contains comma/newline/quote, otherwise bare).
    private static func escapeQB(_ s: String) -> String {
        guard !s.isEmpty else { return "" }
        let q = s.replacingOccurrences(of: "\"", with: "\"\"")
        if q.contains(",") || q.contains("\n") || q.contains("\"") {
            return "\"\(q)\""
        }
        return q
    }

    static func descriptionWithSubtasks(_ entry: Entry) -> String {
        var desc = entry.detail
        if !entry.subtasksList.isEmpty {
            let bullets = entry.subtasksList.map { "• \($0.title)" }.joined(separator: "\n")
            desc = desc.isEmpty ? bullets : desc + "\n" + bullets
        }
        return desc
    }

    private static func safeFilename(_ raw: String) -> String {
        return raw
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\"", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
