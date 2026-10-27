import SwiftUI
import UIKit
import PhosphorSwift

/// The screen people see most. One suggestion, large type, nowhere else to go.
/// It should look like a nice postcard, not an error state.
struct WeekdayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showLocationConsent = false
    /// The screen's height, so the place card leaves out its picture where there is no room.
    @State private var height: CGFloat = 852

    private var store: WeekdayStore { model.weekday }
    private var nearby: LocalIdeasStore { model.localIdeas }

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
            .padding(24)
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
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }
        }
        .sheet(isPresented: $showLocationConsent) {
            LocationConsentSheet { nearby.enable() }
        }
    }

    // MARK: - Pieces

    private var topBar: some View {
        HStack {
            // Approvals wait for Sunday's bar; weekdays stay quiet. This keeps the mark centered.
            Color.clear.frame(width: 40, height: 40)

            Spacer()
            // Big enough to want to tap; smaller when a phone on its side has little height to spare.
            TiltingCherry(size: verticalSizeClass == .compact ? 64 : 96).wobbleOnTap()
            Spacer()

            IconButton(glyph: Glyph.settings, label: "Settings", filled: true) { showSettings = true }
        }
        .foregroundStyle(.primary)
    }

    @ViewBuilder
    private var suggestionBlock: some View {
        if let suggestion = store.current {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 6) {
                        if store.justMarkedDone {
                            Icon(Glyph.approvals, weight: .fill, size: 18)
                                .foregroundStyle(Color.accentColor)
                                .transition(.scale.combined(with: .opacity))
                        }
                        Text(store.justMarkedDone ? "That's one for Sunday" : dayLine(nearby: suggestion.isNearby))
                            .textCase(.uppercase)
                            .tracking(0.8)
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    Text(suggestion.text)
                        .font(Theme.display(verticalSizeClass == .compact ? 30 : 40))
                        .lineSpacing(2)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(store.justMarkedDone ? .secondary : .primary)
                        .strikethrough(store.justMarkedDone, color: .secondary)
                    Text(store.justMarkedDone ? "Take the photos. Sunday will remind you." : suggestion.reason)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                // The words read as one; the card's buttons stay buttons of their own.
                .accessibilityElement(children: .combine)
                if let place = suggestion.place, !store.justMarkedDone {
                    PlaceCard(place: place, distance: distanceLine(place),
                              showsPicture: verticalSizeClass != .compact && height >= 740)
                        .padding(.top, 6)
                        .transition(.opacity)
                }
            }
            .animation(.default, value: store.justMarkedDone)
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
                        Text(store.justMarkedDone ? "Another idea" : "Shuffle")
                    }
                }
                .buttonStyle(.pill(.secondary, fullWidth: true))

                if !store.justMarkedDone {
                    Button {
                        Task { await store.markDone(clock: model.clock) }
                    } label: {
                        HStack(spacing: 8) {
                            Icon(Glyph.done, weight: .bold, size: 18)
                            Text("Done")
                        }
                    }
                    .buttonStyle(.pill(.primary, fullWidth: true))
                    .disabled(store.isCurrentDone || store.isResting)
                }
            }
            Text(countdown)
                .font(.footnote)
                .foregroundStyle(.secondary)
            nearbyFooter
        }
        .animation(.default, value: nearby.status)
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
        if store.isResting { return "Done comes back in a minute. So do you." }
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
