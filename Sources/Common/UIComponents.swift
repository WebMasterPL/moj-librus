import SwiftUI
import UIKit

/// Shared visual building blocks so every screen looks like one app.

extension Color {
    static let cardBackground = Color(uiColor: .secondarySystemBackground)
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct SectionHeader: View {
    let title: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage) }
            Text(title)
        }
        .font(.headline)
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    var message: String?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let message { Text(message) }
        }
    }
}

struct ErrorBanner: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text(message).font(.footnote)
                if let retry {
                    Button("Spróbuj ponownie", action: retry)
                        .font(.footnote.bold())
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Colour for a grade value (1 red … 6 green).
func gradeColor(for value: Double?) -> Color {
    guard let value else { return .secondary }
    switch value {
    case ..<1.75: return .red
    case ..<2.75: return .orange
    case ..<3.75: return .yellow
    case ..<4.75: return .mint
    default: return .green
    }
}

func attendanceColor(_ kind: AttendanceKind) -> Color {
    switch kind {
    case .present, .presentCustom: return .green
    case .absent: return .red
    case .absentExcused: return .orange
    case .belated: return .yellow
    case .released: return .blue
    }
}

extension Color {
    /// "RRGGBB" hex from the Librus API (no leading #).
    init?(librusHex hex: String?) {
        guard let hex, hex.count == 6, let value = Int(hex, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
