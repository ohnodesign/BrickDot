import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.appTheme) private var theme
    @Query(sort: \Entry.serviceDate, order: .reverse) private var allEntries: [Entry]
    @Query private var allClients: [Client]

    @State private var showNewEntry = false
    @State private var searchText = ""
    @State private var showSearch = false
    @Query private var profiles: [UserProfile]
    private var profile: UserProfile? { profiles.first }

    // MARK: - Onboarding
    @AppStorage(OnboardingPrefs.dismissed) private var onboardingDismissed = false
    @AppStorage(OnboardingPrefs.started) private var onboardingStarted = false

    private var onboardingStepsComplete: Bool {
        let realEntries = allEntries.filter { $0.setupAction == nil }
        return !allClients.isEmpty && !realEntries.isEmpty &&
        realEntries.contains { $0.timerStartedAt != nil || $0.hours > 0 || !$0.timeLogsList.isEmpty }
    }
    private var showGettingStarted: Bool {
        !onboardingDismissed && (onboardingStarted || !onboardingStepsComplete)
    }

    var body: some View {
            List {
                // MARK: - Search bar (iPhone)
                if showSearch && sizeClass == .compact {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search entries…", text: $searchText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }

                // MARK: - Greeting
                if searchText.isEmpty {
                    Section {
                        GreetingText(name: profile?.displayName ?? "")
                            .listRowSeparator(.hidden)
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))

                    // MARK: - Getting Started (first launch)
                    if showGettingStarted {
                        Section {
                            GettingStartedCard()
                                .listRowSeparator(.hidden)
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }

                }

                // MARK: - Dashboard (iPhone only — iPad shows this in the sidebar)
                if sizeClass == .compact {
                    Section {
                        DashboardRow(
                            overdueCount: overdueEntries.count,
                            dueTodayCount: allDueTodayCount,
                            timersRunning: timersRunningCount,
                            weekAmount: thisWeekAmount
                        )
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }

                // MARK: - Filtered List (category, filter pills, sort bar, date/client, unified list)
                if mainListEntries.isEmpty && allEntries.isEmpty && showGettingStarted {
                    // Brand-new user: the Getting Started card is the empty state.
                    EmptyView()
                } else if mainListEntries.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.largeTitle)
                                .foregroundStyle(theme.success)
                            Text("All caught up!")
                                .font(.headline)
                            Text("No open entries right now.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                } else {
                    EntryListView(entries: mainListEntries, isClientScoped: false)
                }
            }
            .listStyle(.plain)
            .listRowSpacing(6)
            .listSectionSeparator(.hidden)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                StarterTodos.seedIfNeeded(ctx)
                StarterTodos.autoComplete(ctx)
                guard !onboardingDismissed else { return }
                if onboardingStepsComplete && !onboardingStarted {
                    // Existing user (e.g. data arrived via CloudKit sync) —
                    // never show setup they don't need.
                    onboardingDismissed = true
                } else {
                    onboardingStarted = true
                }
            }
            .onChange(of: allEntries.count) { _, _ in
                StarterTodos.autoComplete(ctx)
            }
            .onChange(of: allClients.count) { _, _ in
                StarterTodos.autoComplete(ctx)
            }
            .sheet(isPresented: $showNewEntry) {
                QuickAddView(onSaved: { showNewEntry = false })
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            .toolbar {
                if sizeClass == .compact {
                    ToolbarItem(placement: .topBarLeading) {
                        Image(systemName: "house")
                            .imageScale(.large)
                            .foregroundStyle(Color(.darkGray))
                            .accessibilityLabel("Home")
                    }
                    ToolbarItem(placement: .principal) {
                        Text(profile.flatMap { $0.companyName.isEmpty ? nil : $0.companyName } ?? "BrickDot")
                            .font(.headline)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 16) {
                            Button {
                                withAnimation {
                                    showSearch.toggle()
                                    if !showSearch { searchText = "" }
                                }
                            } label: {
                                Image(systemName: showSearch ? "xmark" : "magnifyingglass")
                                    .imageScale(.large)
                                    .foregroundStyle(Color(.darkGray))
                                    .accessibilityLabel("Search")
                            }
                            Button { showNewEntry = true } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color(red: 0.79, green: 0.25, blue: 0.25))
                                        .frame(width: 28, height: 28)
                                    Image(systemName: "plus")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                                .accessibilityLabel("New Entry")
                            }
                        }
                    }
                }
            }
    }

    // MARK: - Entry Sorting & Filtering

    private var cal: Calendar { Calendar.current }
    private var todayStart: Date { cal.startOfDay(for: Date()) }
    private var todayEnd: Date { cal.date(byAdding: DateComponents(day: 1, second: -1), to: todayStart) ?? Date() }

    private func matchesSearch(_ entry: Entry) -> Bool {
        guard !searchText.isEmpty else { return true }
        let q = searchText.lowercased()
        return entry.clientName.lowercased().contains(q)
            || entry.service.lowercased().contains(q)
            || entry.detail.lowercased().contains(q)
            || entry.notes.lowercased().contains(q)
    }

    private var openEntries: [Entry] {
        allEntries.filter { $0.status != .done && matchesSearch($0) }
    }

    private var overdueEntries: [Entry] {
        openEntries.filter { e in
            guard let due = e.dueDate else { return false }
            return due < todayStart
        }.sorted(by: prioritySort)
    }

    private var allDueTodayCount: Int {
        openEntries.filter { e in
            guard let due = e.dueDate else { return false }
            return due >= todayStart && due <= todayEnd
        }.count
    }

    // Everything shown below: category + filter pills + sort bar + date/client
    // + unified list, via the shared EntryListView.
    private var mainListEntries: [Entry] {
        allEntries.filter { matchesSearch($0) }
    }

    private var timersRunningCount: Int {
        allEntries.filter { $0.status == .inProgress && $0.timerStartedAt != nil }.count
    }

    private var thisWeekAmount: Double {
        let start = Date().bdStartOfWeek
        let end = Date().bdEndOfWeek
        return allEntries
            .filter { $0.status == .done && ($0.completedAt ?? $0.serviceDate) >= start && ($0.completedAt ?? $0.serviceDate) <= end }
            .reduce(0) { $0 + ($1.hours * $1.rate) }
    }

    private func prioritySort(_ a: Entry, _ b: Entry) -> Bool {
        // Starred first
        if a.isImportant != b.isImportant { return a.isImportant }
        // Then by due date (soonest first), nil last
        switch (a.dueDate, b.dueDate) {
        case let (ad?, bd?): return ad < bd
        case (_?, nil): return true
        case (nil, _?): return false
        default: return a.serviceDate > b.serviceDate
        }
    }

}

