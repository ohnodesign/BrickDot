# Quickbooks Invoicing (Ohno Design)

A lightweight iOS app to log billable work per client and export **QuickBooks-friendly CSVs** by client and time period.

## Requirements
- **Xcode**: 15.x or newer
- **iOS Deployment Target**: 17.0+ (uses **SwiftData**)
- **Swift Packages (optional)**: [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) for zipping multi‑month exports into one file

## Project Structure
```
OhnoinvoiceApp.swift                 // @main app entry
Models/
  Client.swift                       // SwiftData @Model: name (unique), rate
  Entry.swift                        // SwiftData @Model: serviceDate, service, detail, hours, rate, client (rel), amount (computed)
Views/
  RootView.swift                     // Tab root: Clients / New Entry / Log / Export
  ClientListView.swift               // Add/manage clients + quick export actions
  NewEntryView.swift                 // Create entries with date, service, description, hours
  LogView.swift                      // List of entries + full CSV export
  ExportView.swift                   // Per‑client, per‑month/date‑range export UI
Utilities/
  CSVExporter.swift                  // CSV header mapping + writers (single and per‑month)
  ShareSheet.swift                   // UIActivityViewController wrapper
  ZipHelper.swift (optional)         // Requires ZIPFoundation (optional)
Helpers/
  DateFormatter+ISO.swift            // yyyy‑MM‑dd formatter for CSV
  Date+MonthBounds.swift             // startOfMonth/endOfMonth + labels
  Constants.swift                    // Services list + default rate
Assets.xcassets/                     // App icons, etc.
```

## First‑Run Checklist
1. **Deployment target**: iOS **17.0+** (Target → General).
2. **Model container**: In `OhnoinvoiceApp.swift` the app sets `.modelContainer(for: [Client.self, Entry.self])`.
3. **Target Membership** for all app Swift files: **App target ✅**, **Tests ❌**, **UI Tests ❌**.
4. If installing to a device:
   - Enable **Developer Mode** on the iPhone.
   - In **Signing & Capabilities**, select your Apple ID **Team** and enable **Automatically Manage Signing**.
   - Trust the developer cert on device: *Settings → General → VPN & Device Management*.

## Using the App
### Clients
- Add a client name and rate in **Clients** tab.
- Long‑press a client row (or swipe) for **Quick Export** options:
  - *Export This Month*
  - *Export Last Month*

### New Entry
- Choose **Client**, **Service**, **Service Date**, **Description**, **Hours**.
- The Amount is computed from the client’s rate.
- Keyboard has a **Done** button; hides after Save.

### Log
- Shows all entries (newest first).
- Toolbar **Export CSV** creates a full CSV of every entry currently stored.

### Export (Per‑Client)
Pick a **Client** and choose one of:
- **Month**: one CSV for the selected month.
- **Months**: creates one CSV per month in the range.
  - With **ZIPFoundation**, they are zipped into one `.zip` for sharing; otherwise, multiple CSVs are shared.
- **Range**: one CSV for an arbitrary date range.

Toggle **“Use QuickBooks‑style headers”** to switch between default and QuickBooks column names.

**File naming**
- Month: `ClientName_YYYY-MM.csv`
- Multi-month zip: `ClientName_YYYY-MM_to_YYYY-MM.zip`
- Date range: `ClientName_YYYY-MM-DD_to_YYYY-MM-DD.csv`

**CSV Columns**
- **Default**: `Service Date, Customer, Service, Description, Quantity, Rate, Amount`
- **QuickBooks**: `TxnDate, Customer, Service, Description, Qty, Rate, Amount`

Exports are written to a temporary file and presented via the iOS **share sheet** (Mail, Files, Messages, etc.).

## Customizing
### Services & Default Rate
Edit `Constants.swift`:
```swift
enum Constants {
    static let services: [String] = [/* ... */]
    static let defaultRate: Double = 125
}
```

### Adding Fields
1. Update `Models/Entry.swift` (or `Client.swift`) with the new properties.
2. Adjust forms in `NewEntryView.swift` / `ClientListView.swift` to capture the fields.
3. Update `CSVExporter.swift`:
   - Add to `ExportHeaders.columns` (and `.quickBooks` if needed).
   - Update the row builder to include the new field values.
4. Rebuild and test the new CSV.

## Optional: ZIP Support
To export a **single .zip** for multi‑month:
1. Xcode → **File → Add Packages…**
2. Enter: `https://github.com/weichsel/ZIPFoundation`
3. Add to the **app target** only.
4. Keep `ZipHelper.swift` in `Utilities/` (already coded to be optional).

## Troubleshooting
- **Invalid redeclaration / duplicate output**: Ensure there’s only **one** definition of each type, and each Swift file appears **once** in **Build Phases → Compile Sources**. Remove from Test targets.
- **Cannot find ‘RootView’/type in scope**: Fix broken file references (red files) and re‑add them; check Target Membership.
- **Previous preparation error / Unable to copy shared cache files**: Clear DeviceSupport & DerivedData, ensure Xcode supports your iOS version.
- **Untrusted Developer**: Trust the dev cert on device (Settings → General → VPN & Device Management).
- **Predicate macro error** in Client quick export: we filter in Swift using `persistentModelID` to avoid `#Predicate` issues on iOS 17.x.
- **Keyboard won’t dismiss**: `@FocusState` + toolbar Done is already wired in both Clients and New Entry.

## Maintenance Tips
- Keep **enums/structs** in a **single file** each (e.g., `ExportMode` + `ExportView` live in `ExportView.swift` only).
- When you change a function signature (e.g., added `fileName` to `CSVExporter.export`), update **all call sites**:
  - `LogView` toolbar export
  - `ExportView` buttons
  - Any quick‑export helpers
- If you introduce large datasets, we can switch the in‑memory filters to SwiftData `@Query` with runtime predicates.

---

Happy logging and exporting! If you want, I can also add a simple unit test suite to check CSV header/row formatting so future changes don’t break QuickBooks imports.
