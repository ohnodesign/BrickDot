# CLAUDE.md - BrickDot

## Project Overview

BrickDot is a native iOS/iPadOS/Mac Catalyst app (Ohno Design) for logging
billable client work, tracking time, and exporting QuickBooks-ready CSVs.
It also includes an AI "Coach" tab and voice/quick-capture entry flows.

**Target Platform:** iOS 17.0+ (SwiftData), also runs on iPad and Mac via
Mac Catalyst (`#if targetEnvironment(macCatalyst)`).
**Primary User:** Ohno Design (freelance/agency invoicing).

## Tech Stack

- **Language:** Swift, SwiftUI (declarative, no UIKit view code except a
  few wrappers: `DocumentPicker`, `ShareSheet`).
- **Persistence:** SwiftData (`@Model`), synced via CloudKit
  (`ModelConfiguration(cloudKitDatabase: .automatic)` in `BrickDotApp.swift`,
  with a local-only and then in-memory fallback if CloudKit init fails).
- **Settings:** `@AppStorage` / `UserDefaults`.
- **No third-party dependency manager config found in this checkout** —
  confirm in Xcode before assuming SPM packages are present.

## App Structure

- **iPhone** (`horizontalSizeClass == .compact`): `iPhoneRootView` in
  `RootView.swift` — a `TabView` (Profile, Coach, Clients, Stats, More)
  with a custom Home overlay (`HomeView`) shown above the tab bar.
- **iPad / Mac Catalyst** (`horizontalSizeClass == .regular`):
  `iPadRootView` in `RootView.swift` — `NavigationSplitView` sidebar
  (Quick Capture, a "Today" stats card, Saved Searches, then a nav grid)
  with a detail pane driven by `SidebarDestination`.
- `RootView` itself just branches on `horizontalSizeClass` to pick one of
  the two — there is no separate Mac-only view hierarchy to maintain.

## Project Structure

```
BrickDot/
├── BrickDotApp.swift          # @main, ModelContainer/schema, theme, CloudKit fallback chain
├── Constants.swift            # User-editable services list, default hourly rate ($125)
├── TimeLog.swift              # TimeLog model (incremental time entries)
│
├── Models/                    # SwiftData @Model classes
│   ├── Client.swift
│   ├── Entry.swift             # Core work item — see below
│   ├── EntryTemplate.swift / EntryTemplateEditorView.swift
│   ├── Invoice.swift
│   ├── SavedSearch.swift       # Named EntryListView filter combination
│   ├── Subtask.swift / SubtasksSectionView.swift
│   └── UserProfile.swift
│
├── Views/                     # SwiftUI views
│   ├── RootView.swift          # iPhone TabView + iPad/Mac NavigationSplitView
│   ├── HomeView.swift          # Home screen: greeting, dashboard, EntryListView
│   ├── EntryListView.swift     # Shared filter/sort/list UI (Home + ClientDetail)
│   ├── EntriesListView.swift   # Simple read-only list (sidebar shortcuts, ad-hoc lists)
│   ├── LogView.swift           # Standalone "Log" screen (More > Log)
│   ├── EditEntryView.swift / NewEntryView.swift / QuickAddView.swift
│   ├── ClientListView.swift / ClientDetailView.swift / NewClientView.swift
│   ├── ExportView.swift        # CSV export
│   ├── StatsPageView.swift / StatsSectionView.swift / StatsComponents.swift / StatPill.swift
│   ├── ReportsChartsView.swift
│   ├── CoachView.swift         # AI assistant tab (see Utilities/AIService.swift)
│   ├── SearchView.swift
│   ├── SettingsView.swift      # AppPrefsKey definitions live here
│   ├── CalendarMonthView.swift
│   ├── EntryStatus.swift       # EntryStatus enum + display/color mapping
│   ├── EntryRows.swift / GettingStartedCard.swift / StarterTodos.swift / RunningTimerBar.swift
│   ├── Colors.swift / Date+Bounds.swift / DateBoundsTests.swift
│   └── ...
│
├── Utilities/
│   ├── AIService.swift / CoachToolModels.swift / CoachToolWriter.swift   # Coach tab backend
│   ├── SpeechRecognizer.swift  # Voice quick-capture
│   ├── CSVExporter.swift / CSVImporter.swift
│   ├── Backup.swift / AutoBackup.swift
│   ├── InvoiceNumberManager.swift / InvoicePDFRenderer.swift
│   ├── NotificationManager.swift
│   ├── AppTheme.swift          # Theme system (`@Environment(\.appTheme)`), multiple presets
│   ├── TaskDataSerializer.swift
│   ├── DocumentPicker.swift / ShareSheet.swift
│   └── DateExtensions.swift
│
└── Helpers/
    └── DateFormatter+ISO.swift
```

## Key Data Models

### Entry (`Models/Entry.swift`)
- `serviceDate`, `service`, `detail`, `notes`, `hours`, `rate`
- `client: Client?`, `invoice: Invoice?`
- `statusRaw` / computed `status: EntryStatus` (`.todo` / `.inProgress` / `.done`)
- `isImportant: Bool` (starred), `isQuickAdd: Bool` (Quick Capture flag,
  cleared by `markModified()` on any real edit)
