// Views/InvoiceDetailView.swift
import SwiftUI
import SwiftData

struct InvoiceDetailView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.modelContext) private var ctx
    @Bindable var invoice: Invoice

    @Query private var profiles: [UserProfile]
    private var profile: UserProfile? { profiles.first }

    @State private var sharePayload: InvoiceSharePayload?
    @State private var showDocumentExport = false
    @State private var exportFileURL: URL? = nil
    @State private var showDeleteConfirm = false
    @Environment(\.dismiss) private var dismiss

    // Sorted entries on this invoice
    private var items: [Entry] {
        invoice.entriesList.sorted { $0.serviceDate < $1.serviceDate }
    }

    private var totalHours: Double {
        items.reduce(0) { $0 + $1.hours }
    }

    private var totalAmount: Double {
        items.reduce(0) { $0 + ($1.hours * $1.rate) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Header — editable title / number / date
                InvoiceSectionTitle("Invoice")
                HStack {
                    Text("Title")
                    Spacer()
                    TextField("Invoice title", text: $invoice.title)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.words)
                        .onChange(of: invoice.title) { _, _ in try? ctx.save() }
                }
                HStack {
                    Text("Number")
                    Spacer()
                    TextField("e.g. 1001", text: Binding(
                        get: { invoice.number ?? "" },
                        set: { invoice.number = $0.isEmpty ? nil : $0; try? ctx.save() }
                    ))
                    .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Date")
                    Spacer()
                    DatePicker("", selection: $invoice.createdAt, displayedComponents: .date)
                        .labelsHidden()
                        .onChange(of: invoice.createdAt) { _, _ in try? ctx.save() }
                }
                InvoiceKeyValueRow("Client", invoice.safeClientName)

                Divider()

                // Export buttons
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Button {
                            let url = InvoicePDFRenderer.render(
                                invoice: invoice,
                                profile: profile,
                                terms: "Due on receipt"
                            )
                            sharePayload = InvoiceSharePayload(items: [url])
                        } label: {
                            Label("Share PDF", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            let url = InvoicePDFRenderer.render(
                                invoice: invoice,
                                profile: profile,
                                terms: "Due on receipt"
                            )
                            exportFileURL = url
                            showDocumentExport = true
                        } label: {
                            Label("Save to Files", systemImage: "folder")
                        }
                        .buttonStyle(.bordered)
                    }

                    if let client = invoice.client {
                        Button {
                            let url = CSVExporter.exportQuickBooksSingleInvoice(
                                entries: items,
                                client: client,
                                terms: "Due on receipt",
                                invoiceDate: invoice.createdAt,
                                forceInvoiceNo: invoice.number
                            )
                            sharePayload = InvoiceSharePayload(items: [url])
                        } label: {
                            Label("Export CSV", systemImage: "tablecells")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Divider()

                // Items
                InvoiceSectionTitle("Items (\(items.count))")
                if items.isEmpty {
                    Text("No entries on this invoice.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 12) {
                        ForEach(items, id: \.persistentModelID) { e in
                            NavigationLink {
                                EditEntryView(entry: e)
                            } label: {
                                InvoiceItemRow(entry: e)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                        .padding(.vertical, -6)
                    }
                }

                Divider()

                // Totals
                InvoiceSectionTitle("Totals")
                InvoiceKeyValueRow("Hours", totalHours, precision: 2)
                HStack {
                    Text("Amount")
                    Spacer()
                    Text(totalAmount, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                        .fontWeight(.semibold)
                }

                Divider()

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    HStack {
                        Spacer()
                        Label("Delete Invoice", systemImage: "trash")
                        Spacer()
                    }
                }
                .padding(.vertical, 8)
            }
            .padding(.horizontal)
            .padding(.top, 12)
        }
        .navigationTitle(invoice.title)
        .alert("Delete Invoice?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                for entry in invoice.entriesList {
                    entry.invoice = nil
                }
                ctx.delete(invoice)
                try? ctx.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Delete \(invoice.title)? The \(items.count) entries on this invoice will be kept but unlinked from this invoice.")
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(activityItems: payload.items).ignoresSafeArea()
        }
        .sheet(isPresented: $showDocumentExport) {
            if let url = exportFileURL {
                DocumentExportPicker(url: url)
            }
        }
    }
}

private struct InvoiceSharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

// MARK: - Subviews (fileprivate to avoid cross-file symbol collisions)

fileprivate struct InvoiceSectionTitle: View {
    let text: String
    init(_ t: String) { self.text = t }
    var body: some View {
        Text(text.uppercased())
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }
}

fileprivate struct InvoiceKeyValueRow: View {
    let title: String
    let valueText: String

    init(_ title: String, _ value: String) {
        self.title = title
        self.valueText = value
    }
    init(_ title: String, _ value: Date, asDate: Bool) {
        self.title = title
        self.valueText = DateFormatter.localizedString(from: value, dateStyle: .medium, timeStyle: .none)
    }
    init(_ title: String, _ value: Double, precision: Int = 2) {
        self.title = title
        self.valueText = String(format: "%.\(precision)f", value)
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(valueText).foregroundStyle(.secondary)
        }
    }
}

fileprivate struct InvoiceItemRow: View {
    let entry: Entry
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.service).font(.headline)
                Spacer()
                Text(entry.serviceDate, format: .dateTime.year().month().day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !entry.detail.isEmpty {
                Text(entry.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 8) {
                Text("\(entry.hours, specifier: "%.2f")h")
                Text("×")
                Text(entry.rate, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                Spacer()
                Text(entry.hours * entry.rate,
                     format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                    .fontWeight(.semibold)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
