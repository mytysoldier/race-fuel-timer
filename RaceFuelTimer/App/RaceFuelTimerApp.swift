import SwiftUI

@main
struct RaceFuelTimerApp: App {
    @State private var session: Session?

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                // Optional の Session を、画面が更新できる Binding<Session> として安全に取り出す。
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
