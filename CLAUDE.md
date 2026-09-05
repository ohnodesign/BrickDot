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
│   ├── AIService.swift              # Claude API call, model choice, system prompt
│   ├── CoachSession.swift           # Coach transcript + agentic loop (owned by RootView)
│   ├── CoachToolSchema.swift        # Tool definitions sent to the API
│   ├── CoachToolWriter.swift        # Write tools + EntryResolver + CoachToolFormat
│   ├── CoachToolReader.swift        # Read tools (tasks / summaries / clients / invoices)
│   ├── CoachToolPolicy.swift        # Which calls auto-apply vs wait for a tap
│   ├── CoachToolModels.swift        # CoachToolCall, PendingChange, ToolResultBlock
│   ├── CoachBridge.swift            # Loopback HTTP bridge (Mac only, off by default)
│   ├── ClientNameCache.swift        # Safe client lookups — see SwiftData Usage
│   ├── StoreMode.swift              # Which store opened + the warning banner
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
- **Every `@Relationship` must declare an inverse.** CloudKit refuses to
  load the *entire store* if even one relationship lacks one — the app
  then silently falls back to local-only and nothing syncs, app-wide.
  The console error is
  `CloudKit integration requires that all relationships have an inverse`.
  When adding a model with a reference to another model, add the matching
  inverse property on the other side (see `Client.savedSearches` ↔
  `SavedSearch.client`).
- Related CloudKit requirements: every property needs a default value, and
  relationships must be optional.
- CloudKit sync is on by default with an automatic local-only fallback.
  `cloudkit.fallbackToLocal` in `UserDefaults` is true whenever the app is
  running in that degraded mode, and is only cleared by an actual CloudKit
  success — check it before debugging "X doesn't sync" reports.
- **Never render a child collection from a parent's relationship array.**
  `entry.timeLogsList` / `entry.subtasksList` are cached on the parent and
  can still contain a child whose row is gone, because a delete that
  arrived from another device via CloudKit *invalidates* the object rather
  than marking it deleted: `isDeleted` is false, `modelContext` is non-nil,
  and the next stored-property read traps with
  `EXC_BREAKPOINT in <Model>.<property>.getter`. `Utilities/ModelLiveness.swift`
  (`isAlive` / `.live`) cannot see this state — it is only good for
  references the user deletes in this app. Instead take a `@Query` of the
  child type and filter it in Swift on `parent?.persistentModelID`, as
  `EditEntryView` does; a query refetches on the merge that removed the row.
  Mutating the relationship array (`append`, `remove(at:)`) stays fine.
- **The same applies to `entry.client`.** Reading `client?.name` crashed the
  entry list in 2026-09: `EntryListRow` → `displayClientName` → `clientName` →
  the Client's row was gone and the getter trapped. `Entry.clientName`,
  `Entry.clientRate` and `Invoice.safeClientName` now resolve through
  `Utilities/ClientNameCache.swift` (`ClientInfoCache`), which reads names from
  a fetch — only rows that exist come back — and caches them by
  `persistentModelID`, dropping the cache on save or remote change. A fetch per
  row is far too slow for a scrolling list, hence the cache. **Do not reintroduce
  a direct `client?.name` read anywhere.** Identity reads
  (`persistentModelID`, `==`) stay safe on such a model, which is what makes the
  indirection work.

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

## AI Coach and the Claude Bridge

The Coach runs an **agentic loop**, not a single call. `CoachSession.runLoop()`
sends, applies whatever tools come back, feeds the `tool_result` blocks in, and
goes again until the model stops calling tools or hits `AIService.maxLoopTurns`.
A confirmation *suspends* the loop; `applyChanges`/`dismissChanges` resume it.
(Before 2026-09 the results were recorded in the transcript and never sent, so
the model only learned what happened on the next user message.)

- **`CoachSession` is owned by `RootView`** and injected via the environment.
  It was `@State` on `CoachView`, which meant leaving the tab discarded the
  transcript and any pending confirmation mid-loop.
- **Confirmation is tiered** (`CoachToolPolicy`): single-task edits apply
  immediately; several tasks at once, `bulkUpdate`, anything already invoiced,
  and `createInvoice` wait for a tap. A batch is all-or-nothing, because the API
  needs a `tool_result` for every `tool_use` block in a turn.
- **Every tool name in `CoachToolSchema` needs a case** in `CoachToolExecutor`
  (writes) or `CoachToolReader` (reads), and a tier in `CoachToolPolicy`.
- **`createTask` files as a Quick Capture unless a status is passed** — an
  unreviewed note belongs in that section. `markModified()` clears the flag on
  the first real edit.
- **`listClients` is the join to the outside world.** Work folders on the
  FatBoy drive are named `YYYY-MM-DD-<shortcode>-<description>`, so a client's
  `shortcode` maps a folder to a BrickDot client without guessing at names
  ("Cobblestone" on disk vs "Cobblestone Homes" in the app). Shortcodes are not
  unique per folder — the parent client folder is authoritative, the prefix is a
  cross-check.
