import SwiftUI
import UIKit

/// The screen people see most. One suggestion, large type, nowhere else to go.
/// It should look like a nice postcard, not an error state.
struct WeekdayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showLocationConsent = false
    @State private var showWeek = false
    @State private var showSavedIntro = false
    /// True for a moment after Save, for the line that says what happens next.
    @State private var justSaved = false
    /// The screen's height, so the place card leaves out its picture where there is no room.
    @State private var height: CGFloat = 852

    private var store: WeekdayStore { model.weekday }
    private var nearby: LocalIdeasStore { model.localIdeas }
    private var saved: SavedIdeasStore { model.savedIdeas }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 24)
                ZStack(alignment: .leading) {
                    suggestionBlock
                }
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Clipped so a shuffle slides in tidily, with room around it for the card's shadow.
                .padding(20)
                .clipped()
                .padding(-20)
                Spacer(minLength: 24)
                actions
                    .frame(maxWidth: 560)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .padding(.top, 12)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .goldenHour(calendar: model.clock.calendar)
        .birthdayPaper(calendar: model.clock.calendar)
        .task {
            store.load(clock: model.clock)
            await nearby.refresh(clock: model.clock)
        }
        .onChange(of: store.restUntil) { _, until in
            guard let until else { return }
            Task {
                try? await Task.sleep(for: .seconds(max(1, until.timeIntervalSinceNow)))
                store.endRest()
            }
        }
        .onChange(of: model.phase) { _, _ in store.load(clock: model.clock) }
        .onChange(of: nearby.ideas) { _, ideas in
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.35)) {
                store.applyLocal(ideas, clock: model.clock)
            }
        }
        .onChange(of: nearby.isEnabled) { _, enabled in
            // Turned on from Settings, or here. The first look may show the iOS prompt.
            if enabled { Task { await nearby.refresh(clock: model.clock) } }
        }
        .onChange(of: scenePhase) { _, phase in
            // Coming back later in the day, maybe somewhere else.
            if phase == .active { Task { await nearby.refresh(clock: model.clock) } }
        }
        .onChange(of: store.current?.id) { _, _ in justSaved = false }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }
        }
        .sheet(isPresented: $showLocationConsent) {
            LocationConsentSheet { nearby.enable() }
        }
        .sheet(isPresented: $showWeek) {
            YourWeekView()
        }
        .sheet(isPresented: $showSavedIntro) {
            SavedIntroSheet {
                Task { await saved.findPhotos(clock: model.clock) }
            }
        }
    }

    // MARK: - Pieces

    /// The cherry, or what stands in for it: the birthday sundae all your birthday week, or a
    /// holiday's felt piece through the week before its Sunday.
    private var pieceImage: String {
        if model.isBirthdayWeek { return CherryMark.birthday }
        return model.holidayThisWeek?.image ?? "Cherry"
    }

    /// The cherry in the middle; Your week up in the left corner and Settings in the right, out of its way.
    private var topBar: some View {
        ZStack(alignment: .top) {
            // Big enough to want to tap; smaller when a phone on its side has little height to spare.
            TiltingCherry(size: verticalSizeClass == .compact ? 64 : 96, image: pieceImage).wobbleOnTap()
                .padding(.top, 12)
                .frame(maxWidth: .infinity)

            HStack {
                IconButton(glyph: Glyph.saved, label: weekLabel, filled: true) { showWeek = true }
                    .overlay(alignment: .topTrailing) { savedBadge }
                    .accessibilityIdentifier("your-week")
                Spacer()
                IconButton(glyph: Glyph.settings, label: "Settings", filled: true) { showSettings = true }
            }
            .padding(.horizontal, -6)
        }
        .foregroundStyle(.primary)
    }

    /// How many ideas are saved, on the Your week button.
    @ViewBuilder
    private var savedBadge: some View {
        let count = saved.ideas.count
        if count > 0 {
            Text("\(count)")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(minWidth: 18, minHeight: 18)
                .padding(.horizontal, count > 9 ? 3 : 0)
                .background(Color.accentColor, in: Capsule())
                .offset(x: 4, y: -2)
                .transition(.scale.combined(with: .opacity))
                .accessibilityHidden(true)
        }
    }

    private var weekLabel: String {
        switch saved.ideas.count {
        case 0: "Your week"
        case 1: "Your week, 1 saved idea"
        case let count: "Your week, \(count) saved ideas"
        }
    }

    @ViewBuilder
    private var suggestionBlock: some View {
        if let suggestion = store.current {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 6) {
                        if store.isCurrentSaved {
                            Icon(Glyph.saved, weight: .fill, size: 16)
                                .foregroundStyle(Color.accentColor)
                                .transition(.scale.combined(with: .opacity))
                        }
                        Text(store.isCurrentSaved ? "Saved for this week" : dayLine(nearby: suggestion.isNearby))
                            .textCase(.uppercase)
                            .tracking(0.8)
                            .contentTransition(.opacity)
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    Text(suggestion.text)
                        .font(Theme.display(verticalSizeClass == .compact ? 28 : 36))
                        // Lines set close, so a headline of two or three lines reads as one.
                        .lineHeight(.multiple(factor: 1.05))
                        .minimumScaleFactor(0.6)
                    Text(suggestion.reason)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                // The words read as one; the card's buttons stay buttons of their own.
                .accessibilityElement(children: .combine)
                if let place = suggestion.place {
                    PlaceCard(place: place, distance: distanceLine(place),
                              showsPicture: verticalSizeClass != .compact && height >= 740)
                        .padding(.top, 6)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: store.isCurrentSaved)
            .id(suggestion.id)
            .transition(reduceMotion ? .opacity : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .opacity
            ))
        } else {
            Text("Go make something worth posting.")
                .font(Theme.display(36))
        }
    }

    /// "8 min walk" close by, "32 mi" when it is worth the trip.
    private func distanceLine(_ place: Suggestion.Place) -> String? {
        if let minutes = place.walkMinutes { return "\(minutes) min walk" }
        if let meters = place.distanceMeters {
            return Measurement(value: meters, unit: UnitLength.meters)
                .formatted(.measurement(width: .abbreviated, usage: .road))
        }
        return nil
    }

    private var actions: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.35)) {
                        store.shuffle(clock: model.clock)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Icon(Glyph.shuffle, weight: .bold, size: 18)
                        Text("Shuffle")
                    }
                }
                .buttonStyle(.pill(.secondary, fullWidth: true))

                if store.isCurrentSaved {
                    // Saved already: this opens the week, where it can be taken off again.
                    Button {
                        showWeek = true
                    } label: {
                        HStack(spacing: 8) {
                            Icon(Glyph.saved, weight: .fill, size: 18)
                            Text("Saved")
                        }
                    }
                    .buttonStyle(.pill(.secondary, fullWidth: true))
                    .accessibilityHint("Opens your week")
                } else {
                    Button {
                        save()
                    } label: {
                        HStack(spacing: 8) {
                            Icon(Glyph.saved, weight: .bold, size: 18)
                            Text("Save")
                        }
                    }
                    .buttonStyle(.pill(.primary, fullWidth: true))
                    .disabled(!store.canSaveCurrent)
                }
            }
            Text(justSaved ? savedLine : countdown)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
            nearbyFooter
        }
        .animation(.default, value: nearby.status)
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: store.isCurrentSaved)
        .animation(.default, value: justSaved)
    }

    /// Keeps the idea for the week. The first time, a drawer says where it went and what's next.
    private func save() {
        store.saveCurrent(clock: model.clock)
        justSaved = true
        if !saved.introShown {
            showSavedIntro = true
        } else {
            Task { await saved.findPhotos(clock: model.clock) }
        }
    }

    /// What happens to a saved idea, said once, just after saving it.
    private var savedLine: String {
        if store.current?.place != nil, PhotoFinder.isAuthorized {
            return "Photos you take there are added to it for you."
        }
        return "It's under the bookmark, top left."
    }

    /// One quiet line about ideas near you: the offer when it is off, the state when it is on.
    @ViewBuilder
    private var nearbyFooter: some View {
        switch nearby.status {
        case .off:
            Button {
                showLocationConsent = true
            } label: {
                HStack(spacing: 6) {
                    Icon(Glyph.pin, size: 15)
                    Text("Make today's idea local")
                }
            }
            .buttonStyle(.pill(.quiet, size: .small))
            .padding(.top, 2)
        case .waitingForPermission:
            footnote("iOS will ask about location the first time Sundae looks.")
        case .denied:
            VStack(spacing: 4) {
                footnote("Location is off for Sundae in iOS Settings, so today's idea is general.")
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("Open iOS Settings", destination: url)
                        .font(.footnote.weight(.medium))
                }
            }
        case .locating, .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Finding ideas near you")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .ready(let count):
            if count == 0 {
                footnote("Nothing near you yet, so today's idea is general.")
            }
        case .offline:
            footnote("Offline, so today's idea is general.")
        case .failed:
            footnote("Couldn't see what's near you today, so the idea is general.")
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    // MARK: - Copy

    private func dayLine(nearby: Bool) -> String {
        let now = model.clock.now()
        let slot = Suggestion.TimeOfDay.current(for: now, calendar: model.clock.calendar)
        let day = model.clock.weekdayName(now)
        let line: String
        switch slot {
        case .morning: line = "An idea for \(day) morning"
        case .afternoon: line = "An idea for \(day) afternoon"
        case .evening: line = "An idea for \(day) evening"
        case .any: line = "An idea for \(day)"
        }
        return nearby ? "\(line), near you" : line
    }

    private var countdown: String {
        if store.isResting { return "Save comes back in a minute. So do you." }
        switch model.phase {
        case .sunday: return "It's Sunday."
        case .weekday(let days):
            switch days {
            case 1: return "Sunday is tomorrow. Charge your phone."
            case 2: return "2 days until Sunday. Make them count."
            case 4: return "4 days until Sunday. Halfway-ish."
            case 6: return "6 days until Sunday. No rush."
            default: return "\(days) days until Sunday"
            }
        }
    }
}
