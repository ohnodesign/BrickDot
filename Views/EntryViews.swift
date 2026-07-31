import SwiftUI
import SwiftData

/// A built-in, fixed counterpart to a user-created `SavedSearch`: both are
/// just named filter combinations. The dashboard stats and the sidebar's
/// TODAY card are these, so tapping "9 Overdue" applies exactly the same
/// kind of filter as tapping a saved search — one behavior, one code path.
enum BuiltInView: String, CaseIterable, Identifiable {
    case overdue, dueToday, running

    var id: String { rawValue }

    var label: String {
        switch self {
        case .overdue:  return "Overdue"
        case .dueToday: return "Due Today"
        case .running:  return "Running"
        }
    }

    var icon: String {
        switch self {
        case .overdue:  return "exclamationmark.triangle.fill"
        case .dueToday: return "sun.max.fill"
        case .running:  return "timer"
        }
    }

    func tint(_ theme: AppTheme) -> Color {
        switch self {
        case .overdue:  return theme.overdue
        case .dueToday: return theme.dueToday
        case .running:  return theme.running
        }
    }

    /// The filter this view applies. Counts shown next to a built-in are
    /// derived from the same predicate, so the badge always matches the
    /// number of rows you get after tapping it.
    var filter: FilterType {
        switch self {
        case .overdue:  return .overdue
        case .dueToday: return .dueToday
        case .running:  return .running
        }
    }

    func count(in entries: [Entry]) -> Int {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let todayEnd = cal.date(byAdding: DateComponents(day: 1, second: -1), to: todayStart) ?? todayStart
        let open = entries.filter { $0.status != .done }
        switch self {
        case .overdue:
            return open.filter { ($0.dueDate.map { $0 < todayStart }) == true }.count
        case .dueToday:
            return open.filter { d in
                guard let due = d.dueDate else { return false }
                return due >= todayStart && due <= todayEnd
            }.count
        case .running:
            return open.filter { $0.timerStartedAt != nil }.count
        }
    }
}

/// One-shot request to point the entries list at a particular view.
///
/// The filter state lives as `@State` inside `EntryListView`, but the things
/// that want to change it — the Mac sidebar, the iPhone dashboard — sit
/// above it in the hierarchy. This carries the request down through the
/// environment instead of prop-drilling a binding through every view in
/// between. `EntryListView` applies it and clears it.
@Observable
final class EntryViewRequest {
    enum Target: Equatable {
        case builtIn(BuiltInView)
        case saved(PersistentIdentifier)
    }

    var pending: Target?

    func request(_ target: Target) {
        pending = target
    }
}

private struct EntryViewRequestKey: EnvironmentKey {
    static let defaultValue = EntryViewRequest()
}

extension EnvironmentValues {
    var entryViewRequest: EntryViewRequest {
        get { self[EntryViewRequestKey.self] }
        set { self[EntryViewRequestKey.self] = newValue }
    }
}

/// Posted when a stat should take the user to the Stats screen rather than
/// filter the list — "This Week" is a revenue figure, not a filter.
extension Notification.Name {
    static let showStats = Notification.Name("showStats")
}
