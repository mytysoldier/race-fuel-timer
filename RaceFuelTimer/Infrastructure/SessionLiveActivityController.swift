import ActivityKit
import Combine
import Foundation

@MainActor
protocol SessionActivityClient {
    var isEnabled: Bool { get }
    func start(_ snapshot: SessionActivitySnapshot) throws
    func update(_ content: RunActivityAttributes.ContentState) async -> Bool
    func endAll() async
}

@MainActor
private final class SystemSessionActivityClient: SessionActivityClient {
    private var activity: Activity<RunActivityAttributes>?
    var isEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func start(_ snapshot: SessionActivitySnapshot) throws {
        activity = try Activity.request(
            attributes: RunActivityAttributes(sessionStartedAt: snapshot.sessionStartedAt),
            content: ActivityContent(state: snapshot.content, staleDate: snapshot.content.staleDate),
            pushType: nil
        )
    }

    func update(_ content: RunActivityAttributes.ContentState) async -> Bool {
        guard let activity,
              activity.activityState == .active || activity.activityState == .stale else { return false }
        await activity.update(ActivityContent(state: content, staleDate: content.staleDate))
        return activity.activityState == .active || activity.activityState == .stale
    }

    func endAll() async {
        for existing in Activity<RunActivityAttributes>.activities {
            await existing.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
    }
}

@MainActor
final class SessionLiveActivityController: ObservableObject {
    enum Status { case notStarted, active, unavailable }
    @Published private(set) var status: Status = .notStarted

    private let client: any SessionActivityClient
    private var desired: SessionActivitySnapshot?
    private var hasRequested = false
    private var didReset = false
    private var attemptedSession: Date?
    private var revision = 0
    private var worker: Task<Void, Never>?

    init(client: (any SessionActivityClient)? = nil) {
        self.client = client ?? SystemSessionActivityClient()
    }

    func synchronize(session: Session?, at date: Date = .now, force: Bool = false) {
        let snapshot = session.flatMap { SessionActivitySnapshot(session: $0, at: date) }
        guard force || !hasRequested || snapshot != desired else { return }
        hasRequested = true
        desired = snapshot
        revision += 1
        let requestedRevision = revision
        let previous = worker
        // OSへの更新と終了を直列化し、終了後に古い更新が完了する競合を防ぐ。
        worker = Task { [weak self] in
            await previous?.value
            guard let self, requestedRevision == self.revision else { return }
            await self.apply(snapshot, revision: requestedRevision)
        }
    }

    func waitForUpdates() async {
        while let worker {
            let current = revision
            await worker.value
            if current == revision { return }
        }
    }

    private func apply(_ snapshot: SessionActivitySnapshot?, revision requestedRevision: Int) async {
        if !didReset {
            // セッションは非永続のため、前回プロセスの表示を引き継がない。
            await client.endAll()
            didReset = true
        }
        guard requestedRevision == revision else { return }
        guard let snapshot else {
            await client.endAll()
            attemptedSession = nil
            if requestedRevision == revision { status = .notStarted }
            return
        }
        guard client.isEnabled else {
            await client.endAll()
            attemptedSession = snapshot.sessionStartedAt
            if requestedRevision == revision { status = .unavailable }
            return
        }
        if attemptedSession != snapshot.sessionStartedAt {
            await client.endAll()
            guard requestedRevision == revision else { return }
            attemptedSession = snapshot.sessionStartedAt
            do {
                try client.start(snapshot)
                status = .active
            } catch {
                status = .unavailable
            }
        } else {
            // OSの時間制限や手動削除後、同じランの表示を勝手に作り直さない。
            let updated = await client.update(snapshot.content)
            if requestedRevision == revision { status = updated ? .active : .unavailable }
        }
    }
}
