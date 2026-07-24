import Foundation
import SwiftData

/// A named, persisted combination of EntryListView's filter state, so a
/// common search (e.g. "Cobblestone Homes, Starred") can be applied again
/// with one tap instead of re-picking every option.
@Model
final class SavedSearch {
    var name: String = ""
    var categoryRaw: String = EntryCategory.all.rawValue
    var filterRaws: [String] = []
    var dateQuickPickRaw: String? = nil
    var customDateStart: Date? = nil
    var customDateEnd: Date? = nil
    var client: Client? = nil
    var sortRaw: String = SortOption.recent.rawValue
    var createdAt: Date = Date()

    init(name: String,
         category: EntryCategory,
         filters: Set<FilterType>,
         dateQuickPick: DateQuickPick?,
         customDateRange: ClosedRange<Date>?,
         client: Client?,
         sort: SortOption) {
        self.name = name
        self.categoryRaw = category.rawValue
        self.filterRaws = filters.map(\.rawValue)
        self.dateQuickPickRaw = dateQuickPick?.rawValue
        self.customDateStart = customDateRange?.lowerBound
        self.customDateEnd = customDateRange?.upperBound
        self.client = client
        self.sortRaw = sort.rawValue
        self.createdAt = Date()
    }

    var category: EntryCategory { EntryCategory(rawValue: categoryRaw) ?? .all }
    var filters: Set<FilterType> { Set(filterRaws.compactMap(FilterType.init(rawValue:))) }
    var dateQuickPick: DateQuickPick? { dateQuickPickRaw.flatMap(DateQuickPick.init(rawValue:)) }
    var sort: SortOption { SortOption(rawValue: sortRaw) ?? .recent }
    var customDateRange: ClosedRange<Date>? {
        guard let start = customDateStart, let end = customDateEnd else { return nil }
        return start...end
    }

    /// A short "Client, Category, Filters" label matching the title shown
    /// above the entries list, used as the chip/row label everywhere this
    /// saved search is listed.
    var summaryLabel: String {
        var parts: [String] = []
        if let client { parts.append(client.name) }
        parts.append(category.label)
        parts.append(contentsOf: FilterType.allCases.filter(filters.contains).map(\.label))
        return parts.joined(separator: ", ")
    }

    /// Applies this saved search's filters to `allEntries`, mirroring the
    /// predicate EntryListView builds from its own live @State — used by
    /// the iPad/Mac sidebar to show a saved search's results without going
    /// through EntryListView's interactive filter UI.
    func matchingEntries(in allEntries: [Entry]) -> [Entry] {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())

        func isOverdue(_ entry: Entry) -> Bool {
            guard entry.status != .done, let due = entry.dueDate else { return false }
            return due < todayStart
        }
        func matchesFilter(_ entry: Entry, _ filter: FilterType) -> Bool {
            switch filter {
            case .starred:    return entry.isImportant
            case .inProgress: return entry.status == .inProgress
            case .overdue:    return isOverdue(entry)
            case .todo:       return entry.status == .todo
            }
        }
        func relevantDate(_ entry: Entry) -> Date {
            category == .done ? (entry.completedAt ?? entry.serviceDate) : entry.serviceDate
        }

        let categoryEntries: [Entry]
        switch category {
        case .all:           categoryEntries = allEntries.filter { $0.status != .done }
        case .quickCaptures: categoryEntries = allEntries.filter { $0.isQuickAdd }
        case .done:          categoryEntries = allEntries.filter { $0.status == .done }
        }

        let range: ClosedRange<Date>?
        if let custom = customDateRange {
            range = custom
        } else if let pick = dateQuickPick {
            switch pick {
            case .today:
                let end = cal.date(byAdding: DateComponents(day: 1, second: -1), to: todayStart) ?? todayStart
                range = todayStart...end
            case .thisWeek:
                let now = Date()
                range = now.bdStartOfWeek...now.bdEndOfWeek
            case .thisMonth:
                let now = Date()
                range = now.bdStartOfMonth...now.bdEndOfMonth
            }
        } else {
            range = nil
        }

        return categoryEntries.filter { entry in
            (filters.isEmpty || filters.allSatisfy { matchesFilter(entry, $0) })
                && (range == nil || range!.contains(relevantDate(entry)))
                && (client == nil || entry.client?.persistentModelID == client?.persistentModelID)
        }
    }
}
