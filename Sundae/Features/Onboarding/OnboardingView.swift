import AuthenticationServices
import PhotosUI
import SwiftUI
import PhosphorSwift

/// Five short steps on cream paper: what Sundae is, sign in, who you are, ideas near you, bring your group.
/// Every step says plainly what happens next; nothing is sent to anyone without a tap that
/// says so. Sign in with Apple is primary; phone is the labeled fallback, folded away.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Step: Int, CaseIterable { case welcome, signIn, profile, ideas, friends }

    @State private var step: Step = .welcome
    @State private var pendingMethod: SignInMethod?
    /// The nonce for the Sign in with Apple attempt in progress. Apple only ever sees its hash.
    @State private var appleNonce = ""
    @State private var name = ""
    @State private var username = ""
    @State private var birthday = Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date()
    @State private var phone = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var showPhone = false
    @State private var avatarItem: PhotosPickerItem?
    @State private var avatarImage: UIImage?
    @State private var avatarData: Data?
    @State private var error: String?
    @State private var showPrivacy = false
    @State private var isWorking = false

    private var isOldEnough: Bool {
        (Calendar.current.dateComponents([.year], from: birthday, to: Date()).year ?? 0) >= 16
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    Group {
                        switch step {
                        case .welcome: welcome
                        case .signIn: signIn
                        case .profile: profile
                        case .ideas: ideas
                        case .friends: friends
                        }
                    }
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)))
                    .frame(maxWidth: 480)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.4), value: step)
        }
        .filmGrain()
        .sheet(isPresented: $showPrivacy) { PrivacySheet() }
    }

    // MARK: Chrome

    /// Back on every step but the first, and four small dots that fill as you go.
    private var topBar: some View {
        HStack {
            if step != .welcome {
                IconButton(glyph: Glyph.back, label: "Back", size: 22) { goBack() }
            } else {
                Color.clear.frame(width: 40, height: 40)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { s in
                    Capsule()
                        .fill(s.rawValue <= step.rawValue ? Color.accentColor : Theme.hairline)
                        .frame(width: s == step ? 18 : 6, height: 6)
                }
            }
            .animation(.snappy(duration: 0.3), value: step)
            .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func goBack() {
        error = nil
        switch step {
        case .welcome: break
        case .signIn: step = .welcome
        case .profile: step = .signIn
        case .ideas: step = .profile
        case .friends: step = .ideas
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 28) {
            SundaeMark(size: 96)
                .wobbleOnTap()
                .padding(.top, 24)
            VStack(alignment: .leading, spacing: 10) {
                Text("Sundae")
                    .font(Theme.display(44))
                Text("A photo dump app that opens once a week. Six days to live it, one day to share it.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 16) {
                valueRow(Glyph.sun, "One idea a day", "Monday to Saturday the feed is closed. You get a single thing worth going to do.", index: 0)
                valueRow(Glyph.photos, "Post your week", "On Sunday, pick the photos, tag who was there, and see everyone else's week.", index: 1)
                valueRow(Glyph.calendar, "A life in weeks", "Your profile becomes a week-by-week archive of what you did.", index: 2)
            }
            PrimaryButton(title: "Get started") { step = .signIn }
                .padding(.top, 8)
        }
        .padding(.top, 12)
    }

    /// Each row drifts up into place a beat after the one above it.
    private func valueRow(_ glyph: Ph, _ title: String, _ detail: String, index: Int) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Icon(glyph, weight: .bold, size: 20)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(Theme.surface, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .modifier(RiseIn(delay: 0.25 + Double(index) * 0.12))
    }

    private var signIn: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading("Sign in", "No passwords. Nothing to leak, nothing to reset.")

            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.fullName]
                let nonce = AppleNonce.make()
                appleNonce = nonce
                request.nonce = AppleNonce.sha256(nonce)
            } onCompletion: { result in
                switch result {
                case .success(let auth):
                    let credential = auth.credential as? ASAuthorizationAppleIDCredential
                    let token = credential?.identityToken.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    let fullName = [credential?.fullName?.givenName, credential?.fullName?.familyName]
                        .compactMap { $0 }.joined(separator: " ")
                    if !fullName.isEmpty { name = fullName }
                    pendingMethod = .apple(identityToken: token, fullName: fullName.isEmpty ? nil : fullName, nonce: appleNonce)
                    step = .profile
                case .failure(let err):
                    error = err.localizedDescription
                }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 50)
            .clipShape(Capsule())

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
            }

            // Phone sign-in is demo only: the server signs people in with Apple, so there is no
            // SMS to pay for (docs/SERVER.md).
            if model.isUsingMock {
                if showPhone {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Phone number")
                            .font(.subheadline.weight(.medium))
                        Text("A text with a code is the least secure way in. It is here for people without an Apple ID on a shared device.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if codeSent {
                            field("6-digit code", text: $code)
                                .keyboardType(.numberPad)
                                .textContentType(.oneTimeCode)
                            Button("Continue") {
                                pendingMethod = .phone(number: phone, code: code)
                                step = .profile
                            }
                            .buttonStyle(.pill(.secondary, size: .small))
                            .disabled(code.count != 6)
                        } else {
                            field("Phone number", text: $phone)
                                .keyboardType(.phonePad)
                                .textContentType(.telephoneNumber)
                            Button("Text me a code") { codeSent = true }
                                .buttonStyle(.pill(.secondary, size: .small))
                                .disabled(phone.filter(\.isNumber).count < 10)
                        }
                    }
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    Button("Use a phone number instead") {
                        withAnimation(.snappy(duration: 0.3)) { showPhone = true }
                    }
                    .buttonStyle(.pill(.quiet, fullWidth: true))
                }
            }

            // Readable before there is an account: what Sundae keeps and never collects.
            Button("How Sundae handles your data") { showPrivacy = true }
                .buttonStyle(.pill(.quiet, fullWidth: true))

            if let error {
                Text(error).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var profile: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading("Who are you?", "A face and a name so friends know it's you.")

            HStack(spacing: 16) {
                PhotosPicker(selection: $avatarItem, matching: .images) {
                    ZStack {
                        if let avatarImage {
                            Image(uiImage: avatarImage)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Theme.surface
                            Icon(Glyph.plus, weight: .bold, size: 22).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 84, height: 84)
                    .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(avatarImage == nil ? "Add a profile photo" : "Change profile photo")
                VStack(alignment: .leading, spacing: 4) {
                    Text(avatarImage == nil ? "Add a photo" : "Looking good")
                        .font(.body.weight(.semibold))
                    Text("Optional. You can change it any time.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: avatarItem) { _, item in
                guard let item else { return }
                Task { await loadAvatar(item) }
            }

            VStack(spacing: 10) {
                field("Name (optional)", text: $name)
                    .textContentType(.name)
                HStack(spacing: 2) {
                    Text("@").foregroundStyle(.secondary)
                    TextField("username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                }
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
                DatePicker("Birthday", selection: $birthday, in: ...Date(), displayedComponents: .date)
                    .padding(12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
            }
            Text(isOldEnough
                 ? "Your birthday is checked once. Only the day and month stay on this phone, for one small surprise a year. No email is collected."
                 : "Sundae is for people 16 and up.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            PrimaryButton(title: "Continue",
                          isEnabled: isOldEnough && username.trimmingCharacters(in: .whitespaces).count >= 2) {
                step = .ideas
            }
        }
    }

    /// The one permission about place, explained before iOS is involved. Agreeing here turns it
    /// on; iOS itself asks on the first weekday look. Saying no changes nothing and costs nothing.
    private var ideas: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading("Ideas near you?", "Monday to Saturday, Sundae gives you one thing worth doing. With your location, it can be one thing nearby, or one worth the drive.")

            VStack(alignment: .leading, spacing: 16) {
                valueRow(Glyph.calendar, "Weekdays only",
                         "When you open Sundae on a weekday, it looks once to pick today's idea near you. On Sunday it never looks, whatever this is set to.", index: 0)
                valueRow(Glyph.lock, "A neighborhood, not a pin",
                         "Your exact spot stays on this phone. Only an area about a kilometer across is looked up, with no account attached.", index: 1)
                valueRow(Glyph.block, "Nowhere else",
                         "Never on your photos, never shown to friends, never saved. Turn it off any time in Settings.", index: 2)
            }

            PrimaryButton(title: "Use my location on weekdays") {
                model.localIdeas.enable()
                step = .friends
            }
            .padding(.top, 8)
            Button("Not now") { step = .friends }
                .buttonStyle(.pill(.quiet, fullWidth: true))
        }
    }

    /// Nothing here happens on its own. Each choice says who is involved before you tap.
    private var friends: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading("Bring your group", "Sundae is quiet with two friends and great with ten. Invite the people you actually spend your weeks with.")

            VStack(alignment: .leading, spacing: 14) {
                choice(
                    Glyph.share, "Tell a few friends",
                    "Opens the share sheet with a short note. You pick who gets it. Sundae is invite only while it's in testing."
                ) {
                    ShareLink(item: Invite.note, subject: Text(Invite.subject)) {
                        Text("Choose who to tell").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.pill(.secondary, fullWidth: true))
                }
            }

            Button {
                Task { await finishSignIn() }
            } label: {
                ZStack {
                    Text("Open Sundae").opacity(isWorking ? 0 : 1)
                    if isWorking { ProgressView().tint(.white) }
                }
            }
            .buttonStyle(.pill(.primary, fullWidth: true))
            .disabled(isWorking)
            .padding(.top, 8)

            if let error {
                Text(error).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Pieces

    private func heading(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Theme.display(34))
            Text(subtitle).font(.body).foregroundStyle(.secondary)
        }
        .padding(.top, 12)
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
    }

    /// One option on the friends step: what it is, what it does, and the button that does it.
    private func choice<Action: View>(_ glyph: Ph, _ title: String, _ detail: String,
                                      @ViewBuilder action: () -> Action) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Icon(glyph, weight: .bold, size: 18)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
                    .background(Theme.surface, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.body.weight(.semibold))
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
            }
            action()
        }
        .padding(14)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.5)
        }
    }

    // MARK: Actions

    private func loadAvatar(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        avatarData = data
        avatarImage = image
    }

    /// Signs in, then applies the photo.
    /// Once the model flips `isSignedIn`, RootView moves on to the app.
    private func finishSignIn() async {
        guard let method = pendingMethod else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await model.signIn(method, username: username.lowercased().trimmingCharacters(in: .whitespaces),
                                   name: name.trimmingCharacters(in: .whitespaces))
            MomentMemory.birthdayMonthDay = MomentMemory.monthDay(birthday, calendar: Calendar.current)
            if let avatarData {
                try? await model.updateAvatar(avatarData)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
