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
    // MARK: - QUICKBOOKS EXPORTS (bullet-proof format)
    // =========================================================================

    // Required QuickBooks header in the exact order they expect (sample spec)
    private static var qbHeader: String {
        [
            "InvoiceNo","Customer","InvoiceDate","DueDate","Terms","Location","Memo",
            "Item(Product/Service)","ItemDescription","ItemQuantity","ItemRate","ItemAmount",
            "Taxable","TaxRate","Shipping address","Ship via","Shipping date","Tracking no",
            "Shipping Charge","Service Date"
        ].joined(separator: ",")
    }

    // US-style date format for QuickBooks Online (change to dd/MM/yyyy if your QBO is set to UK format)
    private static let qbDFUS: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.dateFormat = "MM/dd/yyyy"
        return df
    }()

    /// Export a SINGLE QuickBooks invoice CSV for a set of entries (all for the same client).
    /// Ensures required columns exist and uses InvoiceNumberManager for numbering by default.
    ///
    /// - Parameters:
    ///   - entries: Items to include on the invoice (line items).
    ///   - client: Customer name source.
    ///   - terms: e.g. "Net 30".
    ///   - invoiceDate: default now.
    ///   - dueDate: default invoiceDate + 30 if terms == "Net 30".
    ///   - forceInvoiceNo: set if you want to override the next sequence number.
    ///   - taxable: "Y/N" behavior. If true for any lines, include a `taxRate` label.
    ///   - taxRate: e.g. "Sales Tax 6%".
    ///   - memo: optional memo for the invoice.
    ///   - fileName: custom file name base (without extension).
    /// - Returns: URL to the generated CSV (in Temporary directory).
    @discardableResult
    static func exportQuickBooksSingleInvoice(
        entries: [Entry],
        client: Client,
        terms: String = "Net 30",
        invoiceDate: Date = Date(),
        dueDate: Date? = nil,
        forceInvoiceNo: String? = nil,
        taxable: Bool = false,
        taxRate: String? = nil,
        memo: String? = nil,
        fileName: String? = nil
    ) -> URL {
        let invNo = forceInvoiceNo ?? InvoiceNumberManager.nextAndAdvance()
        let invDateStr = qbDFUS.string(from: invoiceDate)
        let computedDue = dueDate ?? Calendar(identifier: .gregorian).date(byAdding: .day, value: 30, to: invoiceDate) ?? invoiceDate
        let dueStr = qbDFUS.string(from: computedDue)

        var rows: [String] = [qbHeader]

        for e in entries {
            let qty = String(format: "%.2f", e.hours)
            let rate = String(format: "%.2f", e.rate)
            let amount = String(format: "%.2f", e.hours * e.rate)
            let billingDate = e.billOnCompletion ? (e.completedAt ?? e.serviceDate) : e.serviceDate
            let serviceDate = qbDFUS.string(from: billingDate)

            let cols: [String] = [
                invNo,                                  // InvoiceNo *
                escapeQB(client.name),                  // Customer *
                invDateStr,                             // InvoiceDate *
                dueStr,                                 // DueDate *
                terms,                                  // Terms
                "",                                     // Location
                memo ?? "",                             // Memo
                escapeQB(e.service),                    // Item(Product/Service)
                escapeQB(descriptionWithSubtasks(e)),     // ItemDescription
                qty,                                    // ItemQuantity
                rate,                                   // ItemRate
                amount,                                 // ItemAmount *
                taxable ? "Y" : "N",                    // Taxable
                taxable ? (taxRate ?? "") : "",         // TaxRate (required if any "Y")
                "", "",                                 // Shipping address, Ship via
                "", "",                                 // Shipping date, Tracking no
                "",                                     // Shipping Charge
                serviceDate                              // Service Date
            ]
            rows.append(cols.joined(separator: ","))
        }

        let name = fileName ?? "\(client.name)_Invoice_\(invNo)"
        return writeCSVFile(named: name, rows: rows)
    }

    /// Export MULTIPLE QuickBooks invoices (e.g., one per month or per grouping).
    /// Each group gets its own auto-incremented invoice number (unless you override).
    ///
    /// - Parameter groups: array of (title, client, entries)
    /// - Returns: URLs to each generated CSV (Temporary directory).
    @discardableResult
    static func exportQuickBooksGrouped(
        groups: [(title: String, client: Client, entries: [Entry])],
        terms: String = "Net 30",
        taxable: Bool = false,
        taxRate: String? = nil,
        memoProvider: ((String, Client) -> String?)? = nil // optional memo per file
    ) -> [URL] {
        var urls: [URL] = []
        for g in groups {
            let invNo = InvoiceNumberManager.nextAndAdvance()
            let url = exportQuickBooksSingleInvoice(
                entries: g.entries,
                client: g.client,
                terms: terms,
                forceInvoiceNo: invNo,
                taxable: taxable,
                taxRate: taxRate,
                memo: memoProvider?(g.title, g.client),
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

    /// Escape for QuickBooks CSV cells (quoted by default when non-empty).
    private static func escapeQB(_ s: String) -> String {
        guard !s.isEmpty else { return "" }
        let q = s.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(q)\""
    }

    private static func descriptionWithSubtasks(_ entry: Entry) -> String {
        var desc = entry.detail
        if !entry.subtasks.isEmpty {
            let bullets = entry.subtasks.map { "• \($0.title)" }.joined(separator: "\n")
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
