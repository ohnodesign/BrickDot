// Views/EntryListView.swift
import SwiftUI
import SwiftData

// MARK: - Filter & Sort Types

/// Single-select base category. Replaces the old "always exclude Quick
/// Captures, always append a collapsed Done section" behavior - Quick
/// Captures and Done are now just two more views onto the same list.
enum EntryCategory: String, CaseIterable, Hashable {
    case all, quickCaptures, done

    var label: String {
        switch self {
        case .all:           return "All"
        case .quickCaptures: return "Quick Captures"
        case .done:          return "Done"
        }
    }
}

enum FilterType: String, CaseIterable, Hashable {
    case starred, inProgress, overdue, todo

    var label: String {
        switch self {
        case .starred:    return "Starred"
        case .inProgress: return "In Progress"
        case .overdue:    return "Overdue"
        case .todo:       return EntryStatus.todo.displayLabel
        }
    }
}

enum SortOption: String, CaseIterable {
    case recent   = "Recent"
    case dueDate  = "Due Date"
    case client   = "Client"
}

enum DateQuickPick: String, CaseIterable, Hashable {
    case today, thisWeek, thisMonth

    var label: String {
        switch self {
        case .today:     return "Today"
        case .thisWeek:  return "This Week"
        case .thisMonth: return "This Month"
        }
    }
}

// MARK: - Flow Layout (wrapping chip grid)

/// Lays out subviews left-to-right, wrapping to a new line when a subview
/// would overflow the available width — used for the filter sheet's chip
/// grids (Status, Date) so they wrap instead of scrolling horizontally.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var width: CGFloat = 0
        var height: CGFloat = 0
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if lineWidth + size.width > maxWidth, lineWidth > 0 {
                width = max(width, lineWidth)
                height += lineHeight + spacing
                lineWidth = 0
                lineHeight = 0
            }
            lineWidth += size.width + (lineWidth > 0 ? spacing : 0)
            lineHeight = max(lineHeight, size.height)
        }
        width = max(width, lineWidth)
        height += lineHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - EntryListView (shared between Home screen & Client detail)

/// Unified filter/sort entry list, used on both the home screen and client
/// detail pages. Callers pass in the set of entries to display. A
/// single-select category (All / Quick Captures / Done) picks the base set;
/// status pills, date range, and client all further narrow within it.
struct EntryListView: View {
    let entries: [Entry]
    var isClientScoped: Bool = false

    @Environment(\.modelContext) private var ctx
    @Environment(\.appTheme) private var theme
    @Query(sort: \Client.name) private var allClients: [Client]
    @Query(sort: \SavedSearch.createdAt) private var savedSearches: [SavedSearch]

    @State private var activeCategory: EntryCategory = .all
    // Empty = no constraint (show everything). Each active pill ANDs in an
    // additional requirement — e.g. Starred + Overdue narrows to entries
    // that are both, not the union of the two.
    @State private var activeFilters: Set<FilterType> = []
    @State private var activeSort: SortOption = .recent
    @State private var dateQuickPick: DateQuickPick? = nil
    @State private var customDateRange: ClosedRange<Date>? = nil
    @State private var showCustomRangePicker = false
    @State private var selectedClientFilter: Client? = nil
    @State private var showAllEntries = false
    @State private var showFilterSheet = false
    @State private var showSaveSearchAlert = false
    @State private var newSearchName = ""

    private var cal: Calendar { Calendar.current }
    private var todayStart: Date { cal.startOfDay(for: Date()) }

    /// `selectedClientFilter` holds a strong reference, so a client deleted
    /// on the Clients tab — or synced away by CloudKit from another device —
    /// leaves a dangling model behind. Reading any property off it traps, so
    /// every read goes through here and a deleted client reads as "no filter".
    private var liveClientFilter: Client? {
        guard let c = selectedClientFilter, !c.isDeleted, c.modelContext != nil else { return nil }
        return c
    }

    private var sortOptions: [SortOption] {
        isClientScoped ? [.recent, .dueDate] : SortOption.allCases
    }

    // Base set for the active category. All/Quick Captures/Done are now
    // just three views onto the same list, not separate always-shown
    // sections.
    private var categoryEntries: [Entry] {
        entries(in: activeCategory)
    }

    private func entries(in category: EntryCategory) -> [Entry] {
        switch category {
        case .all:           return entries.filter { $0.status != .done }
        case .quickCaptures: return entries.filter { $0.isQuickAdd }
        case .done:          return entries.filter { $0.status == .done }
        }
    }

