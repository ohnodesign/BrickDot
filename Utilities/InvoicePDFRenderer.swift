// Utilities/InvoicePDFRenderer.swift
import UIKit
import SwiftData

/// Generates a professional PDF invoice from an Invoice model.
enum InvoicePDFRenderer {

    /// Generate a PDF file URL from an Invoice.
    /// - Parameters:
    ///   - invoice: The Invoice to render.
    ///   - profile: User profile for company info + logo.
    ///   - terms: Payment terms string.
    /// - Returns: URL to the generated PDF in the Temporary directory.
    static func render(
        invoice: Invoice,
        profile: UserProfile?,
        terms: String = "Due on receipt"
    ) -> URL {
        let entries = invoice.entriesList.sorted { $0.serviceDate < $1.serviceDate }
        let clientName = invoice.safeClientName
        let client = invoice.client

        let pageWidth: CGFloat = 612   // US Letter
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 50
        let contentWidth = pageWidth - margin * 2

        let pdfURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Invoice_\(invoice.number ?? invoice.title).pdf")

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        let data = renderer.pdfData { context in
            context.beginPage()
            var y: CGFloat = margin

            // ── Logo ──
            if let logoData = profile?.logoData, let logo = UIImage(data: logoData) {
                let maxLogoH: CGFloat = 60
                let maxLogoW: CGFloat = 180
                let aspect = logo.size.width / logo.size.height
                var w = maxLogoW
                var h = w / aspect
                if h > maxLogoH { h = maxLogoH; w = h * aspect }
                logo.draw(in: CGRect(x: margin, y: y, width: w, height: h))
                y += h + 12
            }

            // ── Company Info (left) + Invoice Info (right) ──
            let companyFont = UIFont.systemFont(ofSize: 10)
            let companyBoldFont = UIFont.boldSystemFont(ofSize: 14)
            let companyColor = UIColor.darkGray

            if let p = profile {
                let companyName = p.companyName.isEmpty ? p.displayName : p.companyName
                if !companyName.isEmpty {
                    drawText(companyName, at: CGPoint(x: margin, y: y), font: companyBoldFont, color: .black)
                    y += 20
                }
                var contactLines: [String] = []
                let addr = [p.addressLine1, p.addressLine2, [p.city, p.state, p.zip].filter { !$0.isEmpty }.joined(separator: ", ")]
                    .filter { !$0.isEmpty }
                contactLines.append(contentsOf: addr)
                if !p.email.isEmpty { contactLines.append(p.email) }
                if !p.phone.isEmpty { contactLines.append(p.phone) }
                for line in contactLines {
                    drawText(line, at: CGPoint(x: margin, y: y), font: companyFont, color: companyColor)
                    y += 14
                }
            }

            // Invoice title + number on the right
            let invTitleFont = UIFont.boldSystemFont(ofSize: 22)
            let invDetailFont = UIFont.systemFont(ofSize: 10)
            let invDetailColor = UIColor.darkGray

            let invTitle = "INVOICE"
            let invTitleSize = invTitle.size(withAttributes: [.font: invTitleFont])
            drawText(invTitle, at: CGPoint(x: pageWidth - margin - invTitleSize.width, y: margin), font: invTitleFont, color: .black)

            var rightY = margin + 30

            // Compute due date for header
            let dueDate: Date
            if terms.lowercased().contains("net 30") {
                dueDate = Calendar(identifier: .gregorian).date(byAdding: .day, value: 30, to: invoice.createdAt) ?? invoice.createdAt
            } else {
                dueDate = invoice.createdAt // "Due on receipt"
            }

            let rightInfoLines: [(String, String)] = [
                ("Invoice #", invoice.number ?? "—"),
                ("Date", formatDate(invoice.createdAt)),
                ("Due Date", formatDate(dueDate)),
                ("Terms", terms),
            ]
            for (label, value) in rightInfoLines {
                let text = "\(label): \(value)"
                let size = text.size(withAttributes: [.font: invDetailFont])
                drawText(text, at: CGPoint(x: pageWidth - margin - size.width, y: rightY), font: invDetailFont, color: invDetailColor)
                rightY += 14
            }

            y = max(y, rightY) + 20

            // ── Bill To ──
            let sectionFont = UIFont.boldSystemFont(ofSize: 9)
            let bodyFont = UIFont.systemFont(ofSize: 10)

            drawText("BILL TO", at: CGPoint(x: margin, y: y), font: sectionFont, color: .gray)
            y += 16
            drawText(clientName, at: CGPoint(x: margin, y: y), font: UIFont.boldSystemFont(ofSize: 12), color: .black)
            y += 18
            if let c = client {
                var clientLines: [String] = []
                if !c.contactName.isEmpty { clientLines.append(c.contactName) }
                if !c.email.isEmpty { clientLines.append(c.email) }
                if !c.phone.isEmpty { clientLines.append(c.phone) }
                for line in clientLines {
                    drawText(line, at: CGPoint(x: margin, y: y), font: bodyFont, color: companyColor)
                    y += 14
                }
            }

            y += 16

            // ── Line Items Table ──
            let colDate: CGFloat = margin
            let colService: CGFloat = margin + 62
            let colDesc: CGFloat = margin + 130
            let colQty: CGFloat = pageWidth - margin - 180
            let colRate: CGFloat = pageWidth - margin - 120
            let colAmount: CGFloat = pageWidth - margin - 60

            // Header row
            let headerFont = UIFont.boldSystemFont(ofSize: 9)
            let headerColor = UIColor.white
            let headerBg = UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1)

            let headerRect = CGRect(x: margin, y: y, width: contentWidth, height: 22)
            headerBg.setFill()
            UIBezierPath(roundedRect: headerRect, cornerRadius: 3).fill()

            let hY = y + 5
            drawText("Date", at: CGPoint(x: colDate + 6, y: hY), font: headerFont, color: headerColor)
            drawText("Service", at: CGPoint(x: colService, y: hY), font: headerFont, color: headerColor)
            drawText("Description", at: CGPoint(x: colDesc, y: hY), font: headerFont, color: headerColor)
            drawTextRight("Qty", rightEdge: colRate - 8, y: hY, font: headerFont, color: headerColor)
            drawTextRight("Rate", rightEdge: colAmount - 8, y: hY, font: headerFont, color: headerColor)
            drawTextRight("Amount", rightEdge: pageWidth - margin - 6, y: hY, font: headerFont, color: headerColor)

            y += 26

            // Item rows
            let rowFont = UIFont.systemFont(ofSize: 9)
            let rowBoldFont = UIFont.boldSystemFont(ofSize: 9)
            let altBg = UIColor(red: 0.96, green: 0.96, blue: 0.96, alpha: 1)
            let currencyCode = Locale.current.currency?.identifier ?? "USD"

            for (i, e) in entries.enumerated() {
                let rowH: CGFloat = 20

                // Check if we need a new page
                if y + rowH > pageHeight - margin - 80 {
                    context.beginPage()
                    y = margin
                }

                // Alternating row background
                if i % 2 == 1 {
                    altBg.setFill()
                    UIRectFill(CGRect(x: margin, y: y, width: contentWidth, height: rowH))
                }

                let rY = y + 5

                // Service date
                let billingDate = e.billOnCompletion ? (e.completedAt ?? e.serviceDate) : e.serviceDate
                drawText(formatShortDate(billingDate), at: CGPoint(x: colDate + 6, y: rY), font: rowFont, color: .black)

                drawText(e.service, at: CGPoint(x: colService, y: rY), font: rowFont, color: .black)

                // Truncate description to fit
                let descMaxW = colQty - colDesc - 8
                let desc = CSVExporter.descriptionWithSubtasks(e)
                drawTextTruncated(desc, at: CGPoint(x: colDesc, y: rY), maxWidth: descMaxW, font: rowFont, color: .darkGray)

                let qtyStr = e.hours > 0 ? formatQty(e.hours) : ""
                drawTextRight(qtyStr, rightEdge: colRate - 8, y: rY, font: rowFont, color: .black)
                drawTextRight(String(format: "%.2f", e.rate), rightEdge: colAmount - 8, y: rY, font: rowFont, color: .black)
                drawTextRight(String(format: "%.2f", e.hours * e.rate), rightEdge: pageWidth - margin - 6, y: rY, font: rowBoldFont, color: .black)
                y += rowH
            }

            // ── Totals ──
            y += 12
            let totalHours = entries.reduce(0.0) { $0 + $1.hours }
            let totalAmount = entries.reduce(0.0) { $0 + ($1.hours * $1.rate) }

            // Divider line
            UIColor.gray.setStroke()
            let divPath = UIBezierPath()
            divPath.move(to: CGPoint(x: colQty - 20, y: y))
            divPath.addLine(to: CGPoint(x: pageWidth - margin, y: y))
            divPath.lineWidth = 0.5
            divPath.stroke()
            y += 8

            let totalsFont = UIFont.systemFont(ofSize: 10)
            let totalsBoldFont = UIFont.boldSystemFont(ofSize: 12)

            drawTextRight("Total Hours:", rightEdge: colAmount - 8, y: y, font: totalsFont, color: .gray)
            drawTextRight(formatQty(totalHours), rightEdge: pageWidth - margin - 6, y: y, font: totalsFont, color: .black)
            y += 18

            drawTextRight("Total:", rightEdge: colAmount - 8, y: y, font: totalsBoldFont, color: .black)

            let nf = NumberFormatter()
            nf.numberStyle = .currency
            nf.currencyCode = currencyCode
            let totalStr = nf.string(from: NSNumber(value: totalAmount)) ?? String(format: "$%.2f", totalAmount)
            drawTextRight(totalStr, rightEdge: pageWidth - margin - 6, y: y, font: totalsBoldFont, color: .black)

            y += 30

            // ── Footer ──
            let footerFont = UIFont.systemFont(ofSize: 8)
            let footerText = "Generated by BrickDot • \(formatDate(Date()))"
            let footerSize = footerText.size(withAttributes: [.font: footerFont])
            drawText(footerText, at: CGPoint(x: (pageWidth - footerSize.width) / 2, y: pageHeight - margin + 10), font: footerFont, color: .lightGray)
        }

