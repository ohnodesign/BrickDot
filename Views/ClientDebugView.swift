import SwiftUI
import SwiftData

struct ClientDebugView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Client.name) private var clients: [Client]

    @State private var name = "Acme"
    @State private var rateString = "125"
    @State private var log = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                    TextField("Rate", text: $rateString)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                    Button("Add") { add() }
                    Button("Delete All", role: .destructive) { deleteAll() }
                }
                .padding(.horizontal)

                List(clients) { c in
                    HStack {
                        Text(c.name)
                        Spacer()
                        Text(c.rate, format: .number.precision(.fractionLength(2))).monospaced()
                    }
                }

                ScrollView {
                    Text(log).font(.footnote).monospaced().frame(maxWidth: .infinity, alignment: .leading)
                        .padding().background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 8))
                }.frame(height: 140)
            }
            .navigationTitle("Client Debug")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh") { refresh() }
                }
            }
            .onAppear { refresh() }
        }
    }

    private func add() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let rate = Double(rateString.replacingOccurrences(of: ",", with: ".")) ?? 0
        do {
            let c = Client(name: trimmed, rate: rate)
            ctx.insert(c)
            try ctx.save()
            log.append("✅ Inserted \(trimmed) @ \(rate)\n")
        } catch {
            log.append("❌ Save failed: \(String(describing: error))\n")
        }
    }

    private func deleteAll() {
        do {
            for c in clients { ctx.delete(c) }
            try ctx.save()
            log.append("🗑️ Deleted all\n")
        } catch {
            log.append("❌ Delete failed: \(error.localizedDescription)\n")
        }
    }

    private func refresh() {
        log.append("🔄 Count = \(clients.count)\n")
    }
}
