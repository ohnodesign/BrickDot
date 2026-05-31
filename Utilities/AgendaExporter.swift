// Utilities/AgendaExporter.swift
import Foundation

struct AgendaExporter {

    // MARK: - Public API

    /// Export a CSV agenda. To Do rows have blank Hours/Amount. In Progress shows Hours & Amount.
    /// Columns: Client, Status, Service, Description, Hours, Rate, Amount
    static func exportCSV(
        todo: [Entry],
        inProgress: [Entry],
        fileName: String = defaultCSVName()
    ) -> URL {
        let headers = ["Client","Status","Service","Description","Hours","Rate","Amount"]
        var rows: [String] = [headers.joined(separator: ",")]

        // Group by client for nicer output
        let groupedTodo = groupByClient(todo)
        let groupedIP   = groupByClient(inProgress)

        let clientNames = Set(groupedTodo.keys).union(groupedIP.keys).sorted()

        for (idx, clientName) in clientNames.enumerated() {
            // Insert a blank line between clients (optional, keeps spreadsheet readable)
            if idx > 0 { rows.append("") }

            if let items = groupedTodo[clientName], !items.isEmpty {
                for e in items {
                    let cols: [String] = [
                        escape(clientName),
                        "To Do",
                        escape(e.service),
                        escape(e.detail),
                        "",                                      // Hours blank for To Do
                        "",                                      // Rate blank for To Do
                        ""                                       // Amount blank for To Do
                    ]
                    rows.append(cols.joined(separator: ","))
                }
            }

            if let items = groupedIP[clientName], !items.isEmpty {
                for e in items {
                    let hours = String(format: "%.2f", e.hours)
                    let rate  = String(format: "%.2f", e.rate)
                    let amount = String(format: "%.2f", e.hours * e.rate)
                    let cols: [String] = [
                        escape(clientName),
                        "In Progress",
                        escape(e.service),
                        escape(e.detail),
                        hours,
                        rate,
                        amount
                    ]
                    rows.append(cols.joined(separator: ","))
                }
            }
        }

        let csv = rows.joined(separator: "\n") + "\n"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeFilename(fileName) + ".csv")
        try? csv.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }

    /// Export a clean Markdown agenda grouped by client.
    /// To Do shows no hours. In Progress shows hours in parentheses.
    static func exportMarkdown(
        todo: [Entry],
        inProgress: [Entry],
        fileName: String = defaultMDName()
    ) -> URL {
        var out: [String] = []
        out.append("# Team Agenda — \(todayLabel())")
        out.append("")

        let groupedTodo = groupByClient(todo)
        let groupedIP   = groupByClient(inProgress)
        let clientNames = Set(groupedTodo.keys).union(groupedIP.keys).sorted()

        if clientNames.isEmpty {
            out.append("_No items_")
        } else {
            for clientName in clientNames {
                out.append("## \(clientName)")

                if let items = groupedTodo[clientName], !items.isEmpty {
                    out.append("### To Do")
                    for e in items {
                        let desc = e.detail.isEmpty ? "" : " — “\(sanitizeMD(e.detail))”"
                        out.append("• \(sanitizeMD(e.service))\(desc)")
                    }
                    out.append("") // spacing
                }

                if let items = groupedIP[clientName], !items.isEmpty {
                    out.append("### In Progress")
                    for e in items {
                        let desc = e.detail.isEmpty ? "" : " — “\(sanitizeMD(e.detail))”"
                        let hours = e.hours > 0 ? " (\(formatHours(e.hours)))" : ""
                        out.append("• \(sanitizeMD(e.service))\(desc)\(hours)")
                    }
                    out.append("") // spacing
                }
            }
        }

        let md = out.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeFilename(fileName) + ".md")
        try? md.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Helpers

    private static func groupByClient(_ entries: [Entry]) -> [String: [Entry]] {
        let grouped = Dictionary(grouping: entries) { $0.clientName }
        // Sort each group by service then detail for stable output
        var sorted: [String: [Entry]] = [:]
        for (k, v) in grouped {
            sorted[k] = v.sorted {
                if $0.service != $1.service { return $0.service < $1.service }
                return $0.detail < $1.detail
            }
        }
        return sorted
    }

    private static func escape(_ value: String) -> String {
        var v = value.replacingOccurrences(of: "\"", with: "\"\"")
        if v.contains(",") || v.contains("\n") || v.contains("\"") {
            v = "\"\(v)\""
        }
        return v
    }

    private static func sanitizeMD(_ value: String) -> String {
        // Keep it simple: escape Markdown pipes/backticks; quotes are fine (we wrap with fancy quotes already)
        value.replacingOccurrences(of: "|", with: "\\|")
             .replacingOccurrences(of: "`", with: "\\`")
    }

    private static func safeFilename(_ raw: String) -> String {
        raw.replacingOccurrences(of: "/", with: "-")
           .replacingOccurrences(of: ":", with: "-")
           .replacingOccurrences(of: "\"", with: "'")
           .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func todayLabel() -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        return df.string(from: Date())
    }

    private static func defaultCSVName() -> String {
        "Team_Agenda_\(DateFormatter.iso8601Day.string(from: Date()))"
    }

    private static func defaultMDName() -> String {
        "Team_Agenda_\(DateFormatter.iso8601Day.string(from: Date()))"
    }

    private static func formatHours(_ h: Double) -> String {
        String(format: "%.2f", h) + "h"
    }
}
