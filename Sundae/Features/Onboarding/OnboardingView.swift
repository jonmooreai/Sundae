import AuthenticationServices
import PhotosUI
import SwiftUI
import WidgetKit

/// The felt sundae full screen, then short steps on cream paper: what Sundae is, sign in, who you
/// are, ideas near you, Sunday reminders, the widgets, bring your group.
/// Someone signing back in skips the rest: their account comes back as it was, and only a question
/// this phone has never had an answer to (location, notifications) is still asked.
/// Every step says plainly what happens next; nothing is sent to anyone without a tap that
/// says so. iOS's own prompts come straight after the yes that explains them.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Step: Int, CaseIterable { case welcome, signIn, profile, ideas, reminders, widgets, friends }

    @State private var showsIntro = true
    @State private var step: Step = .welcome
    /// The steps this person goes through: all of them when new, fewer when signing back in.
    @State private var route: [Step] = Step.allCases
    /// From the server when this Apple ID has no account yet. It creates one, once.
    @State private var signupTicket: String?
    /// True from sending the new account until it is confirmed, so a reply lost on the way is
    /// finished off by signing in again instead of losing the photo and birthday.
    @State private var signupSent = false
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
    /// This phone has been through these questions, whatever the answer, so signing back in skips them.
    @AppStorage("onboarding.askedIdeas") private var askedIdeas = false
    @AppStorage("onboarding.askedReminders") private var askedReminders = false

    private var isOldEnough: Bool {
        (Calendar.current.dateComponents([.year], from: birthday, to: Date()).year ?? 0) >= 16
    }

    var body: some View {
        Group {
            if showsIntro {
                OnboardingIntro {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) { showsIntro = false }
                }
                .transition(.opacity)
            } else {
                steps.transition(.opacity)
            }
        }
        .filmGrain()
        .sheet(isPresented: $showPrivacy) { PrivacySheet() }
        .task {
            // Opened again partway through, with the account already made: carry on from there.
            guard model.isSignedIn, step == .welcome else { return }
            showsIntro = false
            route = [.welcome, .signIn] + (await unaskedSteps()) + [.friends]
            step = route[2]
        }
    }

    private var steps: some View {
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
                        case .reminders: reminders
                        case .widgets: widgets
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
    }

    // MARK: Chrome

    /// Back where there is somewhere to go back to, and a small dot for each step.
    private var topBar: some View {
        HStack {
            if !isWorking, let previous = previousStep {
                IconButton(glyph: Glyph.back, label: "Back", size: 22) {
                    error = nil
                    step = previous
                }
            } else {
                Color.clear.frame(width: 40, height: 40)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(route, id: \.self) { s in
                    Capsule()
                        .fill(s.rawValue <= step.rawValue ? Color.accentColor : Theme.hairline)
                        .frame(width: s == step ? 18 : 6, height: 6)
                }
            }
            .animation(.snappy(duration: 0.3), value: step)
            .accessibilityLabel("Step \((route.firstIndex(of: step) ?? 0) + 1) of \(route.count)")
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// Where Back goes. Once there is an account, signing in and choosing a username are done.
    private var previousStep: Step? {
        guard let index = route.firstIndex(of: step), index > 0 else { return nil }
        let previous = route[index - 1]
        if model.isSignedIn, previous.rawValue <= Step.profile.rawValue { return nil }
        return previous
    }

    /// On to the next step, or into the app after the last one.
    private func next() {
        error = nil
        if let index = route.firstIndex(of: step), index + 1 < route.count {
            step = route[index + 1]
        } else {
            model.finishOnboarding()
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 28) {
            CherryMark(size: 96)
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
                    let method = SignInMethod.apple(identityToken: token, fullName: fullName.isEmpty ? nil : fullName, nonce: appleNonce)
                    Task { await continueSignIn(method) }
                case .failure(let err):
                    // Closing Apple's sheet is a change of mind, not a problem to report.
                    if (err as? ASAuthorizationError)?.code != .canceled { error = err.localizedDescription }
                }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 50)
            .clipShape(Capsule())
            .disabled(isWorking)
            .opacity(isWorking ? 0.5 : 1)

            if isWorking {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }

            if model.isUsingMock {
                VStack(spacing: 6) {
                    Button("Continue in demo mode") {
                        Task { await continueSignIn(.demo) }
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
                                Task { await continueSignIn(.phone(number: phone, code: code)) }
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

            // Readable before there is an account: what Sundae uses and never collects.
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
            PrimaryButton(title: "Continue", isLoading: isWorking,
                          isEnabled: isOldEnough && chosenUsername.count >= 2) {
                Task { await createAccount() }
            }

            if let error {
                Text(error).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var chosenUsername: String {
        username.lowercased().trimmingCharacters(in: .whitespaces)
    }

    /// The one permission about place, explained before iOS is involved. Agreeing turns it on and
    /// iOS asks straight away. Saying no changes nothing and costs nothing.
    private var ideas: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading("Ideas near you?", "Monday to Saturday, Sundae gives you one thing worth doing, and you can save the ones you like for later. With your location, it can be nearby, or worth the drive.")

            VStack(alignment: .leading, spacing: 16) {
                valueRow(Glyph.calendar, "Weekdays only",
                         "When you open Sundae on a weekday, it looks once to pick today's idea near you. On Sunday it never looks, whatever this is set to.", index: 0)
                valueRow(Glyph.lock, "A neighborhood, not a pin",
                         "Your exact spot stays on this phone. Only an area about a kilometer across is looked up, with no account attached.", index: 1)
                valueRow(Glyph.block, "Nowhere else",
                         "Never on your photos, never shown to friends, never saved. Turn it off any time in Settings.", index: 2)
            }

            VStack(spacing: 10) {
                PrimaryButton(title: "Use my location on weekdays") {
                    askedIdeas = true
                    // iOS asks now, over the next step. While Using the App is all it needs.
                    model.localIdeas.enable()
                    next()
                }
                Text("iOS asks next. While Using the App is all Sundae needs.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
            Button("Not now") {
                askedIdeas = true
                next()
            }
            .buttonStyle(.pill(.quiet, fullWidth: true))
        }
    }

    /// Sundae opens once a week, so a nudge on Sunday is the one notification worth having. Asked
    /// here with the reason beside it; iOS's prompt comes after the yes. No changes nothing.
    private var reminders: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading("Sunday reminders?", "Sundae opens once a week, so a nudge helps. It sends two, and only on Sunday.")

            VStack(alignment: .leading, spacing: 16) {
                valueRow(Glyph.bell, "Sunday, 9:00 am", "Sunday is here. Time to post your week.", index: 0)
                valueRow(Glyph.moon, "Sunday, 8:00 pm", "A last call, only if you haven't posted. Your week closes at midnight.", index: 1)
                valueRow(Glyph.block, "Nothing midweek", "No nudges the rest of the week. Change either one any time in Settings.", index: 2)
            }

            VStack(spacing: 10) {
                PrimaryButton(title: "Remind me on Sundays", isLoading: isWorking) {
                    Task { await allowReminders() }
                }
                Text("iOS asks next.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
            Button("Not now") {
                askedReminders = true
                next()
            }
            .buttonStyle(.pill(.quiet, fullWidth: true))
            .disabled(isWorking)
        }
    }

    /// The widgets, shown rather than explained: swipe through the sizes. After the location
    /// question, so with a yes the samples are real ideas from nearby.
    private var widgets: some View {
        let sizes = WidgetMetrics.current()
        let snapshot = widgetSamples
        return VStack(alignment: .leading, spacing: 20) {
            heading("On your Home Screen", "Today's idea, without opening the app. Swipe to see the sizes, and add one any time from your Home Screen.")

            TabView {
                widgetPage(WidgetPreview(snapshot: snapshot, family: .systemSmall, size: sizes.small), "Small")
                widgetPage(WidgetPreview(snapshot: snapshot, family: .systemMedium, size: sizes.medium), "Wide")
                widgetPage(WidgetPreview(snapshot: snapshot, family: .systemLarge, size: sizes.large), "Large: a few ideas, nearby ones a tap from Maps")
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .frame(height: sizes.large.height + 76)
            .padding(.horizontal, -24)

            PrimaryButton(title: "Continue") { next() }
        }
        .task {
            // With a yes to location, look now, so the samples are from around here.
            await model.localIdeas.refresh(clock: model.clock)
        }
    }

    private func widgetPage(_ preview: WidgetPreview, _ label: String) -> some View {
        VStack(spacing: 10) {
            preview
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity)
    }

    /// Today's real ideas when there are nearby ones; otherwise today's catalog ideas with a few
    /// made-up nearby places mixed in, so every size shows what it can do.
    private var widgetSamples: WidgetSnapshot {
        var snapshot = WidgetSnapshotBuilder.snapshot(at: Date(), mode: .weekday,
                                                      catalog: model.suggestions, shared: model.shared)
        let nearby = model.localIdeas.ideas
        if nearby.isEmpty {
            let samples = Self.sampleNearby
            snapshot.idea = samples[0]
            let catalog = snapshot.list.filter { $0.place == nil }
            snapshot.list = [samples[0]] + Array(catalog.prefix(1)) + [samples[1]] + Array(catalog.dropFirst().prefix(1)) + [samples[2]]
        }
        return snapshot
    }

    /// Made-up places, worded like the real nearby ideas.
    private static let sampleNearby: [Suggestion] = [
        Suggestion(id: "sample-1", text: "Pick something you've never tried at Juniper Bakery.",
                   reason: "Take a photo of it before the first bite.", categories: [.local], timeOfDay: .any,
                   place: Suggestion.Place(name: "Juniper Bakery", walkMinutes: 6)),
        Suggestion(id: "sample-2", text: "Catch the last light at Riverside Park.",
                   reason: "Bring a friend and take photos of the sky as it changes.", categories: [.local], timeOfDay: .any,
                   place: Suggestion.Place(name: "Riverside Park", walkMinutes: 11)),
        Suggestion(id: "sample-3", text: "Browse Second Story Books for twenty minutes.",
                   reason: "Pick a book by its first sentence. Take a photo of it in your hands.", categories: [.local], timeOfDay: .any,
                   place: Suggestion.Place(name: "Second Story Books", distanceMeters: 2400)),
    ]

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

            PrimaryButton(title: "Open Sundae") { next() }
                .padding(.top, 8)
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

    /// Straight after Apple. Someone coming back is in, with only the questions this phone has never
    /// had an answer to still to come. Someone new goes on to choose a username.
    private func continueSignIn(_ method: SignInMethod) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        error = nil
        do {
            let unasked = await unaskedSteps()
            let finishingSignup = signupSent
            if let ticket = try await model.signIn(method, keepOnboarding: finishingSignup || !unasked.isEmpty) {
                signupTicket = ticket
                route = Step.allCases
                step = .profile
            } else if finishingSignup {
                // The account was made but its reply never came. Finish what "Who are you?" started.
                signupSent = false
                await applyProfileExtras()
                route = Step.allCases
                step = .ideas
            } else if let first = unasked.first {
                route = [.welcome, .signIn] + unasked
                step = first
            }
            // Otherwise RootView has already moved on to the app.
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// For someone coming back: the permission steps this phone has never been through.
    private func unaskedSteps() async -> [Step] {
        var steps: [Step] = []
        if !askedIdeas, LocationCell.authorization == .notDetermined { steps.append(.ideas) }
        if !askedReminders, await NotificationScheduler.authorizationStatus() == .notDetermined { steps.append(.reminders) }
        return steps
    }

    /// Creates the account with the username they chose, then sends the photo.
    private func createAccount() async {
        guard !isWorking else { return }
        guard let ticket = signupTicket else {
            step = model.isSignedIn ? .ideas : .signIn
            return
        }
        isWorking = true
        defer { isWorking = false }
        error = nil
        let chosenName = name.trimmingCharacters(in: .whitespaces)
        signupSent = true
        do {
            try await model.createAccount(ticket: ticket, username: chosenUsername, name: chosenName.isEmpty ? nil : chosenName)
            signupTicket = nil
            signupSent = false
            await applyProfileExtras()
            step = .ideas
        } catch SundaeError.notAuthorized, SundaeError.signInAgain {
            // The ticket ran out, or the account was made already. Apple once more sorts out both.
            signupTicket = nil
            step = .signIn
            self.error = SundaeError.signInAgain.localizedDescription
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// The birthday and photo from "Who are you?", once the account exists. A photo the account
    /// already has is never replaced.
    private func applyProfileExtras() async {
        MomentMemory.birthdayMonthDay = MomentMemory.monthDay(birthday, calendar: Calendar.current)
        if let avatarData, model.currentUser?.avatar == nil {
            try? await model.updateAvatar(avatarData)
        }
    }

    /// iOS's notification prompt, then the reminders, then on. Whatever the answer, Settings can
    /// change it later.
    private func allowReminders() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        askedReminders = true
        await NotificationScheduler.requestAuthorizationIfNeeded()
        // Someone who once turned both off has just asked for them again.
        if let settings = model.accountSettings, !settings.notifySundayReminder, !settings.notifyLastCall {
            var wanted = settings
            wanted.notifySundayReminder = true
            wanted.notifyLastCall = true
            _ = await model.saveAccountSettings(from: settings, to: wanted)
        }
        model.scheduleReminders()
        next()
    }
}
