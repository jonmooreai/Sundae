import AuthenticationServices
import SwiftUI

/// Sign in with Apple, the only way in: no passwords to leak, no codes to intercept, no email kept.
/// Each attempt makes a fresh nonce; Apple signs its SHA-256 into the token and the server checks
/// the pair and accepts each nonce once, so a copied token cannot be replayed.
struct SignInView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var nonce = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Text("Tally")
                .font(Theme.display(44))
            Text("No passwords. Sign in with your Apple Account, and your email stays private.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Spacer()

            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.fullName]
                let fresh = AppleNonce.make()
                nonce = fresh
                request.nonce = AppleNonce.sha256(fresh)
            } onCompletion: { result in
                handle(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 50)
            .clipShape(Capsule())
            .disabled(isWorking)
            .opacity(isWorking ? 0.5 : 1)

            if model.isUsingMock {
                Button {
                    Task { await signIn(token: "demo", nonce: AppleNonce.make(), fullName: nil) }
                } label: {
                    Text("Try the demo")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .disabled(isWorking)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(Theme.danger)
            }

            NavigationLink("Privacy") { PrivacyView() }
                .font(.footnote)
                .frame(maxWidth: .infinity)
        }
        .padding(24)
        .frame(maxWidth: 520)
    }

    private func handle(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let data = credential.identityToken,
                  let token = String(data: data, encoding: .utf8) else {
                errorMessage = AppError.signInAgain.localizedDescription
                return
            }
            // Apple shares the name only on the very first sign-in, so it is kept for the username step.
            let fullName = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
            let sentNonce = nonce
            Task { await signIn(token: token, nonce: sentNonce, fullName: fullName.isEmpty ? nil : fullName) }
        case .failure(let error):
            // Closing Apple's sheet is a change of mind, not a problem to report.
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func signIn(token: String, nonce: String, fullName: String?) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        do {
            try await model.signInWithApple(identityToken: token, nonce: nonce, fullName: fullName)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
