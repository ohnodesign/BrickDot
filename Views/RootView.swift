// RootView.swift
import SwiftUI
import SwiftData
import UIKit

enum RootTab: Hashable { case home, profile, clients, stats, more, coach }
enum MoreDestination: Hashable { case settings, log, export }

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
    @State private var morePath = NavigationPath()

    /// The BrickDot brand red, used for the Quick Capture button and the
    /// selected tab-bar tint.
    private let brandRed = Color(red: 0.79, green: 0.25, blue: 0.25)

    init() {
        // Tint only the tab bar's selected item the BrickDot red, without
        // changing the app's blue accent used elsewhere in page content.
        let red = UIColor(red: 0.79, green: 0.25, blue: 0.25, alpha: 1)
        let item = UITabBarItemAppearance()
        item.selected.iconColor = red
        item.selected.titleTextAttributes = [.foregroundColor: red]

        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.stackedLayoutAppearance = item
        appearance.inlineLayoutAppearance = item
        appearance.compactInlineLayoutAppearance = item

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

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
                    CoachView()
                        .toolbar { homeButton }
                }
                .environment(\.modelContext, ctx)
                .tabItem { Label("Coach", systemImage: "brain.head.profile") }
                .tag(RootTab.coach)

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

                NavigationStack(path: $morePath) {
                    MoreListView()
                        .toolbar { homeButton }
                        .navigationDestination(for: MoreDestination.self) { dest in
                            switch dest {
                            case .settings:
                                SettingsView().toolbar { homeButton }
                            case .log:
                                LogView().toolbar { homeButton }
                            case .export:
                                ExportView().toolbar { homeButton }
                            }
                        }
                }
                .environment(\.modelContext, ctx)
                .tabItem { Label("More", systemImage: "ellipsis") }
                .tag(RootTab.more)
            }
            .onChange(of: selectedTab) { _, _ in
                if showingHome { withAnimation { showingHome = false } }
            }
            .runningTimerBarAttachment()

            if showingHome {
                VStack(spacing: 0) {
                    NavigationStack {
                        HomeView()
                    }
                    .environment(\.modelContext, ctx)

                    RunningTimerBar()
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)

                    tabBarMirror
                }
                .background(Color(.systemBackground).ignoresSafeArea())
                .transition(.opacity)
                .ignoresSafeArea(.keyboard)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .goHome)) { _ in
            // Resign any active text field (e.g. the Coach input) before the
            // home overlay covers it, otherwise the keyboard is left stranded
            // with nothing to dismiss it.
            dismissKeyboard()
            withAnimation { showingHome = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToSection)) { note in
            guard let raw = note.userInfo?["action"] as? String,
                  let action = SetupAction(rawValue: raw) else { return }
            switch action {
            case .profile:
                selectedTab = .profile
            case .services, .reminders:
                selectedTab = .more
                morePath = NavigationPath([MoreDestination.settings])
            case .clients:
                selectedTab = .clients
            case .importData:
                selectedTab = .more
                morePath = NavigationPath([MoreDestination.export])
            }
            withAnimation { showingHome = false }
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
        HStack(spacing: 0) {
            tabButton("Profile", icon: "person.crop.circle", tab: .profile)
            tabButton("Coach", icon: "brain.head.profile", tab: .coach)
            tabButton("Clients", icon: "person.2", tab: .clients)
            tabButton("Stats", icon: "chart.bar", tab: .stats)
            tabButton("More", icon: "ellipsis", tab: .more)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private func go(_ tab: RootTab) {
        dismissKeyboard()
        selectedTab = tab
        withAnimation { showingHome = false }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }

    private func tabButton(_ label: String, icon: String, tab: RootTab) -> some View {
        Button {
            go(tab)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .symbolVariant(.fill)
                Text(label)
                    .font(.caption2)
            }
            .foregroundStyle(Color(.label))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - More List (Settings / Log / Export)

private struct MoreListView: View {
    var body: some View {
        List {
            NavigationLink(value: MoreDestination.settings) {
                Label("Settings", systemImage: "gear")
            }
            NavigationLink(value: MoreDestination.log) {
                Label("Log", systemImage: "doc.text")
            }
            NavigationLink(value: MoreDestination.export) {
                Label("Export", systemImage: "square.and.arrow.up")
            }
        }
        .navigationTitle("More")
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
    case savedSearch(PersistentIdentifier)
    case coach
    case profile
    case settings
}

private struct iPadRootView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.appTheme) private var theme
    @Query(sort: \Entry.serviceDate, order: .reverse) private var allEntries: [Entry]
    @Query(sort: \Client.name) private var allClients: [Client]
    @Query(sort: \SavedSearch.createdAt) private var savedSearches: [SavedSearch]
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
                                    .fill(Color(red: 0.79, green: 0.25, blue: 0.25))
                                    .frame(width: 40, height: 40)
                                Image(systemName: "plus")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            Text("Quick Capture")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(theme.primaryText)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }

                // Today summary card
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: "sun.max.fill")
                                .font(.subheadline)
                                .foregroundStyle(theme.overdue)
                            Text("TODAY")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(theme.overdue)
                        }

                        SidebarStatRow(icon: "calendar", tint: theme.dueToday, value: "\(dueTodayCount)", label: "Due Today")
                        SidebarStatRow(icon: "timer", tint: theme.running, value: "\(timersRunning)", label: "Running")
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
                    .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                }

                // Saved Searches — one-tap shortcuts to a saved EntryListView
                // filter combination, created from the Filter row on Home.
                if !savedSearches.isEmpty {
                    Section {
                        ForEach(savedSearches, id: \.persistentModelID) { search in
                            Button {
                                selection = .savedSearch(search.persistentModelID)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "bookmark.fill")
                                        .foregroundStyle(theme.accent)
                                        .frame(width: 20)
                                    Text(search.name)
                                        .foregroundStyle(theme.primaryText)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    ctx.delete(search)
                                    try? ctx.save()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        Text("SAVED SEARCHES")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(theme.secondaryText)
                    }
                }

                // Navigation
                Section {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        sidebarNavTile("Home", icon: "house", dest: .home)
                        sidebarNavTile("Clients", icon: "person.2", dest: .allClients)
                        sidebarNavTile("Coach", icon: "brain.head.profile", dest: .coach)
                        sidebarNavTile("Stats", icon: "chart.bar", dest: .stats)
                        sidebarNavTile("Log", icon: "doc.text", dest: .log)
                        sidebarNavTile("Export", icon: "square.and.arrow.up", dest: .export)
                        sidebarNavTile("Profile", icon: "person.crop.circle", dest: .profile)
                        sidebarNavTile("Settings", icon: "gear", dest: .settings)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
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
                    Text(profile.flatMap { $0.companyName.isEmpty ? nil : $0.companyName } ?? "BrickDot")
                        .font(.headline)
                }
            }
        } detail: {
            detailView
                .environment(\.modelContext, ctx)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showFullNewEntry = true } label: {
                            ZStack {
                                Circle()
                                    .fill(Color(red: 0.79, green: 0.25, blue: 0.25))
                                    .frame(width: 28, height: 28)
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                            }
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
        .safeAreaInset(edge: .bottom) {
            RunningTimerBar()
                .frame(maxWidth: 440)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
        .onChange(of: selection) { _, _ in
            detailPath = NavigationPath()
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToSection)) { note in
            guard let raw = note.userInfo?["action"] as? String,
                  let action = SetupAction(rawValue: raw) else { return }
            switch action {
            case .profile:              selection = .profile
            case .services, .reminders: selection = .settings
            case .clients:              selection = .allClients
            case .importData:           selection = .export
            }
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
            .presentationContentInteraction(.scrolls)
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
        case .savedSearch(let id):
            if let search = savedSearches.first(where: { $0.persistentModelID == id }) {
                EntriesListView(title: search.name, entries: search.matchingEntries(in: allEntries))
            } else {
                Text("Saved search not found").foregroundStyle(.secondary)
            }
        case .coach:
            CoachView()
        case .profile:
            ProfileView()
        case .settings:
            SettingsView()
        }
    }

    // MARK: - Sidebar Nav Tile

    private func sidebarNavTile(_ label: String, icon: String, dest: SidebarDestination) -> some View {
        Button {
            selection = dest
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .frame(height: 40)
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selection == dest ? theme.accent.opacity(0.15) : .clear)
            )
            .foregroundStyle(selection == dest ? theme.accent : .primary)
        }
        .buttonStyle(.plain)
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
                .font(.subheadline)
                .foregroundStyle(tint)
                .frame(width: 22)
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

extension Double {
    var shortCurrency: String {
        let code = Locale.current.currency?.identifier ?? "USD"
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = code
        nf.maximumFractionDigits = 0
        return nf.string(from: NSNumber(value: self)) ?? "$\(Int(self))"
    }
}

