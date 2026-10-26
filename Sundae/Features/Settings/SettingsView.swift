import LocalAuthentication
import SwiftUI
import UIKit
import PhosphorSwift

/// Account, privacy, weekday ideas, tags, notifications, data. Open every day.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var settings = AccountSettings()
    @State private var loaded = false
    @State private var taggable: [User] = []
    @State private var confirmDelete = false
    @State private var confirmSignOut = false
    @State private var signOutFailed = false
    @State private var showLocationConsent = false

    var body: some View {
        SettingsScreen(title: "Settings") {
            SettingsGroup(title: "Appearance", card: false) {
                SegmentedChoice(options: Appearance.allCases.map { ($0, $0.shortLabel) },
                                selection: Binding(get: { model.appearance }, set: { model.setAppearance($0) }))
            }

            SettingsGroup(title: "Account") {
                RadioRow(title: "Private", detail: "You approve each follower.", isSelected: !settings.isPublic) {
                    settings.isPublic = false
                }
                RadioRow(title: "Public", detail: "Anyone can follow you.", isSelected: settings.isPublic) {
                    settings.isPublic = true
                }
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

            SettingsGroup(title: "Tags and comments") {
                SettingsLinkRow(title: "Auto-approve tags",
                                value: settings.autoApproveUserIDs.isEmpty ? "Nobody" : "\(settings.autoApproveUserIDs.count)") {
                    AutoApproveList(settings: $settings, people: taggable)
                }
                SettingsToggle(title: "Comments on my weeks", isOn: $settings.commentsEnabled)
            }

            SettingsGroup(title: "Notifications", footer: "Weekdays bring one at most, at noon.") {
                SettingsToggle(title: "Sunday reminder", detail: "9:00 am", isOn: $settings.notifySundayReminder)
                SettingsToggle(title: "Last call", detail: "8:00 pm, if you haven't posted", isOn: $settings.notifyLastCall)
                // These need push notifications, which the friends and family server does not send
                // yet. Shown with demo data only, so no switch here promises something that never comes.
                if model.isUsingMock {
                    SettingsToggle(title: "Tags", isOn: $settings.notifyTags)
                    SettingsToggle(title: "Follow requests", isOn: $settings.notifyFollowRequests)
                    SettingsToggle(title: "Likes and comments", detail: "Sundays only", isOn: $settings.notifyLikesAndComments)
                    SettingsToggle(title: "Approved tags", isOn: $settings.notifyTagApproved)
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
            settings = model.accountSettings
            taggable = (try? await model.api.taggableUsers()) ?? []
            loaded = true
        }
        .onChange(of: settings) { _, new in
            guard loaded else { return }
            Task { await model.saveAccountSettings(new) }
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
        .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await model.deleteAccount() } }
        } message: {
            Text("Your dumps, comments and tags are removed right away. Photos you were tagged in stay in the poster's dump with the tag removed.")
        }
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
    @Binding var settings: AccountSettings
    let people: [User]

    var body: some View {
        SettingsScreen(title: "Auto-approve") {
            if people.isEmpty {
                Text("Follow some friends first.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
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