    private func isOverdue(_ entry: Entry) -> Bool {
        guard entry.status != .done, let due = entry.dueDate else { return false }
        return due < todayStart
    }

    private func matches(_ entry: Entry, _ filter: FilterType) -> Bool {
        switch filter {
        case .starred:    return entry.isImportant
        case .inProgress: return entry.status == .inProgress
        case .overdue:    return isOverdue(entry)
        case .todo:       return entry.status == .todo
        }
    }

    /// The date used for sorting/range-filtering an entry: completion date
    /// for Done, service date otherwise.
    private func relevantDate(_ entry: Entry) -> Date {
        activeCategory == .done ? (entry.completedAt ?? entry.serviceDate) : entry.serviceDate
    }

    private var effectiveDateRange: ClosedRange<Date>? {
        if let custom = customDateRange { return custom }
        guard let pick = dateQuickPick else { return nil }
        switch pick {
        case .today:
            let end = cal.date(byAdding: DateComponents(day: 1, second: -1), to: todayStart) ?? todayStart
            return todayStart...end
        case .thisWeek:
            let now = Date()
            return now.bdStartOfWeek...now.bdEndOfWeek
        case .thisMonth:
            let now = Date()
            return now.bdStartOfMonth...now.bdEndOfMonth
        }
    }

    private func matchesDate(_ entry: Entry) -> Bool {
        guard let range = effectiveDateRange else { return true }
        return range.contains(relevantDate(entry))
    }

    private func matchesClient(_ entry: Entry) -> Bool {
        guard let client = liveClientFilter else { return true }
        return entry.client?.persistentModelID == client.persistentModelID
    }

    private var filteredEntries: [Entry] {
        categoryEntries.filter { entry in
            (activeFilters.isEmpty || activeFilters.allSatisfy { matches(entry, $0) })
                && matchesDate(entry)
                && matchesClient(entry)
        }
    }

    private var sortedFlatEntries: [Entry] {
        switch activeSort {
        case .recent:
            return filteredEntries.sorted { relevantDate($0) > relevantDate($1) }
        case .dueDate:
            return filteredEntries.sorted { a, b in
                switch (a.dueDate, b.dueDate) {
                case let (ad?, bd?): return ad < bd
                case (_?, nil): return true
                case (nil, _?): return false
                default: return relevantDate(a) > relevantDate(b)
                }
            }
        case .client:
            return filteredEntries.sorted { relevantDate($0) > relevantDate($1) }
        }
    }

    private var groupedByClient: [(client: String, entries: [Entry])] {
        let grouped = Dictionary(grouping: filteredEntries) { $0.displayClientName }
        return grouped.keys.sorted().map { key in
            (client: key, entries: grouped[key]!.sorted { relevantDate($0) > relevantDate($1) })
        }
    }

    // Number of independent filter dimensions currently narrowing the list —
    // drives the badge on the Filter button.
    private var activeFilterCount: Int {
        activeFilters.count
            + (effectiveDateRange != nil ? 1 : 0)
            + (liveClientFilter != nil ? 1 : 0)
    }

