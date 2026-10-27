import SwiftUI
import UIKit
import WidgetKit
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
    var shortLabel: String {
        switch self {
        case .real: "Real time"
        case .sunday: "Sunday"
        case .weekday: "Wednesday"
        }
    }
}

enum Route: Hashable {
    /// A dump, opened on a particular photo when one is given.
    case dump(ID, photo: ID? = nil)
    case profile(ID)
    /// Someone's followers or the people they follow, from the counts on their profile.
    case people(userID: ID, username: String, list: PeopleList)
}

enum PeopleList: Hashable {
    case followers, following
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
    private(set) var currentUser: User? {
        // A saved "Pretend it's Sunday" only counts for demo data or an admin.
        didSet {
            if !canChangeDay, debugDay != .real { setDebugDay(.real) }
            // Saved ideas belong to whoever saved them. Set on sign-in and on a restored session alike.
            if let id = currentUser?.id, id != oldValue?.id { savedIdeas.signedIn(userID: id) }
        }
    }
    private(set) var isRestoringSession = true
    /// Signed in, with onboarding's last steps (ideas near you, reminders, friends) still to go.
    /// RootView keeps onboarding up until they are done.
    private(set) var isFinishingOnboarding = false
    private(set) var pendingApprovalCount = 0
    /// The account's settings as the server last sent or accepted them. Nil until it has
    /// answered, so nothing is shown, saved or scheduled from a guess.
    private(set) var accountSettings: AccountSettings?
    private(set) var appearance: Appearance
    private(set) var debugDay: DebugDay
    /// Set by a view that wants the shell to switch tabs (the profile's "Post your week" card).
    var requestedTab: SundayTab?
    /// Goes up when the user removes a follower or follows or unfollows someone, so a profile
    /// already on screen shows the new counts.
    var followsChanged = 0

    let feed: FeedStore
    let compose: ComposeStore
    let approvals: ApprovalsStore
    let weekday: WeekdayStore
    let savedIdeas: SavedIdeasStore
    let localIdeas: LocalIdeasStore
    let network = NetworkMonitor()

    /// True when running against the in-memory mock instead of a server.
    var isUsingMock: Bool { mock != nil }
    /// An admin on the live server (docs/SERVER.md): the server opens Sunday to them any day.
    var isAdmin: Bool { currentUser?.isAdmin == true }
    /// The only times the day can be moved: demo data, or an admin testing the real server.
    var canChangeDay: Bool { isUsingMock || isAdmin }

    private var boundaryTask: Task<Void, Never>?
    /// Says when the server refused to renew the session (HTTPClient), and the watch on it.
    private let sessionEnded: AsyncStream<Void>
    private var sessionWatch: Task<Void, Never>?
    private var isSigningOut = false

    private enum Keys {
        static let appearance = "appearance"
        static let debugDay = "debugDay"
        static let session = "session.token"
        static let cachedUser = "session.user"
        /// The account whose onboarding is not finished yet, so a relaunch carries on with it.
        static let finishingOnboarding = "onboarding.finishingFor"
    }

    var isSunday: Bool { phase == .sunday }
    var isSignedIn: Bool { currentUser != nil }
    var currentWeekStart: Date { clock.weekStart() }

