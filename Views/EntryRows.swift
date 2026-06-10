import SwiftUI

// MARK: - Communication Channel Icon Helper

func commChannelIcon(for channel: String?) -> String? {
    switch channel {
    case "phone": return "phone.fill"
    case "email": return "envelope.fill"
    case "text":  return "message.fill"
    case "chat":  return "bubble.left.fill"
    default:      return nil
    }
}

struct SharedStatusMark: View {
    let color: Color
    let isImportant: Bool
    var pulsing: Bool = false

    @State private var animate = false

    var body: some View {
        Image(systemName: isImportant ? "star.fill" : "circle.fill")
            .foregroundStyle(color)
            .font(.system(size: isImportant ? 12 : 8))
            .scaleEffect(pulsing && animate ? 1.35 : 1.0)
            .opacity(pulsing && animate ? 0.45 : 1.0)
            .onAppear { startIfNeeded() }
            .onChange(of: pulsing) { _, _ in startIfNeeded() }
    }

    private func startIfNeeded() {
        animate = false
        if pulsing {
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

struct SharedTodoRow: View {
    let entry: Entry
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            SharedStatusMark(color: theme.dueToday, isImportant: entry.isImportant)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if entry.service == "COMM", let icon = commChannelIcon(for: entry.commChannel) {
                        Image(systemName: icon)
                            .font(.caption)
                            .foregroundStyle(theme.accent)
                    }
                    Text(entry.detail.isEmpty ? entry.service : entry.detail)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(entry.service.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(theme.accent)
                    Text("·").foregroundStyle(.secondary)
                    Text(entry.clientName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(entry.serviceDate, format: .dateTime.month(.abbreviated).day())
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct SharedInProgressRow: View {
    let entry: Entry
    @Environment(\.appTheme) private var theme
    @State private var tick = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 10) {
            SharedStatusMark(
                color: theme.running,
                isImportant: entry.isImportant,
                pulsing: entry.timerStartedAt != nil
            )
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if entry.service == "COMM", let icon = commChannelIcon(for: entry.commChannel) {
                        Image(systemName: icon)
                            .font(.caption)
                            .foregroundStyle(theme.accent)
                    }
                    Text(entry.detail.isEmpty ? entry.service : entry.detail)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(entry.service.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(theme.accent)
                    Text("·").foregroundStyle(.secondary)
                    Text(entry.clientName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if entry.timerStartedAt != nil {
                Text(entry.runningElapsedHoursOrZero.hoursMinutesString)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(theme.running.opacity(0.15)))
                    .foregroundStyle(theme.running)
            } else {
                Text(entry.serviceDate, format: .dateTime.month(.abbreviated).day())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .onReceive(timer) { tick = $0 }
    }
}

struct SharedDoneRow: View {
    let entry: Entry
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            SharedStatusMark(color: theme.success, isImportant: entry.isImportant)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if entry.service == "COMM", let icon = commChannelIcon(for: entry.commChannel) {
                        Image(systemName: icon)
                            .font(.caption)
                            .foregroundStyle(theme.accent)
                    }
                    Text(entry.detail.isEmpty ? entry.service : entry.detail)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(entry.service.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(theme.accent)
                    Text("·").foregroundStyle(.secondary)
                    Text(entry.clientName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let completed = entry.completedAt {
                Text(completed, format: .dateTime.month(.abbreviated).day())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct SharedEntryRow: View {
    let entry: Entry
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            SharedStatusMark(
                color: statusColor(entry.status),
                isImportant: entry.isImportant,
                pulsing: entry.status == .inProgress && entry.timerStartedAt != nil
            )
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if entry.service == "COMM", let icon = commChannelIcon(for: entry.commChannel) {
                        Image(systemName: icon)
                            .font(.caption)
                            .foregroundStyle(theme.accent)
                    }
                    Text(entry.detail.isEmpty ? entry.service : entry.detail)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(entry.service.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(theme.accent)
                    Text("·").foregroundStyle(.secondary)
                    Text(entry.clientName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(entry.hours * entry.rate,
                     format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                    .font(.subheadline)
                if entry.hours > 0 {
                    Text("\(entry.hours, specifier: "%.1f")h")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 2)
    }
}

