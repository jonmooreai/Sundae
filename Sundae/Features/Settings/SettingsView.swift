import LocalAuthentication
import SwiftUI
import UIKit
import PhosphorSwift

/// Account, privacy, auto-approve list, notifications. Open every day.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var settings = AccountSettings()
    @State private var loaded = false
    @State private var taggable: [User] = []
    @State private var confirmDelete = false
    @State private var confirmSignOut = false
    @State private var showLocationConsent = false

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: Binding(get: { model.appearance }, set: { model.setAppearance($0) })) {
                    ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                }
            }

            Section {
                Toggle("Public account", isOn: $settings.isPublic)
            } header: {
                Text("Privacy")
            } footer: {
                Text(settings.isPublic
                     ? "Anyone can follow you without asking and see your weeks."
                     : "People ask to follow you and you decide. Your weeks are only visible to people you accept.")
            }

            Section {
                Toggle("Ideas near me", isOn: Binding(
                    get: { model.localIdeas.isEnabled },
                    set: { on in
                        if on { showLocationConsent = true } else { model.localIdeas.disable() }
                    }))
                if model.localIdeas.isEnabled, model.localIdeas.isDenied,
                   let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("Location is off for Sundae in iOS Settings. Open Settings", destination: url)
                        .textButtonTint()
                }
            } header: {
                Text("Weekday ideas")
            } footer: {
                Text("Monday to Saturday, today's idea can come from your neighborhood. Your exact location never leaves this phone: Sundae sends a neighborhood-sized area, about a kilometer across, with no account attached, and only when you open the app on a weekday. Never on Sunday, never on your photos, never shown to anyone.")
            }

            Section {
                NavigationLink {
                    AutoApproveList(settings: $settings, people: taggable)
                } label: {
                    HStack {
                        Text("Auto-approve tags")
                        Spacer()
                        Text(settings.autoApproveUserIDs.isEmpty ? "Nobody" : "\(settings.autoApproveUserIDs.count)")
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle("Allow comments on my weeks", isOn: $settings.commentsEnabled)
            } footer: {
                Text("Tags from auto-approved friends land on your week right away. Everyone else waits for you.")
            }

            Section {
                Toggle("Sunday reminder, 9:00 am", isOn: $settings.notifySundayReminder)
                Toggle("Last call, 8:00 pm if you haven't posted", isOn: $settings.notifyLastCall)
                Toggle("Someone tagged you", isOn: $settings.notifyTags)
                Toggle("Follow requests", isOn: $settings.notifyFollowRequests)
                Toggle("Likes and comments, Sunday only", isOn: $settings.notifyLikesAndComments)
                Toggle("Your tag was approved", isOn: $settings.notifyTagApproved)
            } header: {
                Text("Notifications")
            } footer: {
                Text("At most one push per weekday, as a noon digest. Nothing ever tells you what's in the feed. Weekday suggestions are never pushed.")
            }

            Section("Devices") {
                LabeledContent("This device", value: UIDevice.current.name)
                Button("Sign out everywhere", role: .destructive) { confirmSignOut = true }
            }

            Section {
                Button("Export my data") { }
                    .disabled(true)
                    .textButtonTint()
                Button("Delete account", role: .destructive) {
                    Task { if await freshAuthentication() { confirmDelete = true } }
                }
            } header: {
                Text("Your data")
            } footer: {
                Text("Export arrives within 24 hours as a zip of your photos, captions, tags and settings. Deletion completes within 30 days.")
            }

            if model.isUsingMock {
                Section {
                    Picker("Day", selection: Binding(get: { model.debugDay }, set: { model.setDebugDay($0) })) {
                        ForEach(DebugDay.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    Toggle("Always open on the post screen",
                           isOn: Binding(get: { model.compose.alwaysShowPrompt }, set: { model.compose.alwaysShowPrompt = $0 }))
                } header: {
                    Text("Demo")
                } footer: {
                    Text("This build runs on built-in demo data. Move the clock to see the Sunday screens on any day. The post screen normally shows once per Sunday until you post or wave it away; the switch shows it on every open.")
                }
            }

            Section {
                Button("Sign out") { Task { await model.signOut() } }
                    .textButtonTint()
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
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
            Button("Sign out everywhere", role: .destructive) { Task { await model.signOut() } }
        }
        .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await model.deleteAccount() } }
        } message: {
            Text("Your dumps and tags are removed within 30 days. Photos you were tagged in stay in the poster's dump with the tag removed.")
        }
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
        List {
            if people.isEmpty {
                Text("Follow some friends first.").foregroundStyle(.secondary)
            }
            ForEach(people) { user in
                let isOn = settings.autoApproveUserIDs.contains(user.id)
                Button {
                    if isOn {
                        settings.autoApproveUserIDs.removeAll { $0 == user.id }
                    } else {
                        settings.autoApproveUserIDs.append(user.id)
                    }
                } label: {
                    HStack {
                        UserRow(user: user)
                        ZStack {
                            Circle().strokeBorder(isOn ? Color.accentColor : Theme.hairline, lineWidth: 1.5)
                            if isOn {
                                Circle().fill(Color.accentColor)
                                Icon(Glyph.done, weight: .bold, size: 14).foregroundStyle(.white)
                            }
                        }
                        .frame(width: 26, height: 26)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Auto-approve")
        .navigationBarTitleDisplayMode(.inline)
    }
}
