# Deadline Playground — DeadlineBudgetKit demo app

**Watch a deadline get enforced.** This SwiftUI app races real (simulated-latency) operations against a live deadline and draws the result as a waterfall timeline: retries backing off inside a shrinking budget, a hedge lane launching at p95 and stealing the win, an admission gate refusing work that could never finish. Every bar comes straight from the library's `AttemptReport` values — the same ones its test suite asserts on to the millisecond.

It consumes [`deadline-budget-kit`](https://github.com/rajatslakhina/deadline-budget-kit) as a **remote Swift Package dependency** (branch `main`) — deliberately not a local path reference, so this repo proves the library resolves and builds the way any external consumer would actually get it.

## Why this matters

Timeout handling is invisible until it fails, and then it fails as a 28-second spinner. The three scenarios here make the failure modes — and their fixes — visible:

- **Budgeted Retry** — backoff draws from one shared deadline budget. When `backoff + minimumAttemptBudget` no longer fits, the loop stops *before* sleeping. You can watch it refuse to launch a doomed attempt.
- **Hedged Request** — a backup lane launches after the hedge delay (or immediately on failure), first success wins, the loser is visibly cancelled mid-bar. Dean & Barroso's tail-at-scale trick, on a phone.
- **Admission Gate** — nine bursty requests hit a `maxConcurrent: 3` gate with a bounded queue. Some run, some queue, and the ones whose deadlines died while queueing are shed instead of executed. The scoreboard shows admitted / shed / rejected counts live.

## How to run it

1. Open `Demo.xcodeproj` in Xcode (15+, iOS 17 SDK).
2. Xcode resolves the remote `deadline-budget-kit` package from GitHub automatically (first open needs network).
3. Select the `Demo` scheme, pick any iOS 17+ Simulator, **Build & Run**.
4. Pick a scenario, drag the deadline/latency sliders, press **Run under deadline**, and read the waterfall.

Suggested first experiment: in *Budgeted Retry*, set latency ≈ 500 ms and the deadline to 800 ms, then to 3000 ms — watch the loop change its mind about how many attempts it can afford.

## Honest verification status

This repo comes out of an automated, unattended pipeline run, and its verification ceiling is disclosed rather than rounded up:

- **Not yet run on a Simulator.** The pipeline's screen-automation permission cannot be granted during an unattended scheduled run on this machine, so no live launch happened and **no screenshots exist yet** — none are faked above. The first human `⌘R` is genuinely the first launch.
- What *was* verified headlessly (Linux, Swift 6.0.3): the library dependency builds clean and passes **58/58 tests**; and a scratch consumer package depending on `https://github.com/rajatslakhina/deadline-budget-kit.git` (branch `main`) — the exact reference in this project's `project.pbxproj` — **resolved and built successfully**, which is the same resolution Xcode performs on first open.
- The app sources were reviewed against the pipeline's crash-class checklist (no force-unwraps, no unchecked indexing, empty-state guards in every collection view) and `project.pbxproj` passed a scripted brace/paren balance check plus XML validation of the shared scheme.

## The library underneath

[`deadline-budget-kit`](https://github.com/rajatslakhina/deadline-budget-kit) — absolute deadlines with tightening-only task-local propagation, exact budget splitting, budget-drawn retries, hedged execution, deadline-aware admission control, and the `VirtualTimeSource` that makes all of it deterministically testable. The README there documents the design decisions and the alternatives that lost.

## License

MIT