    init() {
        let defaults = UserDefaults.standard
        let appearance = Appearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        let debugDay = DebugDay(rawValue: defaults.string(forKey: Keys.debugDay) ?? "") ?? .real
        let clock = Self.makeClock(for: debugDay)
        let catalog = SuggestionCatalog.bundled()

        let api: any SundaeAPI
        let mock: MockSundaeAPI?
        let (sessionEnded, onSessionEnded) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        if let baseURL = APIConfiguration.baseURL {
            api = LiveSundaeAPI(client: HTTPClient(baseURL: baseURL, onSessionExpired: onSessionEnded))
            mock = nil
        } else {
            let m = MockSundaeAPI(clock: clock)
            api = m
            mock = m
        }

        self.appearance = appearance
        self.debugDay = debugDay
        self.clock = clock
        self.mock = mock
        self.api = api
        self.sessionEnded = sessionEnded
        self.suggestions = catalog
        self.feed = FeedStore(api: api)
        self.compose = ComposeStore(api: api)
        self.approvals = ApprovalsStore(api: api)
        let savedIdeas = SavedIdeasStore()
        let weekday = WeekdayStore(api: api, catalog: catalog, saved: savedIdeas)
        savedIdeas.onFirstPhoto = { [weak weekday] suggestion, day in
            Task { await weekday?.recordDone(suggestion, on: day) }
        }
        self.savedIdeas = savedIdeas
        self.weekday = weekday
        // Ideas near you come from Apple Maps on the phone in every build: the friends and family
        // server has no ideas service (docs/SERVER.md), and this keeps location off it entirely.
        self.localIdeas = LocalIdeasStore(api: api, onDevice: true)
    }

    // MARK: - Lifecycle

