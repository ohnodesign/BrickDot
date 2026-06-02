// RootView.swift
import SwiftUI
import SwiftData

enum RootTab: Hashable { case home, profile, clients, stats, settings, log, export }

extension Notification.Name {
    static let goHome = Notification.Name("goHome")
}

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
    @State private var selectedTab: RootTab = .profile
    @State private var showingHome = true
    @State private var showQuickCapture = false

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                NavigationStack {
                    ProfileView()
                        .toolbar { homeButton }
                }
                .environment(\.modelContext, ctx)
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(RootTab.profile)

                NavigationStack {
                    ClientListView()
                        .toolbar { homeButton }
                }
                .environment(\.modelContext, ctx)
                .tabItem { Label("Clients", systemImage: "person.2") }
                .tag(RootTab.clients)

                NavigationStack {
                    StatsPageView()
                        .toolbar { homeButton }
                }
                .environment(\.modelContext, ctx)
                .tabItem {
                    Image(systemName: "chart.bar")
                        .symbolRenderingMode(.hierarchical)
                    Text("Stats")
                }
                .tag(RootTab.stats)

                NavigationStack {
                    SettingsView()
                        .toolbar { homeButton }
                }
                .environment(\.modelContext, ctx)
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(RootTab.settings)

                NavigationStack {
                    LogView()
                        .toolbar { homeButton }
                }
                .environment(\.modelContext, ctx)
                .tabItem { Label("Log", systemImage: "doc.text") }
                .tag(RootTab.log)

                NavigationStack {
                    ExportView()
                        .toolbar { homeButton }
                }
                .environment(\.modelContext, ctx)
                .tabItem { Label("Export", systemImage: "square.and.arrow.up") }
                .tag(RootTab.export)
            }
            .onChange(of: selectedTab) { _, _ in
                if showingHome { withAnimation { showingHome = false } }
            }

            if showingHome {
                VStack(spacing: 0) {
                    NavigationStack {
                        HomeView()
                    }
                    .environment(\.modelContext, ctx)

                    Divider()
                    tabBarMirror
                }
                .transition(.opacity)
                .ignoresSafeArea(.keyboard)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .goHome)) { _ in
            withAnimation { showingHome = true }
        }
        .sheet(isPresented: $showQuickCapture) {
            QuickAddView(onSaved: { showQuickCapture = false })
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    @ToolbarContentBuilder
    private var homeButton: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                NotificationCenter.default.post(name: .goHome, object: nil)
            } label: {
                Image(systemName: "house")
                    .imageScale(.large)
                    .foregroundStyle(Color(.darkGray))
                    .accessibilityLabel("Home")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showQuickCapture = true } label: {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.79, green: 0.25, blue: 0.25))
                        .frame(width: 28, height: 28)
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Quick Capture")
            }
        }
    }

    private var tabBarMirror: some View {
        HStack {
            tabButton("Profile", icon: "person.crop.circle", tab: .profile)
            tabButton("Clients", icon: "person.2", tab: .clients)
            tabButton("Stats", icon: "chart.bar", tab: .stats)
            tabButton("Settings", icon: "gear", tab: .settings)
            tabButton("More", icon: "ellipsis", tab: nil)
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
        .background(Color(.systemBackground))
    }

    private func tabButton(_ label: String, icon: String, tab: RootTab?) -> some View {
        Button {
            if let tab {
                selectedTab = tab
                withAnimation { showingHome = false }
            } else {
                selectedTab = .log
                withAnimation { showingHome = false }
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(label)
                    .font(.caption2)
            }
            .foregroundStyle(Color(.secondaryLabel))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
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
    @Environment(\.appTheme) private var theme
    @Query(sort: \Entry.serviceDate, order: .reverse) private var allEntries: [Entry]
    @Query(sort: \Client.name) private var allClients: [Client]
    @Query private var profiles: [UserProfile]
    private var profile: UserProfile? { profiles.first }

    @State private var selection: SidebarDestination? = .home
    @State private var showNewEntry = false
    @State private var showFullNewEntry = false
    @State private var detailPath = NavigationPath()
    @State private var showSearch = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                // Quick Capture
                Section {
                    Button { showNewEntry = true } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(theme.quickCapture)
                                    .frame(width: 36, height: 36)
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Quick Capture")
                                    .font(.headline)
                                    .foregroundStyle(theme.primaryText)
                                Text("Log work in seconds")
                                    .font(.subheadline)
                                    .foregroundStyle(theme.secondaryText)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }

                // Today summary card
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: "sun.max.fill")
                                .foregroundStyle(theme.overdue)
                            Text("TODAY")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(theme.overdue)
                        }

                        SidebarStatRow(icon: "calendar", tint: theme.dueToday, value: "\(dueTodayCount)", label: "Due Today")
                        SidebarStatRow(icon: "timer", tint: theme.running, value: "\(timersRunning)", label: "Running")
                        SidebarStatRow(icon: "dollarsign.circle.fill", tint: theme.revenue, value: potentialRevenue.shortCurrency, label: "Potential Revenue")
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }

                // Navigation
                Section {
                    NavigationLink(value: SidebarDestination.profile) {
                        Label("Profile", systemImage: "person.crop.circle")
                    }
                    NavigationLink(value: SidebarDestination.allClients) {
                        Label("Clients", systemImage: "person.2")
                    }
                    NavigationLink(value: SidebarDestination.stats) {
                        Label("Stats", systemImage: "chart.bar")
                    }
                    NavigationLink(value: SidebarDestination.log) {
                        Label("Log", systemImage: "doc.text")
                    }
                    NavigationLink(value: SidebarDestination.export) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    NavigationLink(value: SidebarDestination.settings) {
                        Label("Settings", systemImage: "gear")
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
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
                ToolbarItem(placement: .principal) {
                    Text(profile?.companyName.isEmpty == false ? profile!.companyName : "BrickDot")
                        .font(.headline)
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

    private var potentialRevenue: Double {
        dueTodayEntries.reduce(0) { $0 + ($1.hours * $1.rate) }
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

// MARK: - Sidebar Stat Row

private struct SidebarStatRow: View {
    let icon: String
    let tint: Color
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(tint)
                .frame(width: 24)
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
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
                    .fill(isSelected ? tint : Color(.systemGray6))
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

