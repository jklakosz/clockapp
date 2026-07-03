import SwiftUI

/// A compact day × hour heatmap. Cells flex to fill the available width, so it fits
/// whatever container it's dropped into (e.g. the menubar popup).
struct HeatmapView: View {
    @EnvironmentObject private var state: AppState
    /// [weekdayIndex 0=Mon ... 6=Sun][hour 0...23] of seconds tracked.
    let grid: [[TimeInterval]]

    private let labelWidth: CGFloat = 22

    /// Row 0=Mon…6=Sun → Calendar weekday value (Sun=1, Mon=2 … Sat=7).
    private func weekdayLabel(_ row: Int) -> String {
        state.weekdayShort(row == 6 ? 1 : row + 2)
    }
    private let cellHeight: CGFloat = 11

    var body: some View {
        let maxValue = grid.flatMap { $0 }.max() ?? 0
        VStack(alignment: .leading, spacing: 2) {
            hourRuler
            ForEach(0..<7, id: \.self) { row in
                HStack(spacing: 1) {
                    Text(weekdayLabel(row))
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .frame(width: labelWidth, alignment: .leading)
                    ForEach(0..<24, id: \.self) { hour in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color(for: grid[row][hour], max: maxValue))
                            .frame(maxWidth: .infinity)
                            .frame(height: cellHeight)
                            .help(grid[row][hour] > 0 ? Format.hoursMinutes(grid[row][hour]) : "")
                    }
                }
            }
        }
    }

    private var hourRuler: some View {
        HStack(spacing: 1) {
            Color.clear.frame(width: labelWidth, height: 1)
            ForEach(0..<24, id: \.self) { h in
                Text(h % 6 == 0 ? "\(h)" : "")
                    .font(.system(size: 6))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func color(for seconds: TimeInterval, max: TimeInterval) -> Color {
        let intensity = max > 0 ? seconds / max : 0
        return Color.accentColor.opacity(intensity == 0 ? 0.06 : 0.15 + 0.85 * intensity)
    }
}