- `timerStartedAt: Date?`, `dueDate: Date?`, `completedAt: Date?`, `createdAt: Date`
- `setupAction: String?` — non-nil on the first-run starter todo rows only
- Expense fields (`expenseAmount`, `expenseMarkup`, `expenseMarkupIsPercent`)
- Communication fields (`commChannel`, `commDirection`, `commContact`) used
  when `service == "COMM"`
- `timeLogs: [TimeLog]` / `subtasks: [Subtask]` (cascade delete)

### EntryStatus (`Views/EntryStatus.swift`)
```swift
public enum EntryStatus: String, Codable, CaseIterable {
    case todo = "To Do"        // displayLabel: "On Deck"
    case inProgress = "In Progress"
    case done = "Done"
}
```
`.todo`'s *stored* rawValue is still `"To Do"` — only the UI-facing
`displayLabel` says "On Deck". Don't rename the rawValue without a migration.

### SavedSearch (`Models/SavedSearch.swift`)
Persists an `EntryListView` filter combination (category, status filters,
date range, client, sort) under a name so it can be applied with one tap
from a chip row (Home/ClientDetail) or from the iPad/Mac sidebar.

### EntryListView filter/sort types (`Views/EntryListView.swift`)
`EntryCategory` (all / quickCaptures / done — single-select, segmented
control), `FilterType` (starred / inProgress / overdue / todo — ANDed
together, from the Filter sheet), `DateQuickPick` (today / thisWeek /
thisMonth, or a custom range), `SortOption` (recent / dueDate / client).
All three enums are `String`-backed so `SavedSearch` can persist them.

## Conventions and Patterns

### SwiftData Usage
- All models use `@Model`; register new models in the `Schema([...])`
  array in `BrickDotApp.swift` or they silently won't persist/query.
- Use `persistentModelID` for `ForEach(..., id: \.persistentModelID)` and
  for `Equatable`/`Hashable` conformance (see `Client`).
- Avoid complex `#Predicate` macro expressions (iOS 17.x bugs are noted
  elsewhere in this codebase) — filter in Swift instead, as every existing
  view does.
- CloudKit sync is on by default with an automatic local-only fallback;
  don't assume `try? ctx.save()` failures are silent no-ops during testing
  — check `cloudkit.fallbackToLocal` in `UserDefaults`.

### View Patterns
- `@Environment(\.modelContext)` for the SwiftData context,
  `@Environment(\.appTheme)` for theme colors (don't hardcode `Color(...)`
  in new UI — use the theme).
- `@Environment(\.horizontalSizeClass)` is the iPhone/iPad+Mac branch
  point — check it before assuming a view only runs on one form factor.
- `EntryListView` is shared between `HomeView` (global list) and
  `ClientDetailView` (`isClientScoped: true`, which hides the Client
  filter and the saved-search row).

### Settings/Preferences
Preference keys live near their usage (e.g. `AppPrefsKey` in
`SettingsView.swift`, `OnboardingPrefs` in `HomeView.swift`) rather than
one central enum — grep before adding a new key in case one already
covers it.

## Development Workflow

### Build Requirements
- Xcode 15.x+, iOS deployment target 17.0+.
- No Swift/Xcode toolchain is available in this remote sandbox — changes
  made here cannot be compiled or run. Verify in Xcode before trusting a
  change is correct.

### Adding a New Entry Field
1. Add the property to `Models/Entry.swift` (with a default value —
   CloudKit/SwiftData migrations are easiest when every property has one).
2. Update the initializer.
3. Update `NewEntryView.swift` / `EditEntryView.swift` / `EntryFormSection.swift`.
4. Update `Utilities/CSVExporter.swift` (header + row).
5. Update `Utilities/Backup.swift` DTOs if the field should be backed up.

### Adding a New Filter/Sort Option to EntryListView
1. Add the case to the relevant enum (`EntryCategory` / `FilterType` /
   `DateQuickPick` / `SortOption`) in `Views/EntryListView.swift` — keep
   the `String` raw value stable once shipped, since `SavedSearch` persists it.
2. Wire the predicate into `EntryListView`'s `matches`/`matchesDate`/etc.
3. Mirror the same predicate in `SavedSearch.matchingEntries(in:)`
   (`Models/SavedSearch.swift`) — it's a separate implementation used by
   the iPad/Mac sidebar, not a shared function, so it needs updating too.

## Git / Branching

This repo has **no `main`/`master` branch** in its history prior to
2026-07 — every prior line of work lived on an ad-hoc Claude Code session
branch, and several diverged from an early, mostly-empty snapshot without
ever merging back. `main` was established on 2026-07-24 from the most
current branch at the time (`claude/plan-next-steps-D573Y`) — treat `main`
as the source of truth going forward, and if you're picking up a session
on a differently-named branch, diff it against `main` first rather than
assuming it's current.

## Common Pitfalls

- **"Invalid redeclaration"**: check for duplicate type definitions across
  files with similar names.
- **Predicate macro errors**: avoid complex `#Predicate` expressions;
  filter in Swift instead (see SwiftData Usage above).
- `EntryStatus.todo.displayLabel` is `"On Deck"` in the UI but the stored
  rawValue is still `"To Do"` — don't assume the two match when reading
  copy or writing tests.

## External Links
- Support: https://ohnodesign.com/support
- Privacy: https://ohnodesign.com/privacy
- Website: https://ohnodesign.com
