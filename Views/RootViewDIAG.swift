import SwiftUI
import SwiftData

struct RootViewDIAG: View {
    @Query(sort: \Client.name) private var clients: [Client]
    @Query(sort: \Entry.serviceDate, order: .reverse) private var entries: [Entry]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("BrickDot DIAG")
                    Text("Clients: \(clients.count)")
                    Text("Entries: \(entries.count)")
                }
                Section("Go to…") {
                    NavigationLink("HomeView", destination: HomeView())
                    NavigationLink("NewEntryView", destination: NewEntryView())
                    NavigationLink("ClientListView", destination: ClientListView())
                }
            }
            .navigationTitle("Diagnostics")
        }
    }
}
