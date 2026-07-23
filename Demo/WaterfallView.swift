import SwiftUI
import DeadlineBudgetKit

/// Waterfall timeline of attempt/lane/request lifecycles against the
/// deadline, drawn with plain SwiftUI (no chart dependencies).
struct WaterfallView: View {
    let bars: [LaneBar]
    let deadlineMillis: Double
    let windowMillis: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if bars.isEmpty {
                emptyState
            } else {
                GeometryReader { proxy in
                    let plotWidth = max(1, proxy.size.width - labelWidth - 8)
                    ZStack(alignment: .topLeading) {
                        deadlineRule(plotWidth: plotWidth)
                        rows(plotWidth: plotWidth)
                    }
                }
                .frame(height: max(1, CGFloat(bars.count)) * rowHeight + 24)
                legend
            }
        }
    }

    // MARK: Layout constants

    private let labelWidth: CGFloat = 76
    private let rowHeight: CGFloat = 30

    private var safeWindow: Double {
        max(windowMillis, 1)
    }

    // MARK: Pieces

    private var emptyState: some View {
        Text("The timeline renders here after a run.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
    }

    private func deadlineRule(plotWidth: CGFloat) -> some View {
        let fraction = min(1, max(0, deadlineMillis / safeWindow))
        let x = labelWidth + 8 + plotWidth * CGFloat(fraction)
        return VStack(spacing: 2) {
            Text("deadline")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.red)
            Rectangle()
                .fill(.red.opacity(0.75))
                .frame(width: 1.5)
        }
        .frame(height: max(1, CGFloat(bars.count)) * rowHeight + 18)
        .position(x: x, y: (max(1, CGFloat(bars.count)) * rowHeight + 18) / 2)
    }

    private func rows(plotWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(bars) { bar in
                HStack(spacing: 8) {
                    Text(bar.label)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                        .frame(width: labelWidth, alignment: .leading)
                    singleBar(bar, plotWidth: plotWidth)
                }
                .frame(height: rowHeight)
            }
        }
        .padding(.top, 18)
    }

    private func singleBar(_ bar: LaneBar, plotWidth: CGFloat) -> some View {
        let startMillis = bar.report.startOffset.asMillis
        let endMillis = max(bar.report.endOffset.asMillis, startMillis + 12) // minimum visible width
        let startFraction = min(1, max(0, startMillis / safeWindow))
        let endFraction = min(1, max(startFraction, endMillis / safeWindow))
        let width = max(3, plotWidth * CGFloat(endFraction - startFraction))

        return ZStack(alignment: .leading) {
            Capsule()
                .fill(color(for: bar.report.outcome).opacity(0.85))
                .frame(width: width, height: 16)
                .offset(x: plotWidth * CGFloat(startFraction))
            Text(caption(for: bar.report))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .offset(x: plotWidth * CGFloat(startFraction) + width + 4, y: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendDot(.green, "success")
            legendDot(.orange, "failure")
            legendDot(.red, "deadline")
            legendDot(.gray, "cancelled")
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
        }
    }

    // MARK: Mapping

    private func color(for outcome: AttemptReport.Outcome) -> Color {
        switch outcome {
        case .success: return .green
        case .failure: return .orange
        case .deadlineExceeded: return .red
        case .cancelled: return .gray
        }
    }

    private func caption(for report: AttemptReport) -> String {
        let span = "\(Int(report.startOffset.asMillis))–\(Int(report.endOffset.asMillis))ms"
        switch report.outcome {
        case .success: return "✓ \(span)"
        case .failure(let message): return "✗ \(span) \(message)"
        case .deadlineExceeded: return "⏱ \(span) cut off"
        case .cancelled: return "∅ \(span) cancelled"
        }
    }
}
