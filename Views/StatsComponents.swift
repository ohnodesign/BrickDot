import SwiftUI

struct LoggedTodayPill: View {
    let hours: Double
    let count: Int
    let amount: Double

    init(hours: Double, count: Int, amount: Double) {
        self.hours = hours
        self.count = count
        self.amount = amount
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sun.max.fill")
                    .imageScale(.medium)
                    .foregroundStyle(.accent)
                Text("Logged Today")
                    .font(.subheadline).fontWeight(.semibold)
            }
            Text(amount, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                .font(.title3).fontWeight(.semibold)
                .monospacedDigit()
            HStack {
                Text("\(hours, specifier: "%.2f")h")
                Spacer(minLength: 8)
                Text("\(count)")
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
