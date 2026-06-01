import SwiftUI

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
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                SharedStatusMark(color: .orange, isImportant: entry.isImportant)
                Text(entry.clientName)
                    .font(.subheadline).fontWeight(.semibold)
                Spacer()
                Text(entry.service)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(entry.detail.isEmpty ? "No description" : entry.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

struct SharedInProgressRow: View {
    let entry: Entry
    @State private var tick = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                SharedStatusMark(
                    color: Color(red: 0.72, green: 0.19, blue: 0.15),
                    isImportant: entry.isImportant,
                    pulsing: entry.timerStartedAt != nil
                )
                Text(entry.clientName)
                    .font(.subheadline).fontWeight(.semibold)
                Spacer()
                if entry.timerStartedAt != nil {
                    Text(entry.runningElapsedHoursOrZero.hoursMinutesString)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    Text(entry.service)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if !entry.detail.isEmpty {
                Text(entry.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .onReceive(timer) { now in _ = now; tick = now }
    }
}

struct SharedDoneRow: View {
    let entry: Entry
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                SharedStatusMark(color: .green, isImportant: entry.isImportant)
                Text(entry.clientName)
                    .font(.subheadline).fontWeight(.semibold)
                Spacer()
                Text(entry.service)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !entry.detail.isEmpty {
                Text(entry.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

struct SharedEntryRow: View {
    let entry: Entry
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                SharedStatusMark(
                    color: statusColor(entry.status),
                    isImportant: entry.isImportant,
                    pulsing: entry.status == .inProgress && entry.timerStartedAt != nil
                )
                Text(entry.clientName).font(.headline)
                Spacer()
                Text(entry.hours * entry.rate,
                     format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                .font(.subheadline)
            }
            if !entry.detail.isEmpty {
                Text(entry.detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: 8) {
                Text(entry.service); Text("•")
                Text(entry.serviceDate, format: .dateTime.year().month().day())
                Spacer()
                Text("\(entry.hours, specifier: "%.2f")h")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}
