import SwiftUI
import DeadlineBudgetKit

/// The three systems behaviors the playground demonstrates.
enum Scenario: String, CaseIterable, Identifiable {
    case retry = "Budgeted Retry"
    case hedge = "Hedged Request"
    case gate = "Admission Gate"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .retry:
            return "Backoff draws from one shared deadline budget — the loop refuses to sleep into a dead end."
        case .hedge:
            return "A backup lane launches at the hedge delay; first success wins, the loser is cancelled."
        case .gate:
            return "Bounded concurrency + bounded queue; doomed work is rejected at the door or shed at dequeue."
        }
    }
}

/// One rendered row in the waterfall.
struct LaneBar: Identifiable, Equatable {
    let id: Int
    let label: String
    let report: AttemptReport
}

/// Simulated backend error.
struct SimulatedOutageError: Error, CustomStringConvertible {
    var description: String { "simulated 5xx" }
}

@MainActor
@Observable
final class SimulationEngine {
    var scenario: Scenario = .retry
    var deadlineMillis: Double = 1_200
    var latencyMillis: Double = 420
    var failureRate: Double = 0.45
    var hedgeDelayMillis: Double = 350

    private(set) var isRunning = false
    private(set) var bars: [LaneBar] = []
    private(set) var outcomeLine = "Press Run to execute a scenario against a live deadline."
    private(set) var outcomeIsSuccess: Bool?
    private(set) var gateSummary: String?
    private(set) var runCount = 0

    private let clock = ContinuousTimeSource()

    /// Window (ms) the waterfall renders; deadline sits at ~80% of it.
    var windowMillis: Double {
        max(deadlineMillis * 1.25, 200)
    }

    func run() {
        guard !isRunning else { return }
        isRunning = true
        bars = []
        gateSummary = nil
        outcomeIsSuccess = nil
        outcomeLine = "Running…"
        let selected = scenario
        Task {
            switch selected {
            case .retry: await runRetryScenario()
            case .hedge: await runHedgeScenario()
            case .gate: await runGateScenario()
            }
            runCount += 1
            isRunning = false
        }
    }

    // MARK: Scenarios

    private func runRetryScenario() async {
        let deadline = Deadline.after(.milliseconds(deadlineMillis), source: clock)
        let origin = clock.now()
        let latency = latencyMillis
        let failures = failureRate
        let configuration = RetryConfiguration(
            maxAttempts: 4,
            minimumAttemptBudget: .milliseconds(60),
            baseBackoff: .milliseconds(130),
            backoffMultiplier: 2,
            maxBackoff: .seconds(1),
            jitter: .full
        )
        do {
            let result = try await executeWithRetry(
                configuration: configuration,
                deadline: deadline,
                source: clock
            ) { [clock] _ in
                try await Self.simulatedCall(
                    clock: clock, latencyMillis: latency, failureRate: failures
                )
            }
            bars = Self.rebase(result.attempts, to: origin, prefix: "Attempt")
            setOutcome(success: true, "Succeeded on attempt \(result.attempts.count) of \(configuration.maxAttempts) — inside the deadline.")
        } catch let error as RetryExhaustedError {
            bars = Self.rebase(error.attempts, to: origin, prefix: "Attempt")
            switch error.reason {
            case .budgetExhausted(let remaining):
                setOutcome(success: false, "Stopped early: remaining budget (\(Self.millis(remaining)) ms) can't fund backoff + another attempt. No doomed work launched.")
            case .deadlineExceeded:
                setOutcome(success: false, "Deadline fired mid-attempt — the in-flight try was cancelled at the line.")
            case .maxAttemptsReached:
                setOutcome(success: false, "All \(error.attempts.count) attempts failed inside the budget.")
            }
        } catch {
            setOutcome(success: false, "Unexpected: \(error)")
        }
    }

    private func runHedgeScenario() async {
        let deadline = Deadline.after(.milliseconds(deadlineMillis), source: clock)
        let origin = clock.now()
        let latency = latencyMillis
        let failures = min(failureRate, 0.25) // hedging demo focuses on latency, not outages
        let configuration = HedgeConfiguration(
            hedgeDelay: .milliseconds(hedgeDelayMillis),
            maxHedges: 2,
            minimumHedgeBudget: .milliseconds(80),
            hedgeOnFailure: true
        )
        do {
            let result = try await executeHedged(
                configuration: configuration,
                deadline: deadline,
                source: clock
            ) { [clock] lane in
                // Lane 0 simulates a slow primary replica; backups draw a
                // fresh (usually luckier) latency sample.
                let laneLatency = lane == 0 ? latency : latency * Double.random(in: 0.25...0.6)
                return try await Self.simulatedCall(
                    clock: clock, latencyMillis: laneLatency, failureRate: failures
                )
            }
            bars = Self.rebase(result.attempts, to: origin, prefix: "Lane")
            setOutcome(success: true, "Lane \(result.winnerIndex) won the race; \(max(0, result.attempts.count - 1)) loser(s) cancelled — tail latency clipped.")
        } catch let error as HedgeExhaustedError {
            bars = Self.rebase(error.attempts, to: origin, prefix: "Lane")
            setOutcome(success: false, "Every launched lane failed (\(error.attempts.count) total); budget gate blocked further hedges.")
        } catch let error as DeadlineExceededError {
            setOutcome(success: false, "\(error) — no lane finished in time.")
        } catch {
            setOutcome(success: false, "Unexpected: \(error)")
        }
    }

