import SwiftUI

/// Someone new chooses a username. Until they do there is no account, only the ticket from Sign in
/// with Apple, which can make this one account once.
struct UsernameView: View {
    @Environment(AppModel.self) private var model
    @State private var username = ""
    @State private var name = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose a username")
                .font(Theme.display(32))
                .padding(.top, 40)
            Text("It's how people find you. You can change it later.")
                .foregroundStyle(.secondary)

            TextField("username", text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.username)
                .focused($focused)
                .onChange(of: username) { _, typed in
                    let cleaned = Self.clean(typed)
                    if cleaned != typed { username = cleaned }
                }
                .padding(14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))

            TextField("Your name (optional)", text: $name)
                .textContentType(.name)
                .padding(14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(Theme.danger)
            }

            Spacer()

            Button {
                Task { await create() }
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(isWorking || username.count < 2)
            .accessibilityIdentifier("create-account")

            Button("Back") { model.cancelSignUp() }
                .frame(maxWidth: .infinity)
        }
        .padding(24)
        .frame(maxWidth: 520)
        .onAppear {
            name = model.signupName ?? ""
            focused = true
        }
    }

    /// Lowercase letters, numbers, dots and underscores, 24 at most: exactly what the server keeps.
    nonisolated static func clean(_ text: String) -> String {
        String(text.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_") }.prefix(24))
    }

    private func create() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        do {
            try await model.createAccount(username: username, name: trimmed.isEmpty ? nil : trimmed)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