        try? data.write(to: pdfURL, options: .atomic)
        return pdfURL
    }

    // MARK: - Drawing Helpers

    private static func drawText(_ text: String, at point: CGPoint, font: UIFont, color: UIColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        (text as NSString).draw(at: point, withAttributes: attrs)
    }

    private static func drawTextRight(_ text: String, rightEdge: CGFloat, y: CGFloat, font: UIFont, color: UIColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: CGPoint(x: rightEdge - size.width, y: y), withAttributes: attrs)
    }

    private static func drawTextTruncated(_ text: String, at point: CGPoint, maxWidth: CGFloat, font: UIFont, color: UIColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let rect = CGRect(x: point.x, y: point.y, width: maxWidth, height: 14)
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        var drawAttrs = attrs
        drawAttrs[.paragraphStyle] = para
        (text as NSString).draw(in: rect, withAttributes: drawAttrs)
    }

    private static func formatDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        return df.string(from: date)
    }

    /// Compact date for line item rows, e.g. "Jul 2" or "Dec 15"
    private static func formatShortDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        return df.string(from: date)
    }

    private static func formatQty(_ hours: Double) -> String {
        if hours == hours.rounded() && hours >= 1 {
            return String(Int(hours))
        }
        return String(format: "%g", hours)
    }
}