    private func runGateScenario() async {
        let requestCount = 9
        let deadline = Deadline.after(.milliseconds(deadlineMillis), source: clock)
        let origin = clock.now()
        let gate: DeadlineAwareAdmissionGate
        do {
            gate = try DeadlineAwareAdmissionGate(
                configuration: .init(maxConcurrent: 3, maxQueueDepth: 3, safetyFactor: 1.0),
                source: clock
            )
        } catch {
            setOutcome(success: false, "Gate configuration rejected: \(error)")
            return
        }

        let clock = self.clock
        let latencyCeiling = max(latencyMillis, 150)
        var collected: [LaneBar] = []

        await withTaskGroup(of: LaneBar.self) { group in
            for index in 0..<requestCount {
                let cost = Double.random(in: latencyCeiling * 0.4...latencyCeiling * 1.3)
                group.addTask {
                    let start = clock.now() - origin
                    do {
                        _ = try await gate.run(
                            estimatedCost: .milliseconds(cost),
                            deadline: deadline
                        ) {
                            try await Self.simulatedCall(
                                clock: clock, latencyMillis: cost, failureRate: 0
                            )
                        }
                        return LaneBar(
                            id: index,
                            label: "Req \(index)",
                            report: AttemptReport(
                                index: index,
                                startOffset: start,
                                endOffset: clock.now() - origin,
                                outcome: .success
                            )
                        )
                    } catch let error as AdmissionRejectedError {
                        return LaneBar(
                            id: index,
                            label: "Req \(index)",
                            report: AttemptReport(
                                index: index,
                                startOffset: start,
                                endOffset: clock.now() - origin,
                                outcome: .failure(Self.shortReason(error.reason))
                            )
                        )
                    } catch {
                        return LaneBar(
                            id: index,
                            label: "Req \(index)",
                            report: AttemptReport(
                                index: index,
                                startOffset: start,
                                endOffset: clock.now() - origin,
                                outcome: .failure("\(error)")
                            )
                        )
                    }
                }
            }
            for await bar in group {
                collected.append(bar)
            }
        }

        bars = collected.sorted { $0.id < $1.id }
        let stats = await gate.statistics()
        let served = stats.admittedImmediately + stats.admittedAfterWait
        gateSummary = "Admitted \(served) (\(stats.admittedAfterWait) after queueing) · shed \(stats.shedExpiredInQueue) expired · rejected \(stats.rejectedInsufficientBudget) no-budget + \(stats.rejectedQueueFull) queue-full · peak queue \(stats.peakQueueDepth)"
        setOutcome(
            success: stats.completed > 0,
            "\(requestCount) bursty requests → \(stats.completed) served; doomed work was refused instead of executed."
        )
    }

    // MARK: Helpers

    private func setOutcome(success: Bool, _ line: String) {
        outcomeIsSuccess = success
        outcomeLine = line
    }

    /// Simulated backend call with jittered latency and a failure dice-roll.
    private nonisolated static func simulatedCall(
        clock: ContinuousTimeSource,
        latencyMillis: Double,
        failureRate: Double
    ) async throws -> String {
        let jittered = max(20, latencyMillis * Double.random(in: 0.7...1.3))
        try await clock.sleep(until: clock.now() + .milliseconds(jittered))
        if Double.random(in: 0..<1) < failureRate {
            throw SimulatedOutageError()
        }
        return "payload"
    }

    /// Rebases executor-recorded absolute offsets onto this run's origin.
    private nonisolated static func rebase(
        _ reports: [AttemptReport], to origin: Duration, prefix: String
    ) -> [LaneBar] {
        reports.enumerated().map { position, report in
            LaneBar(
                id: position,
                label: "\(prefix) \(report.index)",
                report: AttemptReport(
                    index: report.index,
                    startOffset: max(.zero, report.startOffset - origin),
                    endOffset: max(.zero, report.endOffset - origin),
                    outcome: report.outcome
                )
            )
        }
    }

    private nonisolated static func shortReason(_ reason: AdmissionRejectionReason) -> String {
        switch reason {
        case .insufficientBudget: return "rejected: budget"
        case .queueFull: return "rejected: queue full"
        case .expiredWhileQueued: return "shed: expired in queue"
        }
    }

    private nonisolated static func millis(_ duration: Duration) -> Int {
        Int(duration.asMillis)
    }
}

extension Duration {
    /// Fractional milliseconds — rendering helper for the demo UI.
    var asMillis: Double {
        let parts = components
        return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
    }
}
