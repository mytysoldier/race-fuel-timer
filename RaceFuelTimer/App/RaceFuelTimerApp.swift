import SwiftUI

@main
struct RaceFuelTimerApp: App {
    @State private var session: Session?

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                // switch でも分岐できるが、Optional の Binding<Session> を安全に取り出す目的が明確な if let を使う。
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
