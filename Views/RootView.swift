// RootView.swift
import SwiftUI
import SwiftData

enum RootTab: Hashable { case home, stats, new, clients, log, export }

struct RootView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            iPadRootView()
        } else {
            iPhoneRootView()
        }
    }
}

// MARK: - iPhone (Tab Bar)

private struct iPhoneRootView: View {
    @Environment(\.modelContext) private var ctx
    @State private var selectedTab: RootTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView()
            }
            .environment(\.modelContext, ctx)
            .tabItem { Label("Home", systemImage: "house") }
            .tag(RootTab.home)

            NavigationStack {
                StatsPageView()
            }
            .environment(\.modelContext, ctx)
            .tabItem { Label("Stats", systemImage: "chart.bar.fill") }
            .tag(RootTab.stats)

            NavigationStack {
                QuickAddView(onSaved: { selectedTab = .home })
            }
            .environment(\.modelContext, ctx)
            .tabItem { Label("New", systemImage: "plus.circle") }
            .tag(RootTab.new)

            NavigationStack {
                ClientListView()
            }
            .environment(\.modelContext, ctx)
            .tabItem { Label("Clients", systemImage: "person.2") }
            .tag(RootTab.clients)

            NavigationStack {
                LogView()
            }
            .environment(\.modelContext, ctx)
            .tabItem { Label("Log", systemImage: "doc.text") }
            .tag(RootTab.log)

            NavigationStack {
                ExportView()
            }
            .environment(\.modelContext, ctx)
            .tabItem { Label("Export", systemImage: "square.and.arrow.up") }
            .tag(RootTab.export)
        }
    }
}

// MARK: - iPad (Sidebar)

private enum SidebarDestination: Hashable {
    case home
    case overdue
    case dueToday
    case running
    case thisWeek
    case stats
    case log
    case export
    case newEntry
    case allClients
    case client(PersistentIdentifier)
    case profile
    case settings
}