    func start() async {
        // Before the Keychain is read and before any await, so a second window can't race it.
        clearSessionLeftByAnEarlierInstall()
        refreshPhase()
        watchForEndedSession()
        network.onChange = { [weak self] online in
            guard online else { return }
            Task { await self?.networkReturned() }
        }
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-uiTestSignedOut") {
            Keychain.delete(Keys.session)
            cacheUser(nil)
        }
        if arguments.contains("-uiTestSignedIn") {
            UserDefaults.standard.removeObject(forKey: "sundayPrompt.dismissedWeekStart")
        }
        if arguments.contains("-uiTestSignedIn"), isUsingMock {
            try? await createAccount(ticket: "mock-signup-ticket", username: "jon", name: "Jon")
            finishOnboarding()
            isRestoringSession = false
            return
        }
        if let token = Keychain.string(for: Keys.session) {
            do {
                if let user = try await api.restoreSession(token: token) {
                    isFinishingOnboarding = UserDefaults.standard.string(forKey: Keys.finishingOnboarding) == user.id
                    currentUser = user
                    cacheUser(user)
                    await didSignIn()
                } else {
                    Keychain.delete(Keys.session)
                    cacheUser(nil)
                }
            } catch {
                // Offline at launch. Trust the cached identity until the server can be reached.
                if let cached = cachedUser() {
                    isFinishingOnboarding = UserDefaults.standard.string(forKey: Keys.finishingOnboarding) == cached.id
                    currentUser = cached
                }
            }
        }
        isRestoringSession = false
    }

    /// The Keychain outlives a deleted app. On a fresh install, tokens found there belong to
    /// whoever used this phone before, so they are cleared and never sent, not even to sign out.
    private func clearSessionLeftByAnEarlierInstall() {
        // Before first unlock UserDefaults can read as empty; check on a later launch instead.
        guard UIApplication.shared.isProtectedDataAvailable else { return }
        guard FreshInstall.check(.standard, evidence: [Keys.cachedUser, Keys.appearance]) else { return }
        TokenStore().clear()
        Keychain.delete(Keys.session)
    }

    /// When the network returns on Sunday, post anything compose queued while offline.
    private func networkReturned() async {
        guard isSignedIn else { return }
        // After an offline launch the settings the reminders follow are still to come.
        if accountSettings == nil, await loadAccountSettings() != nil { scheduleReminders() }
        if let dump = await compose.retryQueuedPost(currentWeekStart: currentWeekStart, isSunday: isSunday) {
            feed.insertOwn(dump)
            shared.postedWeekStart = dump.weekStart
            scheduleReminders()
        }
    }

    private func cacheUser(_ user: User?) {
        let defaults = UserDefaults.standard
        if let user, let data = try? JSONEncoder().encode(user) {
            defaults.set(data, forKey: Keys.cachedUser)
        } else {
            defaults.removeObject(forKey: Keys.cachedUser)
        }
    }

    private func cachedUser() -> User? {
        UserDefaults.standard.data(forKey: Keys.cachedUser).flatMap { try? JSONDecoder().decode(User.self, from: $0) }
    }

    /// Recomputes Sunday vs weekday and arms a wake-up at the next midnight boundary.
    func refreshPhase() {
        let next: DayPhase = clock.isSunday() ? .sunday : .weekday(daysUntilSunday: clock.daysUntilSunday())
        if next != phase { WidgetCenter.shared.reloadAllTimelines() }
        phase = next
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
        if isSignedIn, accountSettings == nil { await loadAccountSettings() }
        // A week posted early skips its last call; a new week brings the weekly one back.
        if isSignedIn { scheduleReminders() }
        // Photos taken at saved places since the last look, matched on the phone.
        if isSignedIn {
            savedIdeas.startWeek(currentWeekStart)
            await savedIdeas.findPhotos(clock: clock)
        }
        await refreshPendingCount()
    }

    /// Signs out here once the server has refused to renew this session (docs/API.md), whichever
    /// request found out. Started once, however many windows call `start()`.
    private func watchForEndedSession() {
        guard sessionWatch == nil else { return }
        let ended = sessionEnded
        sessionWatch = Task { [weak self] in
            for await _ in ended {
                await self?.sessionDidEnd()
            }
        }
    }

    private func sessionDidEnd() async {
        guard isSignedIn else { return }
        await signOut()
    }

    // MARK: - Session

    /// Someone coming back is signed in here, and nil comes back. `keepOnboarding` holds the
    /// remaining steps on screen for them. Someone new gets the ticket for `createAccount` instead.
    func signIn(_ method: SignInMethod, keepOnboarding: Bool) async throws -> String? {
        switch try await api.signIn(method) {
        case .signedIn(let session):
            await adopt(session, keepOnboarding: keepOnboarding)
            return nil
        case .newAccount(let ticket):
            return ticket
        }
    }

    /// The new account, with the username they chose. Onboarding stays up for its last steps.
    func createAccount(ticket: String, username: String, name: String?) async throws {
        let session = try await api.createAccount(ticket: ticket, username: username, name: name)
        await adopt(session, keepOnboarding: true)
    }

    func finishOnboarding() {
        isFinishingOnboarding = false
        UserDefaults.standard.removeObject(forKey: Keys.finishingOnboarding)
    }

    private func adopt(_ session: Session, keepOnboarding: Bool) async {
        // Before the user is set, so RootView never flashes the app on its way.
        isFinishingOnboarding = keepOnboarding
        if keepOnboarding {
            UserDefaults.standard.set(session.user.id, forKey: Keys.finishingOnboarding)
        } else {
            UserDefaults.standard.removeObject(forKey: Keys.finishingOnboarding)
        }
        Keychain.set(session.token, for: Keys.session)
        currentUser = session.user
        cacheUser(session.user)
        localIdeas.signedIn(userID: session.user.id)
        MomentMemory.signedIn(userID: session.user.id)
        await didSignIn()
    }

    private func didSignIn() async {
        // Nil when the server can't be reached: Settings asks again when it opens.
        accountSettings = try? await api.accountSettings()
        await refreshPendingCount()
        // Scheduling shows nothing until iOS has a yes. That question is asked only with its reason
        // on screen: in onboarding, or when a reminder is switched on in Settings.
        scheduleReminders()
    }

    func scheduleReminders() {
        // Until the server's settings are in, whatever iOS already has scheduled stays.
        guard let settings = accountSettings else { return }
        let posted = shared.postedWeekStart == currentWeekStart
        NotificationScheduler.scheduleSundayReminders(reminder: settings.notifySundayReminder,
                                                      lastCall: settings.notifyLastCall,
                                                      postedUntil: posted ? clock.weekEnd() : nil)
    }

    /// Signs every device out, this one last. False when the server could not be reached, in which
    /// case nothing changes, so nobody believes their other devices are out when they are not.
    func signOutEverywhere() async -> Bool {
        do {
            try await api.signOutEverywhere()
        } catch {
            return false
        }
        await signOut()
        return true
    }

    func signOut() async {
        // One at a time: an ended session can arrive while a sign-out is already on its way.
        guard !isSigningOut else { return }
        isSigningOut = true
        defer { isSigningOut = false }
        localIdeas.signedOut(userID: currentUser?.id)
        MomentMemory.signedOut(userID: currentUser?.id)
        savedIdeas.signedOut()
        NotificationScheduler.cancelAll()
        finishOnboarding()
        try? await api.signOut()
        Keychain.delete(Keys.session)
        cacheUser(nil)
        currentUser = nil
        accountSettings = nil
        compose.reset()
        feed.reset()
        approvals.reset()
    }

    /// Signs out only once the server has deleted the account. False when it couldn't, and then
    /// nothing changes here, so nobody believes their weeks are gone when they are not.
    func deleteAccount() async -> Bool {
        do {
            try await api.deleteAccount()
        } catch SundaeError.notAuthorized, SundaeError.sessionExpired {
            // The session is gone with the account: an earlier try got through and its reply was lost.
        } catch {
            return false
        }
        localIdeas.disable()
        await signOut()
        // Nothing of a deleted account waits on this phone for it to come back.
        MomentMemory.signedOut(userID: nil)
        savedIdeas.forgetAll()
        return true
    }

    func updateProfile(name: String, username: String, bio: String) async throws {
        let user = try await api.updateProfile(name: name, username: username, bio: bio)
        currentUser = user
        cacheUser(user)
        feed.replaceUser(user)
    }

    /// Re-encodes the picked image to a 600 px square on device, then sends only that.
    func updateAvatar(_ data: Data) async throws {
        guard let photo = await PhotoProcessor.processAvatarInBackground(data) else { throw SundaeError.invalidPhoto }
        let user = try await api.updateAvatar(photo)
        currentUser = user
        cacheUser(user)
        feed.replaceUser(user)
    }

    /// The account's settings, fresh from the server. Nil when it can't be reached.
    @discardableResult
    func loadAccountSettings() async -> AccountSettings? {
        guard let fresh = try? await api.accountSettings() else { return nil }
        accountSettings = fresh
        return fresh
    }

    /// Sends only the fields where `wanted` differs from `base`, the server's values as the caller
    /// last had them. The app's copy, and Public or Private on the profile, change only once the
    /// server has the change. False when it didn't get it.
    func saveAccountSettings(from base: AccountSettings, to wanted: AccountSettings) async -> Bool {
        let patch = AccountSettingsPatch(from: base, to: wanted)
        guard !patch.isEmpty else { return true }
        do {
            try await api.updateAccountSettings(patch)
        } catch {
            return false
        }
        accountSettings = patch.applied(to: accountSettings ?? wanted)
        if let isPublic = patch.isPublic, var user = currentUser {
            user.isPublic = isPublic
            currentUser = user
            cacheUser(user)
        }
        scheduleReminders()
        return true
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
        applyAppearance()
    }

    /// Light, dark or the system's, on every window and every sheet open in it, so Settings,
    /// where it is changed, changes at once with everything under it. A sheet is given its own look
    /// when it opens, which the window's does not reach, so each one is set too. Only on a change:
    /// at launch the root's preference is enough, and the intro film's light one is left alone.
    private func applyAppearance() {
        let style = appearance.interfaceStyle
        for scene in UIApplication.shared.connectedScenes {
            guard let scene = scene as? UIWindowScene else { continue }
            for window in scene.windows {
                window.overrideUserInterfaceStyle = style
                var controller = window.rootViewController
                while let shown = controller {
                    shown.overrideUserInterfaceStyle = style
                    controller = shown.presentedViewController
                }
            }
        }
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