// MARK: - Dashboard Row

private struct DashboardRow: View {
    let overdueCount: Int
    let dueTodayCount: Int
    let timersRunning: Int
    let weekAmount: Double
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            DashboardPill(
                icon: "exclamationmark.triangle.fill",
                tint: theme.overdue,
                value: "\(overdueCount)",
                label: "Overdue"
            )
            Divider().frame(height: 36)
            DashboardPill(
                icon: "sun.max.fill",
                tint: theme.dueToday,
                value: "\(dueTodayCount)",
                label: "Today"
            )
            Divider().frame(height: 36)
            DashboardPill(
                icon: "timer",
                tint: theme.running,
                value: "\(timersRunning)",
                label: "Running"
            )
            Divider().frame(height: 36)
            DashboardPill(
                icon: "dollarsign.circle.fill",
                tint: theme.revenue,
                value: weekAmount.shortCurrency,
                label: "This Week"
            )
        }
    }
}

private struct DashboardPill: View {
    let icon: String
    let tint: Color
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(tint)
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Greeting

private struct GreetingText: View {
    let name: String
    @Environment(\.appTheme) private var theme
    @AppStorage(AppPrefsKey.showDailyPhrase) private var showDailyPhrase = true

    private var firstName: String {
        name.split(separator: " ").first.map(String.init) ?? name
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12:  return "Good Morning"
        case 12..<17: return "Good Afternoon"
        default:      return "Good Evening"
        }
    }

    private static let dailyPhrases: [String] = [
        "Let's make today productive.",
        "Small steps, big results.",
        "Your best work starts now.",
        "\"The secret of getting ahead is getting started.\"",
        "One task at a time.",
        "Build something you're proud of.",
        "Progress over perfection.",
        "\"Do what you can, with what you have, where you are.\"",
        "Today's effort is tomorrow's momentum.",
        "Stay focused, stay sharp.",
        "Great things take time — keep going.",
        "\"Simplicity is the ultimate sophistication.\"",
        "Clear the decks, own the day.",
        "Your clients are counting on you.",
        "\"Well begun is half done.\"",
        "Make it happen.",
        "The work you do today matters.",
        "\"Quality is not an act, it is a habit.\"",
        "Less talk, more build.",
        "You've got this."
    ]

    private var dailyPhrase: String {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return Self.dailyPhrases[day % Self.dailyPhrases.count]
    }

    private var greetingSize: CGFloat {
        #if targetEnvironment(macCatalyst)
        return 26
        #else
        return 34
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(greeting)\(firstName.isEmpty ? "" : " \(firstName)")")
                .font(.system(size: greetingSize, weight: .bold, design: .serif))
            if showDailyPhrase {
                Text(dailyPhrase)
                    .font(.subheadline)
                    .foregroundStyle(theme.mutedText)
                    .padding(.bottom, 8)
            }
        }
    }
}


