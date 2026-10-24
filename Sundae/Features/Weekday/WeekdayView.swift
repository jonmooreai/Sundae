import SwiftUI

/// The screen people see most. One suggestion, large type, nowhere else to go.
/// It should look like a nice postcard, not an error state.
struct WeekdayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var showApprovals = false
    @State private var showSettings = false

    private var store: WeekdayStore { model.weekday }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 24)
                suggestionBlock
                    .frame(maxWidth: 560, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                    Image(systemName: Icon.approvals)
                    if model.pendingApprovalCount > 0 {
                        Text("\(model.pendingApprovalCount)")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .padding(.horizontal, model.pendingApprovalCount > 0 ? 12 : 10)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
            }
            .accessibilityLabel(model.pendingApprovalCount > 0 ? "\(model.pendingApprovalCount) tags waiting for approval" : "Tag approvals")
            .opacity(model.pendingApprovalCount > 0 ? 1 : 0.6)

            Spacer()

            Button {
                showSettings = true
            } label: {
                Image(systemName: Icon.settings)
                    .padding(10)
                    .background(.regularMaterial, in: Circle())
            }
            .accessibilityLabel("Settings")
        }
        .foregroundStyle(.primary)
    }

    @ViewBuilder
    private var suggestionBlock: some View {
        if let suggestion = store.current {
            VStack(alignment: .leading, spacing: 18) {
                Text(store.justMarkedDone ? "That's one for Sunday" : dayLine)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.8)
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
                    store.shuffle(clock: model.clock)
                } label: {
                    Label(store.justMarkedDone ? "Another idea" : "Shuffle", systemImage: Icon.shuffle)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                if !store.justMarkedDone {
                    Button {
                        Task { await store.markDone(clock: model.clock) }
                    } label: {
                        Label("Done", systemImage: Icon.done)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
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
        case .weekday(let days) where days == 1: return "Sunday is tomorrow"
        case .weekday(let days): return "\(days) days until Sunday"
        }
    }

}
