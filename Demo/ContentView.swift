import SwiftUI
import DeadlineBudgetKit

struct ContentView: View {
    @State private var engine = SimulationEngine()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    scenarioPicker
                    controls
                    runButton
                    outcome
                    WaterfallView(
                        bars: engine.bars,
                        deadlineMillis: engine.deadlineMillis,
                        windowMillis: engine.windowMillis
                    )
                    .padding(.top, 4)
                    if let gateSummary = engine.gateSummary {
                        Text(gateSummary)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    footer
                }
                .padding()
            }
            .navigationTitle("Deadline Playground")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var scenarioPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Scenario", selection: Binding(
                get: { engine.scenario },
                set: { engine.scenario = $0 }
            )) {
                ForEach(Scenario.allCases) { scenario in
                    Text(scenario.rawValue).tag(scenario)
                }
            }
            .pickerStyle(.segmented)

            Text(engine.scenario.subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            slider(
                "Deadline",
                value: Binding(get: { engine.deadlineMillis }, set: { engine.deadlineMillis = $0 }),
                range: 300...3_000,
                unit: "ms"
            )
            slider(
                "Simulated latency",
                value: Binding(get: { engine.latencyMillis }, set: { engine.latencyMillis = $0 }),
                range: 60...1_500,
                unit: "ms"
            )
            if engine.scenario == .retry {
                slider(
                    "Failure rate",
                    value: Binding(get: { engine.failureRate }, set: { engine.failureRate = $0 }),
                    range: 0...0.95,
                    unit: "",
                    format: { String(format: "%.0f%%", $0 * 100) }
                )
            }
            if engine.scenario == .hedge {
                slider(
                    "Hedge delay",
                    value: Binding(get: { engine.hedgeDelayMillis }, set: { engine.hedgeDelayMillis = $0 }),
                    range: 50...1_200,
                    unit: "ms"
                )
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    private func slider(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        unit: String,
        format: ((Double) -> String)? = nil
    ) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(label).font(.caption.weight(.medium))
                Spacer()
                Text(format.map { $0(value.wrappedValue) } ?? "\(Int(value.wrappedValue)) \(unit)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private var runButton: some View {
        Button {
            engine.run()
        } label: {
            HStack {
                if engine.isRunning {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "play.fill")
                }
                Text(engine.isRunning ? "Racing the deadline…" : "Run under deadline")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .disabled(engine.isRunning)
    }

    private var outcome: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
            Text(engine.outcomeLine)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    private var iconName: String {
        switch engine.outcomeIsSuccess {
        case .some(true): return "checkmark.circle.fill"
        case .some(false): return "exclamationmark.triangle.fill"
        case .none: return "timer"
        }
    }

    private var iconColor: Color {
        switch engine.outcomeIsSuccess {
        case .some(true): return .green
        case .some(false): return .orange
        case .none: return .secondary
        }
    }

    private var footer: some View {
        Text("Powered by DeadlineBudgetKit — absolute deadlines, budget-drawn retries, hedged requests, and deadline-aware admission control. Runs so far: \(engine.runCount)")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }
}

#Preview {
    ContentView()
}