    private var customRangeLabel: String {
        guard let range = customDateRange else { return "Custom…" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return "\(f.string(from: range.lowerBound))–\(f.string(from: range.upperBound))"
    }

    /// "Cobblestone Homes, All, Starred" — a legible readout of every active
    /// filter dimension, shown as a title above the list so it's always
    /// obvious what's currently narrowing it down.
    private var activeFilterTitle: String {
        var parts: [String] = []
        if let client = liveClientFilter { parts.append(client.name) }
        parts.append(activeCategory.label)
        parts.append(contentsOf: FilterType.allCases.filter(activeFilters.contains).map(\.label))
        if customDateRange != nil {
            parts.append(customRangeLabel)
        } else if let pick = dateQuickPick {
            parts.append(pick.label)
        }
        return parts.joined(separator: ", ")
    }

    private var entryCountText: String {
        let count = sortedFlatEntries.count
        return "\(count) \(count == 1 ? "entry" : "entries")"
    }

    private func apply(_ search: SavedSearch) {
        activeCategory = search.category
        activeFilters = search.filters
        dateQuickPick = search.dateQuickPick
        customDateRange = search.customDateRange
        selectedClientFilter = search.client
        activeSort = search.sort
    }

    private func saveCurrentSearch() {
        let name = newSearchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let search = SavedSearch(
            name: name,
            category: activeCategory,
            filters: activeFilters,
            dateQuickPick: dateQuickPick,
            customDateRange: customDateRange,
            client: liveClientFilter,
            sort: activeSort
        )
        ctx.insert(search)
        try? ctx.save()
        newSearchName = ""
    }

    private func deleteSavedSearch(_ search: SavedSearch) {
        ctx.delete(search)
        try? ctx.save()
    }

    // Default to the first 20, with a "More" button to reveal the rest.
    private var displayedFlatEntries: [Entry] {
        showAllEntries ? sortedFlatEntries : Array(sortedFlatEntries.prefix(20))
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                categorySegmented
                if !isClientScoped {
                    savedSearchRow
                }
                Text(activeFilterTitle)
                    .font(macSized(Font.subheadline, .title3).weight(.semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                toolbarRow
            }
            .padding(.vertical, 4)
            .listRowSeparator(.hidden)
            .onChange(of: activeCategory) { _, _ in showAllEntries = false }
            .onChange(of: activeFilters) { _, _ in showAllEntries = false }
            .onChange(of: dateQuickPick) { _, _ in showAllEntries = false }
            .onChange(of: customDateRange) { _, _ in showAllEntries = false }
            .onChange(of: selectedClientFilter) { _, _ in showAllEntries = false }
            .sheet(isPresented: $showFilterSheet) { filterSheet }
            .alert("Save Search", isPresented: $showSaveSearchAlert) {
                TextField("Name", text: $newSearchName)
                Button("Save") { saveCurrentSearch() }
                Button("Cancel", role: .cancel) { newSearchName = "" }
            } message: {
                Text("Save the current filters so you can apply them again with one tap.")
            }
        } header: {
            Text("ENTRIES")
                .font(.caption.weight(.bold))
                .foregroundStyle(theme.secondaryText)
                .tracking(0.5)
        }

        if !isClientScoped && activeSort == .client {
            ForEach(groupedByClient, id: \.client) { group in
                Section(group.client) {
                    ForEach(group.entries, id: \.persistentModelID) { entry in
                        row(for: entry)
                    }
                }
            }
        } else {
            Section {
                if sortedFlatEntries.isEmpty {
                    Text("Nothing matches the current filters.")
                        .foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(displayedFlatEntries, id: \.persistentModelID) { entry in
                        row(for: entry)
                    }
                    if sortedFlatEntries.count > 20 {
                        Button {
                            withAnimation { showAllEntries.toggle() }
                        } label: {
                            HStack {
                                Spacer()
                                Text(showAllEntries ? "Show Less" : "More (\(sortedFlatEntries.count - 20))")
                                    .font(.footnote)
                                    .foregroundStyle(theme.secondaryText)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowSeparator(.hidden)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(for entry: Entry) -> some View {
        if activeCategory == .done {
            doneRow(entry)
        } else {
            entryRow(entry)
        }
    }

    // MARK: - Controls

    /// Single-select category, always fully visible — this is the one
    /// decision that changes what universe of entries you're looking at,
    /// so it gets a segmented control instead of being one pill among many.
    private var categorySegmented: some View {
        HStack(spacing: 2) {
            ForEach(EntryCategory.allCases, id: \.self) { category in
                let isActive = activeCategory == category
                Button {
                    activeCategory = category
                } label: {
                    HStack(spacing: 4) {
                        Text(category.label)
                        Text("\(entries(in: category).count)")
                            .foregroundStyle(isActive ? theme.accent : theme.mutedText)
                    }
                    .font(macSized(Font.caption, .subheadline).weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, macSized(7, 10))
                    .background(isActive ? theme.cardBackground : Color.clear)
                    .foregroundStyle(isActive ? theme.primaryText : theme.secondaryText)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: isActive ? .black.opacity(0.08) : .clear, radius: 2, y: 1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(theme.sidebarBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// One-tap saved-search chips, plus a trailing chip to save the current
    /// filter combination under a name. Hidden on client-scoped lists,
    /// where the client dimension is already fixed by the caller.
    private var savedSearchRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(savedSearches, id: \.persistentModelID) { search in
                    Button {
                        apply(search)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "bookmark.fill")
                            Text(search.name)
                        }
                        .font(macSized(Font.caption, .subheadline).weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, macSized(10, 13))
                        .padding(.vertical, macSized(6, 9))
                        .background(theme.sidebarBackground)
                        .foregroundStyle(theme.secondaryText)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            deleteSavedSearch(search)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }

                Button {
                    showSaveSearchAlert = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                        Text("Save Search")
                    }
                    .font(macSized(Font.caption, .subheadline).weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, macSized(10, 13))
                    .padding(.vertical, macSized(6, 9))
                    .background(theme.accentLight)
                    .foregroundStyle(theme.accent)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The entry count, plus the two entry points for everything else: a
    /// Filter button (badged with how many dimensions are active) opening
    /// one sheet, and a Sort menu.
    private var toolbarRow: some View {
        HStack(spacing: 8) {
            Text(entryCountText)
                .font(macSized(Font.caption, .subheadline))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
                .layoutPriority(-1)

            Spacer(minLength: 8)

            Button {
                showFilterSheet = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "line.3.horizontal.decrease")
                    Text("Filter")
                    if activeFilterCount > 0 {
                        Text("\(activeFilterCount)")
                            .font(macSized(Font.caption2, .caption).weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Circle().fill(theme.accent))
                    }
                }
                .font(macSized(Font.caption, .subheadline).weight(.semibold))
                .padding(.horizontal, macSized(9, 12))
                .padding(.vertical, macSized(6, 9))
                .background(activeFilterCount > 0 ? theme.accentLight : theme.sidebarBackground)
                .foregroundStyle(activeFilterCount > 0 ? theme.accent : theme.secondaryText)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            Menu {
                ForEach(sortOptions, id: \.self) { option in
                    Button {
                        activeSort = option
                    } label: {
                        if activeSort == option {
                            Label(option.rawValue, systemImage: "checkmark")
                        } else {
                            Text(option.rawValue)
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text(activeSort.rawValue)
                }
                .font(macSized(Font.caption, .subheadline).weight(.semibold))
                .padding(.horizontal, macSized(9, 12))
                .padding(.vertical, macSized(6, 9))
                .background(theme.sidebarBackground)
                .foregroundStyle(theme.secondaryText)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Filter Sheet

    private var filterSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if activeCategory != .done {
                        filterGroup("Status") {
                            FlowLayout(spacing: 8) {
                                ForEach(FilterType.allCases, id: \.self) { filter in
                                    chip(filter.label, isOn: activeFilters.contains(filter)) {
                                        if activeFilters.contains(filter) {
                                            activeFilters.remove(filter)
                                        } else {
                                            activeFilters.insert(filter)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    filterGroup("Date") {
                        FlowLayout(spacing: 8) {
                            ForEach(DateQuickPick.allCases, id: \.self) { pick in
                                let isActive = dateQuickPick == pick && customDateRange == nil
                                chip(pick.label, isOn: isActive) {
                                    if isActive {
                                        dateQuickPick = nil
                                    } else {
                                        dateQuickPick = pick
                                        customDateRange = nil
                                    }
                                }
                            }
                            chip(customRangeLabel, isOn: customDateRange != nil) {
                                showCustomRangePicker = true
                            }
                        }
                    }

                    if !isClientScoped {
                        filterGroup("Client") {
                            VStack(spacing: 0) {
                                clientRow("All Clients", isOn: liveClientFilter == nil) {
                                    selectedClientFilter = nil
                                }
                                ForEach(allClients, id: \.persistentModelID) { c in
                                    clientRow(c.name, isOn: liveClientFilter?.persistentModelID == c.persistentModelID) {
                                        selectedClientFilter = c
                                    }
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.divider, lineWidth: 1))
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear All") {
                        activeFilters.removeAll()
                        dateQuickPick = nil
                        customDateRange = nil
                        selectedClientFilter = nil
                    }
                    .disabled(activeFilterCount == 0)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showFilterSheet = false }
                }
            }
        }
        .sheet(isPresented: $showCustomRangePicker) {
            DateRangePickerSheet(range: $customDateRange, onApply: { dateQuickPick = nil })
        }
    }

    @ViewBuilder
    private func filterGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(theme.mutedText)
                .tracking(0.5)
            content()
        }
    }

    private func chip(_ label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(macSized(Font.caption, .subheadline).weight(.semibold))
                .padding(.horizontal, macSized(12, 15))
                .padding(.vertical, macSized(7, 10))
                .background(Capsule().fill(isOn ? theme.accent : Color.clear))
                .overlay(Capsule().strokeBorder(isOn ? Color.clear : theme.divider, lineWidth: 1))
                .foregroundStyle(isOn ? .white : theme.secondaryText)
        }
        .buttonStyle(.plain)
    }

    private func clientRow(_ name: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(name)
                    .foregroundStyle(isOn ? theme.accent : theme.primaryText)
                    .fontWeight(isOn ? .semibold : .regular)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark")
                        .foregroundStyle(theme.accent)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(theme.cardBackground)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func entryRow(_ entry: Entry) -> some View {
        Group {
            if let raw = entry.setupAction, let action = SetupAction(rawValue: raw) {
                // Starter todo: tapping jumps to the app section it asks for.
                Button {
                    action.navigate()
                } label: {
                    HStack {
                        EntryListRow(entry: entry, isOverdue: isOverdue(entry))
                        Image(systemName: "arrow.right.circle")
                            .foregroundStyle(theme.accent)
                            .imageScale(.large)
                    }
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink { EditEntryView(entry: entry) } label: {
                    EntryListRow(entry: entry, isOverdue: isOverdue(entry))
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) { trailingSwipe(entry) }
        .swipeActions(edge: .leading, allowsFullSwipe: false) { leadingSwipe(entry) }
    }

    @ViewBuilder
    private func doneRow(_ entry: Entry) -> some View {
        NavigationLink { EditEntryView(entry: entry) } label: {
            EntryListRow(entry: entry, isOverdue: false)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) { leadingSwipe(entry) }
    }

    // MARK: - Swipe Actions (mirrors HomeView / ClientDetailView)

    @ViewBuilder
    private func trailingSwipe(_ entry: Entry) -> some View {
        if entry.status == .inProgress && entry.timerStartedAt != nil {
            Button { quickPauseAndAdd(entry) } label: {
                Label("Pause & Add", systemImage: "pause.circle")
            }.tint(theme.dueToday)
        } else if entry.status != .done {
            Button { quickStart(entry) } label: {
                Label("Start", systemImage: "play.circle")
            }.tint(theme.success)
        }
        Button { quickBump(entry, 0.25) } label: { Text("+15m") }.tint(theme.accent)
        Button { quickBump(entry, 0.5) }  label: { Text("+30m") }.tint(theme.accentHover)
    }

    @ViewBuilder
    private func leadingSwipe(_ entry: Entry) -> some View {
        Button {
            entry.isImportant.toggle()
            entry.markModified()
            try? ctx.save()
        } label: {
            Label(entry.isImportant ? "Unstar" : "Star",
                  systemImage: entry.isImportant ? "star.slash.fill" : "star.fill")
        }.tint(.yellow)

        if entry.status != .todo {
            Button {
                entry.status = .todo
                entry.timerStartedAt = nil
                entry.markModified()
                try? ctx.save()
            } label: {
                Label(EntryStatus.todo.displayLabel, systemImage: "circle")
            }.tint(theme.dueToday)
        }
        if entry.status != .inProgress {
            Button {
                entry.status = .inProgress
                if entry.timerStartedAt == nil { entry.timerStartedAt = Date() }
                entry.markModified()
                try? ctx.save()
            } label: {
                Label("In Progress", systemImage: "bolt.fill")
            }.tint(theme.running)
        }
        if entry.status != .done {
            Button { markDone(entry) } label: {
                Label("Done", systemImage: "checkmark.circle.fill")
            }.tint(theme.success)
        }
    }

    private func quickStart(_ e: Entry) {
        e.status = .inProgress
        if e.timerStartedAt == nil { e.timerStartedAt = Date() }
        e.markModified()
        try? ctx.save()
    }
    private func quickPauseAndAdd(_ e: Entry) {
        guard e.timerStartedAt != nil else { return }
        let elapsed = e.runningElapsedHoursOrZero
        e.hours += elapsed
        e.timeLogsList.append(TimeLog(hours: elapsed, entry: e))
        e.timerStartedAt = nil
        e.markModified()
        try? ctx.save()
        NotificationManager.shared.cancelNoTimeLoggedReminder()
    }
    private func quickBump(_ e: Entry, _ h: Double) {
        e.hours += h
        e.timeLogsList.append(TimeLog(hours: h, entry: e))
        e.markModified()
        try? ctx.save()
        NotificationManager.shared.cancelNoTimeLoggedReminder()
    }
    private func markDone(_ e: Entry) {
        e.timerStartedAt = nil
        e.status = .done
        e.completedAt = Date()
        e.markModified()
        try? ctx.save()
    }
}

// MARK: - Custom Date Range Picker

private struct DateRangePickerSheet: View {
    @Binding var range: ClosedRange<Date>?
    var onApply: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date

    init(range: Binding<ClosedRange<Date>?>, onApply: @escaping () -> Void = {}) {
        self._range = range
        self.onApply = onApply
        let now = Date()
        self._start = State(initialValue: range.wrappedValue?.lowerBound ?? now)
        self._end = State(initialValue: range.wrappedValue?.upperBound ?? now)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("From", selection: $start, displayedComponents: .date)
                DatePicker("To", selection: $end, displayedComponents: .date)
            }
            .navigationTitle("Date Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Clear") {
                        range = nil
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        let cal = Calendar.current
                        let s = cal.startOfDay(for: start)
                        let e = cal.date(byAdding: DateComponents(day: 1, second: -1), to: cal.startOfDay(for: end)) ?? end
                        range = min(s, e)...max(s, e)
                        onApply()
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Rows

/// One row format for every state an entry can be in — a status pill
/// (Overdue / Quick Capture / Done / In Progress / On Deck) replaces the
/// old three separate row types (plain / done / quick-capture) that each
/// used a different colored dot or bullet.
private struct EntryListRow: View {
    let entry: Entry
    let isOverdue: Bool
    @Environment(\.appTheme) private var theme

    /// Amber, matching the app's established "unreviewed capture" color
    /// (the same hue used elsewhere for Quick Capture, independent of theme).
    private static let captureColor = Color(red: 0.71, green: 0.325, blue: 0.035)

    private var headlineText: String {
        entry.detail.isEmpty ? entry.service : entry.detail
    }

    private var pillLabel: String {
        if isOverdue { return "Overdue" }
        if entry.isQuickAdd { return "Quick Capture" }
        switch entry.status {
        case .done:       return "Done"
        case .inProgress: return "In Progress"
        case .todo:       return "On Deck"
        }
    }

    private var pillForeground: Color {
        if isOverdue { return theme.overdue }
        if entry.isQuickAdd { return Self.captureColor }
        switch entry.status {
        case .done:       return theme.success
        case .inProgress: return theme.running
        case .todo:       return theme.secondaryText
        }
    }

    private var pillBackground: Color {
        if isOverdue { return theme.overdueLight }
        if entry.isQuickAdd { return Self.captureColor.opacity(0.15) }
        switch entry.status {
        case .done:       return theme.successLight
        case .inProgress: return theme.runningLight
        case .todo:       return theme.sidebarBackground
        }
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    private var dateLine: String {
        let created = "Created \(shortDate(entry.createdAt))"
        if entry.status == .done, let completed = entry.completedAt {
            return "\(created) · Completed \(shortDate(completed))"
        } else if let due = entry.dueDate {
            return "\(created) · Due \(shortDate(due))"
        }
        return created
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                if entry.isImportant {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(theme.overdue)
                }
                if entry.service == "COMM", let icon = commChannelIcon(for: entry.commChannel) {
                    Image(systemName: icon)
                        .font(.caption2)
                        .foregroundStyle(theme.accent)
                }
                Text(headlineText)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                if !entry.detail.isEmpty {
                    Text(entry.service.uppercased())
                        .font(macSized(Font.caption2, .caption).weight(.bold))
                        .foregroundStyle(theme.accent)
                    Text("·").foregroundStyle(.secondary)
                }
                Text(entry.displayClientName)
                    .font(macSized(Font.caption, .subheadline))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 6)

                Text(pillLabel)
                    .font(macSized(Font.caption2, .caption).weight(.bold))
                    .lineLimit(1)
                    .padding(.horizontal, macSized(7, 9))
                    .padding(.vertical, macSized(2, 3))
                    .background(pillBackground)
                    .foregroundStyle(pillForeground)
                    .clipShape(Capsule())
            }

            HStack {
                Text(dateLine)
                    .font(macSized(Font.caption2, .caption))
                    .foregroundStyle(theme.mutedText)
                Spacer()
                if entry.hours > 0 {
                    Text("\(entry.hours, specifier: "%.1f")h")
                        .font(macSized(Font.caption, .subheadline).weight(.semibold))
                        .foregroundStyle(theme.secondaryText)
                }
            }
        }
        .padding(.vertical, macSized(3, 5))
    }
}
