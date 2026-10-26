import LocalAuthentication
import SwiftUI
import UIKit
import UserNotifications
import PhosphorSwift

/// Account, privacy, weekday ideas, tags, notifications, data. Open every day.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    /// What the account's switches show and the person changes.
    @State private var settings = AccountSettings()
    /// The server's values as this screen last loaded or saved them. Nil until it has answered,
    /// and until then the account's switches stay hidden, so they never show a guess.
    @State private var saved: AccountSettings?
    @State private var loadFailed = false
    @State private var saving = false
    @State private var saveFailed = false
    /// True while the auto-approve list is on screen, which then shows a failed save itself.
    @State private var showingAutoApprove = false
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var deleteFailed = false
    @State private var confirmSignOut = false
    @State private var signOutFailed = false
    @State private var showLocationConsent = false
    /// What iOS says about notifications for Sundae. Read when Settings opens and on coming back.
    @State private var notificationStatus: UNAuthorizationStatus = .authorized

    var body: some View {
        SettingsScreen(title: "Settings") {
            SettingsGroup(title: "Appearance", card: false) {
                SegmentedChoice(options: Appearance.allCases.map { ($0, $0.shortLabel) },
                                selection: Binding(get: { model.appearance }, set: { model.setAppearance($0) }))
            }

            SettingsGroup(title: "Account", footer: saved == nil && loadFailed ? "Couldn't load your settings. Check your connection." : nil) {
                if saved != nil {
                    RadioRow(title: "Private", detail: "New followers need your approval. Remove anyone under Followers.",
                             isSelected: !settings.isPublic) {
                        settings.isPublic = false
                    }
                    RadioRow(title: "Public", detail: "Anyone can follow you.", isSelected: settings.isPublic) {
                        settings.isPublic = true
                    }
                } else if loadFailed {
                    SettingsActionRow(title: "Try again") { Task { await load() } }
                } else {
                    LoadingRow(title: "Loading your settings")
                }
                // Not tied to the settings above, so it opens even while they load.
                SettingsLinkRow(title: "Followers") { FollowersList() }
            }

            SettingsGroup(title: "Weekdays") {
                SettingsToggle(title: "Ideas near me", detail: "From your neighborhood. Never on Sunday.",
                               isOn: Binding(get: { model.localIdeas.isEnabled },
                                             set: { on in
                                                 if on { showLocationConsent = true } else { model.localIdeas.disable() }
                                             }))
                if model.localIdeas.isEnabled, model.localIdeas.isDenied {
                    SettingsActionRow(title: "Turn on Location in iOS Settings") { openSystemSettings() }
                }
                SettingsLinkRow(title: "Home Screen widgets") { WidgetGalleryView() }
            }

            if saved != nil {
                SettingsGroup(title: "Tags and comments") {
                    SettingsLinkRow(title: "Auto-approve tags",
                                    value: settings.autoApproveUserIDs.isEmpty ? "Nobody" : "\(settings.autoApproveUserIDs.count)") {
                        AutoApproveList(settings: $settings, isShowing: $showingAutoApprove, saveFailed: $saveFailed)
                    }
                    SettingsToggle(title: "Comments on my weeks", isOn: $settings.commentsEnabled)
                }

                SettingsGroup(title: "Notifications", footer: model.isUsingMock ? nil : "Sundae sends only these two, both on Sunday.") {
                    SettingsToggle(title: "Sunday reminder", detail: "9:00 am", isOn: $settings.notifySundayReminder)
                    SettingsToggle(title: "Last call", detail: "8:00 pm, if you haven't posted", isOn: $settings.notifyLastCall)
                    // A switch that is on but can't deliver says how to fix it.
                    if settings.notifySundayReminder || settings.notifyLastCall {
                        if notificationStatus == .notDetermined {
                            SettingsActionRow(title: "Allow notifications") { Task { await allowNotifications() } }
                        } else if notificationStatus == .denied {
                            SettingsActionRow(title: "Turn on Notifications in iOS Settings") { openSystemSettings() }
                        }
                    }
                    // These need push notifications, which the friends and family server does not send
                    // yet. Shown with demo data only, so no switch here promises something that never comes.
                    if model.isUsingMock {
                        SettingsToggle(title: "Tags", isOn: $settings.notifyTags)
                        SettingsToggle(title: "Follow requests", isOn: $settings.notifyFollowRequests)
                        SettingsToggle(title: "Likes and comments", detail: "Sundays only", isOn: $settings.notifyLikesAndComments)
                        SettingsToggle(title: "Approved tags", isOn: $settings.notifyTagApproved)
                    }
                }
            }

            SettingsGroup(title: "Devices") {
                SettingsValueRow(title: "This device", value: UIDevice.current.name)
                SettingsActionRow(title: "Sign out everywhere", isDestructive: true) { confirmSignOut = true }
            }

            SettingsGroup(title: "Your data", footer: "Deleting removes everything right away.") {
                SettingsLinkRow(title: "Privacy") { PrivacyView() }
                SettingsActionRow(title: "Export my data", value: "Soon") { }
                    .disabled(true)
                SettingsActionRow(title: "Delete account", isDestructive: true) {
                    Task { if await freshAuthentication() { confirmDelete = true } }
                }
                .disabled(deleting)
            }

            if model.canChangeDay {
                SettingsGroup(title: model.isUsingMock ? "Demo" : "Admin",
                              footer: model.isUsingMock
                                ? "Built-in demo data. Move the clock to see Sunday any day."
                                : "Only you see this. Sunday opens for you any day; everyone else waits for Sunday.") {
                    SegmentedChoice(options: DebugDay.allCases.map { ($0, $0.shortLabel) },
                                    selection: Binding(get: { model.debugDay }, set: { model.setDebugDay($0) }))
                        .padding(10)
                    SettingsToggle(title: "Always open on the post screen",
                                   isOn: Binding(get: { model.compose.alwaysShowPrompt }, set: { model.compose.alwaysShowPrompt = $0 }))
                }
            }

            SettingsGroup {
                SettingsActionRow(title: "Sign out") { Task { await model.signOut() } }
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.textButtonTint() }
        }
        .task {
            // Fresh from the server each time Settings opens, never a copy from earlier.
            if saved == nil { await load() }
            notificationStatus = await NotificationScheduler.authorizationStatus()
        }
        .onChange(of: settings) { old, new in
            // Loading, or a failed save going back: nothing to send or ask.
            guard let base = saved, new != base else { return }
            Task { await save() }
            // Switching a reminder on is the moment to ask iOS, if it has never been asked.
            let switchedOn = (new.notifySundayReminder && !old.notifySundayReminder) || (new.notifyLastCall && !old.notifyLastCall)
            if switchedOn, notificationStatus == .notDetermined { Task { await allowNotifications() } }
        }
        .onChange(of: model.accountSettings) { _, fresh in
            // Saved in another window, or loaded again: shown here too.
            if let fresh { adopt(fresh) }
        }
        .onChange(of: scenePhase) { _, phase in
            // Back from iOS Settings, maybe with notifications turned on or a connection again.
            guard phase == .active else { return }
            Task { notificationStatus = await NotificationScheduler.authorizationStatus() }
            if loadFailed { Task { await load() } }
        }
        .sheet(isPresented: $showLocationConsent) {
            LocationConsentSheet { model.localIdeas.enable() }
        }
        .confirmationDialog("Sign out of every device?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out everywhere", role: .destructive) {
                Task { if !(await model.signOutEverywhere()) { signOutFailed = true } }
            }
        } message: {
            Text("Other devices are signed out within 15 minutes.")
        }
        .alert("Couldn't reach Sundae", isPresented: $signOutFailed) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Nothing was signed out. Try again when you're online.")
        }
        .saveFailedAlert(isPresented: Binding(get: { saveFailed && !showingAutoApprove }, set: { saveFailed = $0 }))
        .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await deleteAccount() } }
        } message: {
            Text("Your dumps, comments and tags are removed right away. Photos you were tagged in stay in the poster's dump with the tag removed.")
        }
        .alert("Couldn't finish deleting your account", isPresented: $deleteFailed) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Try again when you're online.")
        }
    }

    /// Asks the server for the account's settings. Until it answers, the switches stay hidden.
    private func load() async {
        loadFailed = false
        if let fresh = await model.loadAccountSettings() {
            adopt(fresh)
        } else if saved == nil {
            loadFailed = true
        }
    }

    /// Shows the server's values, unless a change made here is still on its way.
    private func adopt(_ fresh: AccountSettings) {
        guard !saving, saved == nil || settings == saved else { return }
        saved = fresh
        settings = fresh
        loadFailed = false
    }

    /// One save at a time. A change made while one is on its way goes next, so the newest wins.
    /// When a save fails, the switches go back to what the server has.
    private func save() async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        while let base = saved, settings != base {
            let wanted = settings
            guard await model.saveAccountSettings(from: base, to: wanted) else {
                settings = base
                saveFailed = true
                return
            }
            saved = wanted
        }
    }

    /// Signs out only once the server has deleted the account; otherwise says so and stays.
    private func deleteAccount() async {
        guard !deleting else { return }
        deleting = true
        defer { deleting = false }
        if !(await model.deleteAccount()) { deleteFailed = true }
    }

    private func allowNotifications() async {
        await NotificationScheduler.requestAuthorizationIfNeeded()
        notificationStatus = await NotificationScheduler.authorizationStatus()
        model.scheduleReminders()
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }

    /// Sensitive actions need fresh authentication. Face ID or Touch ID when available, passcode otherwise.
    private func freshAuthentication() async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return true }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Confirm it's you before deleting your account.")) ?? false
    }
}

