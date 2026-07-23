import SwiftUI
import DeadlineBudgetKit

/// Deadline Playground — a visual, interactive consumer of DeadlineBudgetKit.
///
/// This target deliberately lives in its own repository and consumes the
/// library as a *remote* Swift Package dependency (branch `main`), proving
/// the package resolves and builds the way any external consumer would get
/// it — not via a local path reference that can hide packaging mistakes.
@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
