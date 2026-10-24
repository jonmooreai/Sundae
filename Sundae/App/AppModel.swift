import SwiftUI
import Observation

enum DayPhase: Equatable {
    case sunday
    case weekday(daysUntilSunday: Int)
}

/// Debug-only time travel so the Sunday screens can be worked on during the week.
enum DebugDay: String, CaseIterable, Identifiable {
    case real, sunday, weekday
    var id: String { rawValue }
    var label: String {
        switch self {
        case .real: "Real time"
        case .sunday: "Pretend it's Sunday"
        case .weekday: "Pretend it's Wednesday"
        }
    }
}

enum Route: Hashable {
    case dump(ID)
    case profile(ID)
}

@MainActor
@Observable
final class AppModel {
    let api: any SundaeAPI
    private let mock: MockSundaeAPI?
    private(set) var clock: SundayClock
    let suggestions: SuggestionCatalog
    let shared = SharedDefaults()

    private(set) var phase: DayPhase = .weekday(daysUntilSunday: 6)
    private(set) var currentUser: User?
    private(set) var isRestoringSession = true
    private(set) var pendingApprovalCount = 0
    private(set) var accountSettings = AccountSettings()
    private(set) var appearance: Appearance
    private(set) var debugDay: DebugDay

    let feed: FeedStore
    let compose: ComposeStore
    let approvals: ApprovalsStore
    let weekday: WeekdayStore

    private var boundaryTask: Task<Void, Never>?

    private enum Keys {
        static let appearance = "appearance"
        static let debugDay = "debugDay"
        static let session = "session.token"
    }

    var isSunday: Bool { phase == .sunday }
    var isSignedIn: Bool { currentUser != nil }
    var currentWeekStart: Date { clock.weekStart() }

    init() {
        let defaults = UserDefaults.standard
        let appearance = Appearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        let debugDay = DebugDay(rawValue: defaults.string(forKey: Keys.debugDay) ?? "") ?? .real
        let clock = Self.makeClock(for: debugDay)
        let mock = MockSundaeAPI(clock: clock)
        let catalog = SuggestionCatalog.bundled()

        self.appearance = appearance
        self.debugDay = debugDay
        self.clock = clock
        self.mock = mock
        self.api = mock
        self.suggestions = catalog
        self.feed = FeedStore(api: mock)
        self.compose = ComposeStore(api: mock)
        self.approvals = ApprovalsStore(api: mock)
        self.weekday = WeekdayStore(api: mock, catalog: catalog)
    }

    // MARK: - Lifecycle

    func start() async {
        refreshPhase()
        if let token = Keychain.string(for: Keys.session),
           let user = try? await api.restoreSession(token: token) {
            currentUser = user
            await didSignIn()
        }
        isRestoringSession = false
    }

    /// Recomputes Sunday vs weekday and arms a wake-up at the next midnight boundary.
    func refreshPhase() {
        phase = clock.isSunday() ? .sunday : .weekday(daysUntilSunday: clock.daysUntilSunday())
        boundaryTask?.cancel()
        let interval = max(1, clock.nextBoundary().timeIntervalSince(clock.now()))
        boundaryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            self?.refreshPhase()
        }
    }

    func becameActive() async {
        refreshPhase()
        await refreshPendingCount()
    }

    // MARK: - Session

    func signIn(_ method: SignInMethod, username: String?, name: String?) async throws {
        let session = try await api.signIn(method, username: username, name: name)
        Keychain.set(session.token, for: Keys.session)
        currentUser = session.user
        await didSignIn()
    }

    private func didSignIn() async {
        accountSettings = (try? await api.accountSettings()) ?? AccountSettings()
        await refreshPendingCount()
        await NotificationScheduler.requestAuthorizationIfNeeded()
        NotificationScheduler.scheduleSundayReminders(
            reminder: accountSettings.notifySundayReminder,
            lastCall: accountSettings.notifyLastCall
        )
    }

    func signOut() async {
        try? await api.signOut()
        Keychain.delete(Keys.session)
        currentUser = nil
        compose.reset()
        feed.reset()
        approvals.reset()
    }

    func deleteAccount() async {
        try? await api.deleteAccount()
        await signOut()
    }

    func updateProfile(name: String, username: String, bio: String) async throws {
        currentUser = try await api.updateProfile(name: name, username: username, bio: bio)
    }

    func saveAccountSettings(_ settings: AccountSettings) async {
        accountSettings = settings
        try? await api.updateAccountSettings(settings)
        if var user = currentUser {
            user.isPublic = settings.isPublic
            currentUser = user
        }
        NotificationScheduler.scheduleSundayReminders(reminder: settings.notifySundayReminder, lastCall: settings.notifyLastCall)
    }

    func refreshPendingCount() async {
        guard isSignedIn else { return }
        let count = (try? await api.pendingTagRequests())?.count ?? 0
        pendingApprovalCount = count
        shared.pendingApprovalCount = count
    }

    // MARK: - Preferences

    func setAppearance(_ value: Appearance) {
        appearance = value
        UserDefaults.standard.set(value.rawValue, forKey: Keys.appearance)
    }

    func setDebugDay(_ value: DebugDay) {
        debugDay = value
        UserDefaults.standard.set(value.rawValue, forKey: Keys.debugDay)
        clock = Self.makeClock(for: value)
        let clock = clock
        Task {
            await mock?.setClock(clock)
            refreshPhase()
            compose.reset()
            feed.reset()
            approvals.reset()
            await refreshPendingCount()
        }
    }

    /// Real time, or real time shifted so that "now" lands on this week's Sunday at noon
    /// (or the following Wednesday at noon). Only the offset moves, so the clock keeps ticking.
    nonisolated private static func makeClock(for debug: DebugDay) -> SundayClock {
        let real = SundayClock()
        switch debug {
        case .real:
            return real
        case .sunday:
            if real.isSunday() { return real }
            let target = real.sundayStart(forWeekContaining: nil).addingTimeInterval(12 * 3600)
            let offset = target.timeIntervalSince(real.now())
            return SundayClock(now: { Date().addingTimeInterval(offset) })
        case .weekday:
            if !real.isSunday() { return real }
            let target = real.weekEnd(containing: nil).addingTimeInterval((2 * 24 + 12) * 3600)
            let offset = target.timeIntervalSince(real.now())
            return SundayClock(now: { Date().addingTimeInterval(offset) })
        }
    }
}