struct AutoApproveList: View {
    @Environment(AppModel.self) private var model
    @Binding var settings: AccountSettings
    /// True while this list is on screen, so a failed save is shown here.
    @Binding var isShowing: Bool
    @Binding var saveFailed: Bool
    /// The people who can tag you. Nil until they load, or when they couldn't.
    @State private var people: [User]?
    @State private var loadFailed = false

    var body: some View {
        SettingsScreen(title: "Auto-approve") {
            if let people {
                // Only after a good load: a failed one would make everyone look gone.
                let gone = settings.autoApprovedIDs(notIn: people)
                if !gone.isEmpty {
                    SettingsGroup(footer: "If one of you follows the other again, their tags would land without waiting.") {
                        SettingsActionRow(title: gone.count == 1 ? "1 person you no longer follow" : "\(gone.count) people you no longer follow",
                                          value: "Remove") {
                            withAnimation(.snappy(duration: 0.2)) {
                                settings.autoApproveUserIDs.removeAll { gone.contains($0) }
                            }
                            Haptics.light()
                        }
                    }
                }
                if people.isEmpty {
                    note("Follow some friends first.")
                } else {
                    SettingsGroup(footer: "Their tags land on your week without waiting.") {
                        ForEach(people) { user in
                            let isOn = settings.autoApproveUserIDs.contains(user.id)
                            Button {
                                withAnimation(.snappy(duration: 0.2)) {
                                    if isOn {
                                        settings.autoApproveUserIDs.removeAll { $0 == user.id }
                                    } else {
                                        settings.autoApproveUserIDs.append(user.id)
                                    }
                                }
                                Haptics.light()
                            } label: {
                                HStack(spacing: 12) {
                                    AvatarView(user: user, size: 40)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(user.displayName).font(.body).lineLimit(1)
                                        Text("@\(user.username)").font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer(minLength: 8)
                                    CheckMark(isOn: isOn)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(isOn ? .isSelected : [])
                        }
                    }
                }
            } else if loadFailed {
                note("Couldn't load the people you follow. Check your connection.")
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            }
        }
        .task {
            guard people == nil else { return }
            loadFailed = false
            do {
                people = try await model.api.taggableUsers()
            } catch {
                loadFailed = true
            }
        }
        .onAppear { isShowing = true }
        .onDisappear { isShowing = false }
        .saveFailedAlert(isPresented: $saveFailed)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
    }
}

/// A quiet row with a spinner, while something loads.
private struct LoadingRow: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.body).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            ProgressView()
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    /// After a settings change the server didn't get. The switches are already back as they were.
    func saveFailedAlert(isPresented: Binding<Bool>) -> some View {
        alert("Couldn't save", isPresented: isPresented) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Nothing changed.")
        }
    }
}

/// A round check that fills sage when chosen.
private struct CheckMark: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            Circle().strokeBorder(isOn ? Color.accentColor : Color.primary.opacity(0.25), lineWidth: 1.5)
            if isOn {
                Circle().fill(Color.accentColor)
                Icon(Glyph.done, weight: .bold, size: 13).foregroundStyle(.white)
            }
        }
        .frame(width: 24, height: 24)
        .animation(.snappy(duration: 0.2), value: isOn)
        .accessibilityHidden(true)
    }
}