- **An entry with no invoice attached is not necessarily unbilled.** Invoicing
  happens in QuickBooks — monthly data is exported from BrickDot, adjusted
  there, and the invoice record in the app is created after the fact, if at all.
  Cobblestone shows every 2026 entry unlinked while being billed through
  QuickBooks to the start of 2026. Report this as "not linked to an invoice
  here", never as "unpaid"; `listInvoices` shows what is actually on record.
- **The payload in the system prompt is open work only.** Completed and invoiced
  work must be reached with `findTasks(status:)` or `getClientSummary`.
- **Prompt caching** is on via a top-level `cache_control` breakpoint. In DEBUG,
  every call logs `[Coach] tokens in=… cached_read=… — N¢`.

The bridge (`CoachBridge.swift`) is a loopback listener, Mac Catalyst only, off
by default, guarded by a bearer token, with a read-only mode. `GET /tools`
serves the real schema so the Node MCP server in `mcp/` mirrors whatever the
build supports. `createInvoice` is refused over the bridge — it consumes a
sequential invoice number and marks work billed, and the bridge has no
confirmation UI.

**`GET /health` is the debugging tool.** It reports `entryCount`, `clientCount`,
`storeInMemoryOnly`, `storePath`, `fallbackToLocal`, `pid`, `launchedAt` and
`built`. Every one of those was added after a long guessing session that the
fact would have ended in one line. Two worth knowing:

- An empty snapshot means either no work *or* a container that fell through to
  the in-memory fallback — `storeInMemoryOnly` distinguishes them.
- A rebuild replaces the binary on disk but a running process keeps its old
  code, and port reuse lets a stale instance keep answering. Check `built`
  before concluding a change didn't work.

## Billing records vs work entries

QuickBooks invoice CSVs import as `Entry` rows so an invoice can be opened and
read line by line. They are **not** work. Michael's intent, in his words: the QB
entries are "a fail safe on my end so I can go back and make sure that I billed
something" and were never meant to appear in the main BrickDot lists.

Before this existed, an import dropped its line items straight into the task
lists next to the hand-logged work for the same days, which read as duplicated
work — Cobblestone showed 390 hours for 2025 against 266 hours actually logged.

The wall:

- `Entry.isBillingRecord` — true for imported line items.
- `Invoice.isImported` — true for invoices that came from a CSV.
- `Entry.workOnlyPredicate` / `Entry.workOnly(_:)` — the single filter. Every
  `@Query` and `FetchDescriptor<Entry>` that feeds a list, count, chart, or
  Coach tool uses it.

Three places deliberately do **not** filter, and each will break if you "fix" it:

- `InvoiceDetailView` — reads `invoice.entriesList`, so it shows the line items.
  That view *is* the failsafe.
- `CoachToolReader.listInvoices` — filtering here would report every imported
  invoice as having zero items.
- `CSVImporter` dedup and `Backup` — dedup has to see the records it compares
  against; a backup that dropped them would lose the billing history.

`BillingRecordMigration` walls off what was already in the store, once, guarded
by UserDefaults. Its rule is `Invoice.number != nil`, because only the importer
ever set a number — invoices built in the app leave it nil. That distinction is
load-bearing: at the time it was written the store held 14 numbered QuickBooks
invoices and one in-app invoice built from real tracked work, and a blanket
"has an invoice → hide it" rule would have hidden that real work. It also
refuses to reclassify any entry carrying time logs or subtasks.

### Money comes from invoices

Client Profitability on the Stats page reads `Invoice`, not entries. Summing
`hours * rate` over entries answers "what is this work theoretically worth",
which drifts from the money as soon as anything is written off or bundled. The
invoices are what was actually charged, and the imported QuickBooks history now
reaches back through 2025. `getClientSummary` follows the same rule:
`invoiced_amount` comes from invoices; the entry-side number is labelled
`unlinked_`, because an entry with no invoice link is unlinked, not unpaid.

Caveat when reading a short period: some imported invoices fell back to their
import date because QuickBooks' date column did not parse, so they cluster on
the day they were brought in. "All Time" is unaffected.

## Open Items / Known Tradeoffs

- `TaskDataSerializer` emits `elapsed_minutes` for a running timer, which
  changes every second and so busts the prompt cache while a timer runs. Drop it
  and let the model call `getTaskDetail` if it needs the figure.
- Task ids in the payload are ~250-character base64 `PersistentIdentifier`
  blobs — roughly 2,600 tokens per call with 40 open tasks, over a quarter of
  the input. Short handles with a lookup table would claw that back.
- `createTask` falls back to `Constants.services.first` when no service is
  given, which lands arbitrary entries under whatever that happens to be.
- The MCP server has no `tools/list_changed` notification, so schema changes
  need a Claude Desktop restart to reach the model.
- `ClientInfoCache` invalidation hangs off save and remote-change
  notifications; freshness on client *renames* has not been exercised much.
- Bridge writes have no audit trail and no undo. Given they touch billing data,
  an append-only journal (tool, arguments, result, timestamp) is the next
  safety net worth building.
- The Anthropic API key is in `UserDefaults`, not the Keychain.
- `try?` swallowing fetch errors into empty results is widespread — an empty
  array reads as "no data" when it may mean "the fetch failed". This is what
  turned a store problem into an afternoon of wrong theories.

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
