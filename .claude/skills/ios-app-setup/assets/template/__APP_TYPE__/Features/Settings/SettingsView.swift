import SwiftUI

/// The account, privacy, sign out, and deleting the account, which Apple requires any app with
/// accounts to offer inside the app. Admins also see an Admin section.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let user = model.currentUser {
                    Section("Account") {
                        LabeledContent("Username", value: user.username)
                        if !user.name.isEmpty {
                            LabeledContent("Name", value: user.name)
                        }
                    }
                }

                Section {
                    NavigationLink("Privacy") { PrivacyView() }
                }

                if model.isAdmin {
                    Section("Admin") {
                        Text("Only admins see this section. Tools for trying things out go here.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button("Sign out") {
                        Task { await model.signOut() }
                    }
                    Button("Delete account", role: .destructive) {
                        confirmDelete = true
                    }
                    .disabled(isDeleting)
                } footer: {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(Theme.danger)
                    } else {
                        Text("Deleting removes your account and everything in it right away.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete account", role: .destructive) {
                    Task { await delete() }
                }
            } message: {
                Text("Your account and everything in it are deleted for good. This can't be undone.")
            }
        }
    }

    private func delete() async {
        isDeleting = true
        defer { isDeleting = false }
        errorMessage = nil
        do {
            try await model.deleteAccount()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
