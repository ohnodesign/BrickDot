# BrickDot — Home Screen & Client Page List Redesign
### Claude Code Implementation Prompt

---

## Context

BrickDot is an iOS app (SwiftUI + SwiftData) for freelance work and time management.
Project location: `/Users/michaelrobb/Documents/BrickDot`

The current home screen shows entries grouped by status (In Progress, To Do, etc.) in separate sections with individual "Show more" toggles. This is being replaced with a smarter, more compact unified list layout.

The same layout applies to **both the home screen and client detail pages** — build it as a shared component.

---

## Before Starting

1. Locate the home screen view file and the client detail page view file
2. Locate the SwiftData Entry/Task model and confirm the exact property names for:
   - Entry title
   - Client/project name
   - Status (and what the status string values are — e.g. "inProgress", "todo", "done")
   - isImportant / isStarred (the star flag)
   - isInFocus / todaysFocus flag
   - isQuickCapture flag (or however quick captures are identified — no client assigned, or a specific flag)
   - dueDate
   - createdAt / dateCreated
   - updatedAt / lastModified (whichever exists)
   - serviceType (PHOTO, PRINT, WEBCUST, DESIGN, WEBUP, CONSULT, SOCIAL, COMM, etc.)
3. Read CLAUDE.md for any project-specific conventions before writing any code

---

## New Home Screen Structure

Replace the current sectioned list with this fixed structure, top to bottom:

```
┌─────────────────────────────┐
│  TODAY'S FOCUS              │  ← existing pinned section, no changes
│  [focus items]              │
├─────────────────────────────┤
│  QUICK CAPTURES             │  ← new pinned section
│  [unprocessed items]        │
├─────────────────────────────┤
│  [Filter Pills] [Sort Bar]  │  ← new controls
│  [Unified filtered list]    │  ← new main list
├─────────────────────────────┤
│  DONE  ▸                    │  ← collapsed by default, always
│  [done items, if expanded]  │
└─────────────────────────────┘
```

---

## Section 1: Today's Focus

Keep exactly as it currently exists. No changes to this section.

---

## Section 2: Quick Captures

Quick Captures are entries created via the quick capture button that have not yet been assigned a client/project (or however they are currently identified in the data model — confirm this before building).

Display rules:
- Pinned directly below Today's Focus
- Section header: "QUICK CAPTURES" styled consistently with Today's Focus header
- Each row gets a **yellow triangle** bullet instead of the standard dot or star
  - Use SF Symbol `triangle.fill` colored yellow/amber (`Color.yellow` or `Color(.systemYellow)`)
  - Size: approximately 10pt, vertically centered with the title
- If there are no Quick Captures, hide this section entirely (no empty state header)
- Quick Captures do NOT appear in the main filtered list below

---

## Section 3: Main Filtered List

### Filter Pills

A horizontally scrollable row of pill-shaped toggle buttons. Tapping a pill toggles it on/off. Multiple pills can be active simultaneously.

Pills (in this order):
`Starred` · `In Progress` · `Overdue` · `To Do`

**Default state on launch:** All four pills active (show everything except Done and Quick Captures)

**Active pill style:** Filled background using app's primary brand color, white text
**Inactive pill style:** Outlined border, secondary text color

Implementation: `ScrollView(.horizontal, showsIndicators: false)` containing an `HStack` of toggle buttons. Store active filters in `@State var activeFilters: Set<FilterType>` in the view or view model — not in SwiftData or UserDefaults (resets each session is fine).

### Sort Bar

Sits to the right of or below the filter pills. Three options, only one active at a time:

`Recent` · `Due Date` · `Client`

**Recent** = sort by `updatedAt` / `lastModified` descending (most recently touched first) — **this is the default**

**Due Date** = sort ascending by dueDate, with nil due dates at the bottom

**Client** = group by client name alphabetically, with section headers between client groups (see Client Sort section below)

Implementation: A segmented-style control or three small text buttons with an underline indicator on the active one. Store in `@State var activeSort: SortOption`.

### Filtering Logic

Apply active filter pills to determine which entries appear:

```swift
enum FilterType {
    case starred      // isImportant == true
    case inProgress   // status == "inProgress" (confirm exact string)
    case overdue      // dueDate != nil && dueDate < Date() && status != "done"
    case todo         // status == "todo" (confirm exact string)
}
```

An entry appears in the list if it matches **any** active filter (OR logic, not AND). This way Starred + In Progress shows everything that is either starred or in progress.

