import SwiftUI

@main
struct RaceFuelTimerApp: App {
    @State private var session: Session?

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                if let sessionBinding = Binding($session) {
                    SessionTimerView(session: sessionBinding) {
                        session = nil
                    }
                } else {
                    ContentView { plan in
                        session = try? Session(plan: plan)
                    }
                }
            }
        }
    }
}