private struct iPadRootView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Entry.serviceDate, order: .reverse) private var allEntries: [Entry]
    @Query(sort: \Client.name) private var allClients: [Client]

    @State private var selection: SidebarDestination? = .home
    @State private var showNewEntry = false
    @State private var showFullNewEntry = false
    @State private var detailPath = NavigationPath()
    @State private var showSearch = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                // Quick Add
                Section {
                    Button { showNewEntry = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "hare.fill")
                                .font(.title2)
                            Text("Quick Add")
                                .font(.headline.weight(.bold))
                        }
                        .foregroundStyle(Color(red: 0.75, green: 0.60, blue: 0.0))
                    }
                    .buttonStyle(.plain)
                }

                // Dashboard cards (Reminders-style 2x2 grid)
                Section {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        SidebarCard(
                            icon: "exclamationmark.triangle.fill",
                            label: "Overdue",
                            value: "\(overdueCount)",
                            tint: .red,
                            destination: .overdue,
                            selection: $selection
                        )
                        SidebarCard(
                            icon: "sun.max.fill",
                            label: "Today",
                            value: "\(dueTodayCount)",
                            tint: .orange,
                            destination: .dueToday,
                            selection: $selection
                        )
                        SidebarCard(
                            icon: "timer",
                            label: "Running",
                            value: "\(timersRunning)",
                            tint: Color.brick,
                            destination: .running,
                            selection: $selection
                        )
                        SidebarCard(
                            icon: "dollarsign.circle.fill",
                            label: "This Week",
                            value: weekAmount.shortCurrency,
                            tint: .green,
                            destination: .thisWeek,
                            selection: $selection
                        )
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }

                // Clients
                Section {
                    NavigationLink(value: SidebarDestination.allClients) {
                        Label("All Clients", systemImage: "person.2")
                    }

                    ForEach(topClients, id: \.persistentModelID) { client in
                        NavigationLink(value: SidebarDestination.client(client.persistentModelID)) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(client.accentColor)
                                    .frame(width: 10, height: 10)
                                Text(client.name)
                                Spacer()
                                let count = client.entriesList.filter { $0.status != .done }.count
                                if count > 0 {
                                    Text("\(count)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                // Tools
                Section("Tools") {
                    NavigationLink(value: SidebarDestination.stats) {
                        Label("Stats", systemImage: "chart.bar.fill")
                    }
                    NavigationLink(value: SidebarDestination.log) {
                        Label("Log", systemImage: "doc.text")
                    }
                    NavigationLink(value: SidebarDestination.export) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }

                // Profile & Settings
                Section {
                    NavigationLink(value: SidebarDestination.profile) {
                        Label("Profile", systemImage: "person.crop.circle")
                    }
                    NavigationLink(value: SidebarDestination.settings) {
                        Label("Settings", systemImage: "gear")
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("BrickDot")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        detailPath = NavigationPath()
                        selection = .home
                    } label: {
                        Image(systemName: "house")
                            .imageScale(.large)
                                .foregroundStyle(Color(.darkGray))
                    }
                }
            }
        } detail: {
            detailView
                .environment(\.modelContext, ctx)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showFullNewEntry = true } label: {
                            Image(systemName: "plus.circle")
                                .imageScale(.large)
                                .foregroundStyle(Color(.darkGray))
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showSearch = true } label: {
                            Image(systemName: "magnifyingglass")
                                .imageScale(.large)
                                .foregroundStyle(Color(.darkGray))
                        }
                    }
                }
                .sheet(isPresented: $showSearch) {
                    SearchView()
                        .environment(\.modelContext, ctx)
                }
        }
        .onChange(of: selection) { _, _ in
            detailPath = NavigationPath()
        }
        .sheet(isPresented: $showNewEntry) {
            QuickAddView(onSaved: {
                showNewEntry = false
                selection = .home
            })
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showFullNewEntry) {
            NavigationStack {
                NewEntryView(onSaved: {
                    showFullNewEntry = false
                    selection = .home
                })
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Detail View

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .home, .none:
            NavigationStack(path: $detailPath) { HomeView() }
        case .overdue:
            EntriesListView(title: "Overdue", entries: overdueEntries)
        case .dueToday:
            EntriesListView(title: "Due Today", entries: dueTodayEntries)
        case .running:
            EntriesListView(title: "Running Timers", entries: runningEntries)
        case .thisWeek:
            EntriesListView(title: "This Week", entries: thisWeekEntries)
        case .stats:
            StatsPageView()
        case .log:
            LogView()
        case .export:
            ExportView()
        case .newEntry:
            NewEntryView(onSaved: { selection = .home })
        case .allClients:
            ClientListView()
        case .client(let id):
            if let client = allClients.first(where: { $0.persistentModelID == id }) {
                ClientDetailView(client: client)
            } else {
                Text("Client not found").foregroundStyle(.secondary)
            }
        case .profile:
            ProfileView()
        case .settings:
            SettingsView()
        }
    }

    // MARK: - Sidebar Data

    private var cal: Calendar { Calendar.current }
    private var todayStart: Date { cal.startOfDay(for: Date()) }
    private var todayEnd: Date { cal.date(byAdding: DateComponents(day: 1, second: -1), to: todayStart) ?? Date() }

    private var openEntries: [Entry] {
        allEntries.filter { $0.status != .done }
    }

    private var overdueCount: Int {
        openEntries.filter { e in
            guard let due = e.dueDate else { return false }
            return due < todayStart
        }.count
    }

    private var overdueEntries: [Entry] {
        openEntries.filter { e in
            guard let due = e.dueDate else { return false }
            return due < todayStart
        }
    }

    private var dueTodayCount: Int {
        openEntries.filter { e in
            guard let due = e.dueDate else { return false }
            return due >= todayStart && due <= todayEnd
        }.count
    }

    private var dueTodayEntries: [Entry] {
        openEntries.filter { e in
            guard let due = e.dueDate else { return false }
            return due >= todayStart && due <= todayEnd
        }
    }

    private var timersRunning: Int {
        allEntries.filter { $0.status == .inProgress && $0.timerStartedAt != nil }.count
    }

    private var runningEntries: [Entry] {
        allEntries.filter { $0.status == .inProgress && $0.timerStartedAt != nil }
    }

    private var topClients: [Client] {
        Array(allClients
            .sorted { a, b in
                let aOpen = a.entriesList.filter { $0.status != .done }.count
                let bOpen = b.entriesList.filter { $0.status != .done }.count
                return aOpen > bOpen
            }
            .prefix(5))
    }

    private var weekAmount: Double {
        let start = Date().bdStartOfWeek
        let end = Date().bdEndOfWeek
        return allEntries
            .filter { $0.status == .done && ($0.completedAt ?? $0.serviceDate) >= start && ($0.completedAt ?? $0.serviceDate) <= end }
            .reduce(0) { $0 + ($1.hours * $1.rate) }
    }

    private var thisWeekEntries: [Entry] {
        let start = Date().bdStartOfWeek
        let end = Date().bdEndOfWeek
        return allEntries.filter { e in
            let d = e.completedAt ?? e.serviceDate
            return e.status == .done && d >= start && d <= end
        }
    }

}

// MARK: - Sidebar Card (Reminders-style)

private struct SidebarCard: View {
    let icon: String
    let label: String
    let value: String
    let tint: Color
    let destination: SidebarDestination
    @Binding var selection: SidebarDestination?

    private var isSelected: Bool { selection == destination }

    var body: some View {
        Button {
            selection = destination
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(isSelected ? .white : tint)
                    Spacer()
                    Text(value)
                        .font(.title.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? .white : .primary)
                }
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? tint : tint.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }
}

private extension Double {
    var shortCurrency: String {
        let code = Locale.current.currency?.identifier ?? "USD"
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = code
        nf.maximumFractionDigits = 0
        return nf.string(from: NSNumber(value: self)) ?? "$\(Int(self))"
    }
}