Exclude from this list:
- Entries in Today's Focus (already shown above)
- Quick Captures (already shown above)
- Done entries (shown in Done section below)

### Row Appearance

Each row displays: bullet/star · title · service type tag · client name · date

**Star bullet:**
- If `isImportant == true`: show a red star (`star.fill`, `Color.red`)
  - If the entry is ALSO overdue: animate the star with a repeating pulse
    ```swift
    // Apply only when isImportant && isOverdue
    .opacity(isPulsing ? 0.4 : 1.0)
    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), 
                value: isPulsing)
    .onAppear { isPulsing = true }
    ```
  - Use a custom `OverdueStarView` subview so the animation is isolated per row and doesn't affect list performance
- If `isImportant == false`: show a standard bullet dot, color matching service type or neutral gray

**Important:** Only apply the pulse animation when both conditions are true (starred AND overdue). A plain overdue non-starred item gets no special bullet treatment — it simply appears when the Overdue filter pill is active.

### Client Sort — Section Headers

When `activeSort == .client`, group entries by client name and insert section headers:

```swift
// Group entries
let grouped = Dictionary(grouping: filteredEntries) { $0.clientName }
let sortedKeys = grouped.keys.sorted()
```

Render as a `List` with `Section` headers — one section per client, header showing client name in the standard SwiftUI section header style.

When sort is Recent or Due Date, render as a flat `List` with no section headers.

---

## Section 4: Done

- Section header: "DONE" with a chevron indicating collapsed/expanded state
- **Always starts collapsed** — `@State var doneExpanded = false`, never persisted
- When expanded, shows all entries with `status == "done"`
- Each Done row gets a **green dot** bullet (`circle.fill`, `Color.green`) regardless of whether the entry has a star
- Sort Done entries by most recently completed (updatedAt descending)
- Tapping the header toggles expanded/collapsed with a simple animation

---

## Shared Component — Use on Client Pages Too

Build the main filtered list (filter pills + sort bar + unified list + done section) as a reusable SwiftUI view:

```swift
struct EntryListView: View {
    let entries: [EntryModel]         // passed in — all entries for this context
    var isClientScoped: Bool = false  // true when used on a client detail page
    
    // internal state: activeFilters, activeSort, doneExpanded
}
```

**On the home screen:** Pass all entries, `isClientScoped = false`

**On client detail pages:** Pass only that client's entries, `isClientScoped = true`
- When `isClientScoped == true`, hide the `Client` sort option from the sort bar (it's redundant when already scoped to one client)
- The `Recent` sort becomes the only default and the sort bar may show just `Recent · Due Date` — or hide entirely if only two options feels unnecessary. Use judgment here.

Do NOT copy-paste the view. One shared `EntryListView` component used in both places.

---

## Visual Bullet Summary

| Entry state | Bullet |
|---|---|
| Quick Capture | Yellow triangle (`triangle.fill`, yellow) |
| Starred, any status | Red star (`star.fill`, red) |
| Starred + Overdue | Red star, pulsing opacity |
| Unstarred, active | Neutral dot or service-type color dot |
| Done | Green dot (`circle.fill`, green), no star shown |

---

## What NOT to Change

- Today's Focus section — keep exactly as is
- Entry detail/edit view — no changes
- New Entry form — no changes
- Navigation structure — no changes
- Any existing data model properties — read only, no schema changes needed

---

## Files Likely to Touch

- Home screen view file (contains current sectioned list)
- Client detail page view file
- New file: `EntryListView.swift` (shared component)
- Possibly a view model if filter/sort state is managed there

---

## Pitfalls to Avoid

- **Pulse animation on list rows:** Isolate the pulsing star in its own subview (`OverdueStarView`) so SwiftUI doesn't re-render the whole list on each animation tick
- **Multi-select filter state:** Store in the view or an `@ObservableObject`, not SwiftData — it should not persist between app launches
- **Client sort with headers:** Use SwiftUI `List` with `ForEach` over sorted client keys and `Section` per client — not a flat list with manual header rows
- **Done always collapsed:** `@State var doneExpanded = false` — do not store this in UserDefaults or SwiftData
- **Shared component:** One `EntryListView`, not two copies. The `isClientScoped` flag handles the differences
- **Quick Captures exclusion:** Make sure Quick Capture entries are excluded from the main filtered list and the Done section — they only appear in the Quick Captures pinned section
