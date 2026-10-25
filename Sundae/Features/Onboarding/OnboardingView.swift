import AuthenticationServices
import SwiftUI
import PhosphorSwift

/// Signup is built around inviting a group, not a single person. Four steps: what Sundae is,
/// sign in, who you are, bring your friends. Sign in with Apple and passkeys are primary;
/// phone is the labeled fallback.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    private enum Step { case welcome, signIn, profile, invite }

    @State private var step: Step = .welcome
    @State private var pendingMethod: SignInMethod?
    @State private var name = ""
    @State private var username = ""
    @State private var birthday = Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date()
    @State private var phone = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var error: String?
    @State private var isWorking = false

    private var isOldEnough: Bool {
        (Calendar.current.dateComponents([.year], from: birthday, to: Date()).year ?? 0) >= 16
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack {
                Spacer(minLength: 0)
                Group {
                    switch step {
                    case .welcome: welcome
                    case .signIn: signIn
                    case .profile: profile
                    case .invite: invite
                    }
                }
                .frame(maxWidth: 480)
                .animation(.default, value: step)
                Spacer(minLength: 0)
            }
            .padding(24)
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 24) {
            SundaeMark(size: 72)
            Text("Sundae")
                .font(Theme.display(44))
            Text("A photo dump app that only opens on Sundays.")
                .font(.title2)
            VStack(alignment: .leading, spacing: 12) {
                bullet("Monday to Saturday, the feed is closed. You get one idea for something to go do.")
                bullet("Sunday, post the week's photos, tag the friends who were there, and see everyone else's week.")
                bullet("Over time, your profile becomes a week-by-week archive of your life.")
            }
            .font(.body)
            .foregroundStyle(.secondary)
            PrimaryButton(title: "Get started") { step = .signIn }
        }
    }

    private var signIn: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Sign in").font(Theme.display(34))
            Text("No passwords. Nothing to leak, nothing to reset.")
                .foregroundStyle(.secondary)

            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.fullName]
            } onCompletion: { result in
                switch result {
                case .success(let auth):
                    let credential = auth.credential as? ASAuthorizationAppleIDCredential
                    let token = credential?.identityToken.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    let fullName = [credential?.fullName?.givenName, credential?.fullName?.familyName]
                        .compactMap { $0 }.joined(separator: " ")
                    if !fullName.isEmpty { name = fullName }
                    pendingMethod = .apple(identityToken: token, fullName: fullName.isEmpty ? nil : fullName)
                    step = .profile
                case .failure(let err):
                    error = err.localizedDescription
                }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                Text("Or use your phone number")
                    .font(.subheadline.weight(.medium))
                Text("SMS codes are the least secure option and only here for people without an Apple ID on a shared device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if codeSent {
                    TextField("6-digit code", text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .padding(12)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
                    Button("Continue") {
                        pendingMethod = .phone(number: phone, code: code)
                        step = .profile
                    }
                    .buttonStyle(.pill(.secondary, size: .small))
                    .disabled(code.count != 6)
                } else {
                    TextField("Phone number", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .padding(12)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
                    Button("Send code") { codeSent = true }
                        .buttonStyle(.pill(.secondary, size: .small))
                        .disabled(phone.filter(\.isNumber).count < 10)
                }
            }
            .padding(.top, 8)

            if model.isUsingMock {
                VStack(spacing: 6) {
                    Button("Continue in demo mode") {
                        pendingMethod = .demo
                        step = .profile
                    }
                    .buttonStyle(.pill(.secondary, fullWidth: true))
                    Text("No server yet: this build runs on built-in demo data.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }

            if let error {
                Text(error).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var profile: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Who are you?").font(Theme.display(34))
            VStack(spacing: 10) {
                TextField("Name (optional)", text: $name)
                    .textContentType(.name)
                    .padding(12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                    .padding(12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
                DatePicker("Birthday", selection: $birthday, in: ...Date(), displayedComponents: .date)
                    .padding(12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
            }
            if !isOldEnough {
                Text("Sundae is for people 16 and up.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text("Your birthday is checked once and not stored. Name and bio are optional; no email is collected.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            PrimaryButton(title: "Continue",
                          isEnabled: isOldEnough && username.trimmingCharacters(in: .whitespaces).count >= 2) {
                step = .invite
            }
        }
    }

    private var invite: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Bring your group").font(Theme.display(34))
            Text("Sundae is empty with fewer than five friends and great with ten. Send the link to the people you actually spend your weeks with.")
                .foregroundStyle(.secondary)
            Text("Once you're in, Search can check your contacts for people already here. Numbers are hashed on your phone and never stored.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ShareLink(item: URL(string: "https://sundae.app/join")!,
                      subject: Text("Join me on Sundae"),
                      message: Text("Sundays only. Come post your week with us.")) {
                HStack(spacing: 8) {
                    Icon(Glyph.share, weight: .bold, size: 18)
                    Text("Invite your group")
                }
            }
            .buttonStyle(.pill(.primary, fullWidth: true))
            Button {
                Task { await finishSignIn() }
            } label: {
                ZStack {
                    Text("Open Sundae").opacity(isWorking ? 0 : 1)
                    if isWorking { ProgressView() }
                }
            }
            .buttonStyle(.pill(.secondary, fullWidth: true))
            .disabled(isWorking)
            if let error {
                Text(error).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle().fill(Color.accentColor).frame(width: 6, height: 6).offset(y: -3)
            Text(text)
        }
    }

    /// Signs in. Once the model flips `isSignedIn`, RootView moves on to the app.
    private func finishSignIn() async {
        guard let method = pendingMethod else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await model.signIn(method, username: username.lowercased().trimmingCharacters(in: .whitespaces),
                                   name: name.trimmingCharacters(in: .whitespaces))
        } catch {
            self.error = error.localizedDescription
        }
    }
}
