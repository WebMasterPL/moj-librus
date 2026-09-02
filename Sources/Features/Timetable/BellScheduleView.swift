import SwiftUI

struct BellScheduleView: View {
    @Environment(DataRepository.self) private var repo

    private var nowMinutes: Int { LibrusDate.nowMinutesOfDay }

    var body: some View {
        List {
            if repo.bellSchedule.isEmpty {
                EmptyStateView(systemImage: "bell.slash", title: "Brak rozkładu dzwonków",
                               message: "Pociągnij w dół, aby odświeżyć.")
            }

            ForEach(repo.bellSchedule) { period in
                HStack(spacing: 14) {
                    Text("\(period.number)")
                        .font(.headline.monospacedDigit())
                        .frame(width: 28)
                        .foregroundStyle(isNow(period) ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(period.start) – \(period.end)")
                            .font(.callout.monospacedDigit())
                            .fontWeight(isNow(period) ? .semibold : .regular)
                        if let len = lengthMinutes(period) {
                            Text("\(len) min").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    if isNow(period) {
                        Text("teraz")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.tint, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .navigationTitle("Rozkład dzwonków")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await repo.refreshCore() }
    }

    private func isNow(_ p: BellPeriod) -> Bool {
        guard let s = LibrusDate.minutesOfDay(p.start), let e = LibrusDate.minutesOfDay(p.end) else { return false }
        return nowMinutes >= s && nowMinutes < e
    }

    private func lengthMinutes(_ p: BellPeriod) -> Int? {
        guard let s = LibrusDate.minutesOfDay(p.start), let e = LibrusDate.minutesOfDay(p.end), e > s else { return nil }
        return e - s
    }
}
