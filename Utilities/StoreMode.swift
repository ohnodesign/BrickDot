import SwiftUI

/// Which store the app actually opened at launch.
///
/// `BrickDotApp` falls back CloudKit → local-only → in-memory, and until now it
/// did so silently. An in-memory fallback gives you a fully working app with an
/// empty database and no indication anything is wrong — indistinguishable from
/// "I have no work", which is exactly how it read twice. The dangerous part
/// isn't the confusion: anything logged into that store evaporates on quit.
enum StoreMode: String {
    case cloudKit
    case localOnly
    case inMemory

    private static let key = "store.mode"

    static var current: StoreMode {
        get { StoreMode(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .cloudKit }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    var isHealthy: Bool { self == .cloudKit }

    var title: String {
        switch self {
        case .cloudKit:  return ""
        case .localOnly: return "Not syncing to iCloud"
        case .inMemory:  return "Changes are not being saved"
        }
    }

    var detail: String {
        switch self {
        case .cloudKit:
            return ""
        case .localOnly:
            return "Work is saved on this device only. Your data on other devices is untouched, and this usually resolves on the next launch."
        case .inMemory:
            return "BrickDot couldn't open its database and is running on a temporary one. Anything entered now is lost on quit. Your data is safe in iCloud — quit and reopen to try again."
        }
    }

    var isSevere: Bool { self == .inMemory }
}

/// Shown above everything when the store isn't the real one. Renders nothing in
/// the normal case, so it costs a branch and no layout.
struct StoreStatusBanner: View {
    @Environment(\.appTheme) private var theme
    @State private var expanded = false

    private let mode = StoreMode.current

    var body: some View {
        if mode.isHealthy {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation { expanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: mode.isSevere
                              ? "exclamationmark.triangle.fill"
                              : "icloud.slash.fill")
                        Text(mode.title)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                if expanded {
                    Text(mode.detail)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(mode.isSevere ? theme.overdue : Color.orange)
        }
    }
}
