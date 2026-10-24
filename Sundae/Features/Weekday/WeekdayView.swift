import SwiftUI
import PhosphorSwift

/// The screen people see most. One suggestion, large type, nowhere else to go.
/// It should look like a nice postcard, not an error state.
struct WeekdayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showApprovals = false
    @State private var showSettings = false

    private var store: WeekdayStore { model.weekday }

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
                .clipped()
                Spacer(minLength: 24)
                actions
                    .frame(maxWidth: 560)
            }
            .padding(24)
        }
        .task { store.load(clock: model.clock) }
        .onChange(of: model.phase) { _, _ in store.load(clock: model.clock) }
        .sheet(isPresented: $showApprovals) {
            NavigationStack { ApprovalsView() }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }
        }
    }

    // MARK: - Pieces

    private var topBar: some View {
        HStack {
            Button {
                showApprovals = true
            } label: {
                HStack(spacing: 6) {
                    Icon(Glyph.approvals, size: 22)
                    if model.pendingApprovalCount > 0 {
                        Text("\(model.pendingApprovalCount)")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .padding(.horizontal, model.pendingApprovalCount > 0 ? 12 : 9)
                .frame(height: 40)
                .background(Theme.fill, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.pendingApprovalCount > 0 ? "\(model.pendingApprovalCount) tags waiting for approval" : "Tag approvals")
            .opacity(model.pendingApprovalCount > 0 ? 1 : 0.6)

            Spacer()
            SundaeMark(size: 30)
            Spacer()

            IconButton(glyph: Glyph.settings, label: "Settings", filled: true) { showSettings = true }
        }
        .foregroundStyle(.primary)
    }

    @ViewBuilder
    private var suggestionBlock: some View {
        if let suggestion = store.current {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 6) {
                    if store.justMarkedDone {
                        Icon(Glyph.approvals, weight: .fill, size: 18)
                            .foregroundStyle(Color.accentColor)
                            .transition(.scale.combined(with: .opacity))
                    }
                    Text(store.justMarkedDone ? "That's one for Sunday" : dayLine)
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
            .animation(.default, value: store.justMarkedDone)
            .id(suggestion.id)
            .transition(reduceMotion ? .opacity : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .opacity
            ))
            .accessibilityElement(children: .combine)
        } else {
            Text("Go make something worth posting.")
                .font(Theme.display(36))
        }
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
                    .disabled(store.isCurrentDone)
                }
            }
            Text(countdown)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Copy

    private var dayLine: String {
        let now = model.clock.now()
        let slot = Suggestion.TimeOfDay.current(for: now, calendar: model.clock.calendar)
        let day = model.clock.weekdayName(now)
        switch slot {
        case .morning: return "An idea for \(day) morning"
        case .afternoon: return "An idea for \(day) afternoon"
        case .evening: return "An idea for \(day) evening"
        case .any: return "An idea for \(day)"
        }
    }

    private var countdown: String {
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
