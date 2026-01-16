import SwiftUI

struct SharedStatPill: View {
    let title: String
    let entries: [Entry]
    let icon: String

    private var currencyCode: String { Locale.current.currency?.identifier ?? "USD" }
    private var totalHours: Double { entries.reduce(0) { $0 + $1.hours } }
    private var totalAmount: Double { entries.reduce(0) { $0 + ($1.hours * $1.rate) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .imageScale(.medium)
                    .foregroundStyle(.accent)
                Text(title)
                    .font(.subheadline).fontWeight(.semibold)
            }

            Text(totalAmount, format: .currency(code: currencyCode))
                .font(.title3).fontWeight(.semibold)
                .monospacedDigit()

            HStack {
                Text("\(totalHours, specifier: "%.2f")h")
                Spacer(minLength: 8)
                Text("\(entries.count)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}
