import SwiftUI

// The pieces every settings screen is built from: a page, grouped cards with hairlines between
// rows, and rows that are switches, radios, links, values or actions. Few words, clear states.
// Every row is the same height, a title with or without one short line under it.

enum SettingsRow {
    /// With 6 points above and below, every row is 60 tall, with a detail line or without.
    static let minHeight: CGFloat = 48
    static let verticalPadding: CGFloat = 6
}

/// A settings page: cream paper, a scroll of groups, the title in the bar.
struct SettingsScreen<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) { content }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 36)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A small caps label, then rows on one quiet card with hairlines between them.
/// `card: false` lays the content straight on the page, for a segmented choice.
struct SettingsGroup<Content: View>: View {
    var title: String? = nil
    var footer: String? = nil
    var card = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            if card {
                VStack(spacing: 0) {
                    Group(subviews: content) { rows in
                        ForEach(rows) { row in
                            if row.id != rows.first?.id {
                                Hairline()
                            }
                            row
                        }
                    }
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            } else {
                content
            }
            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }
}

/// Row padding and the soft press every row shares.
private struct SettingsRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowLabel(configuration: configuration)
    }

    private struct RowLabel: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .frame(maxWidth: .infinity, minHeight: SettingsRow.minHeight, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, SettingsRow.verticalPadding)
                .contentShape(Rectangle())
                .background(configuration.isPressed ? Color.primary.opacity(0.06) : .clear)
                .opacity(isEnabled ? 1 : 0.45)
        }
    }
}

/// Title and an optional line under it.
private struct RowText: View {
    let title: String
    var detail: String?
    var tint: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.body)
                .foregroundStyle(tint ?? .primary)
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.leading)
    }
}

/// A switch row. The whole row toggles; VoiceOver hears a plain switch.
struct SettingsToggle: View {
    let title: String
    var detail: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
            Haptics.light()
        } label: {
            HStack(spacing: 12) {
                RowText(title: title, detail: detail)
                Spacer(minLength: 8)
                SundaeSwitch(isOn: isOn)
            }
        }
        .buttonStyle(SettingsRowStyle())
        .accessibilityRepresentation {
            Toggle(isOn: $isOn) { Text(title) }
        }
    }
}

/// Sage when on, a quiet track when off, a white knob that slides.
struct SundaeSwitch: View {
    let isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? Color.accentColor : Color.primary.opacity(0.14))
            .frame(width: 50, height: 30)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                    .padding(2.5)
            }
            .animation(.snappy(duration: 0.22), value: isOn)
            .accessibilityHidden(true)
    }
}

/// One of a few choices. A ring that fills when chosen.
struct RadioRow: View {
    let title: String
    var detail: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            guard !isSelected else { return }
            withAnimation(.snappy(duration: 0.2)) { action() }
            Haptics.light()
        } label: {
            HStack(spacing: 12) {
                RowText(title: title, detail: detail)
                Spacer(minLength: 8)
                RadioMark(isOn: isSelected)
            }
        }
        .buttonStyle(SettingsRowStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct RadioMark: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            Circle().strokeBorder(isOn ? Color.accentColor : Color.primary.opacity(0.25), lineWidth: 1.5)
            if isOn {
                Circle().fill(Color.accentColor).padding(5).transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }
}

/// Two to four short options side by side. The chosen one is a raised pill that slides over.
struct SegmentedChoice<Value: Hashable>: View {
    /// Each option's value and its short label.
    let options: [(Value, String)]
    @Binding var selection: Value
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let value = options[index].0
                let label = options[index].1
                let isSelected = value == selection
                Button {
                    guard !isSelected else { return }
                    withAnimation(.snappy(duration: 0.28)) { selection = value }
                    Haptics.light()
                } label: {
                    Text(label)
                        .font(.subheadline.weight(isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Theme.surfaceRaised)
                                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                                    .matchedGeometryEffect(id: "choice", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.fill))
    }
}

/// A row that opens another screen, with its current value beside the chevron.
struct SettingsLinkRow<Destination: View>: View {
    let title: String
    var value: String? = nil
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 10) {
                RowText(title: title, detail: nil)
                Spacer(minLength: 8)
                if let value {
                    Text(value).font(.body).foregroundStyle(.secondary).lineLimit(1)
                }
                Icon(Glyph.chevronRight, weight: .bold, size: 13)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(SettingsRowStyle())
    }
}

/// A plain fact: "This device", "Jon's iPhone".
struct SettingsValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.body)
            Spacer(minLength: 8)
            Text(value).font(.body).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: SettingsRow.minHeight, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, SettingsRow.verticalPadding)
        .accessibilityElement(children: .combine)
    }
}

/// One of a few choices, from a menu: the title on the left, the current choice on the right.
struct SettingsMenuRow<Value: Hashable>: View {
    let title: String
    /// Each option's value and its label.
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(options.indices, id: \.self) { index in
                    Text(options[index].1).tag(options[index].0)
                }
            }
        } label: {
            HStack(spacing: 10) {
                Text(title).font(.body).foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(options.first { $0.0 == selection }?.1 ?? "")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: SettingsRow.minHeight, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, SettingsRow.verticalPadding)
            .contentShape(Rectangle())
        }
        .accessibilityValue(options.first { $0.0 == selection }?.1 ?? "")
    }
}

/// Something to do. Cherry red when it cannot be undone.
struct SettingsActionRow: View {
    let title: String
    var value: String? = nil
    var isDestructive = false
    let action: () -> Void

    var body: some View {
        Button(role: isDestructive ? ButtonRole.destructive : nil, action: action) {
            HStack(spacing: 10) {
                RowText(title: title, detail: nil, tint: isDestructive ? Theme.cherry : nil)
                Spacer(minLength: 8)
                if let value {
                    Text(value).font(.body).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(SettingsRowStyle())
    }
}

/// A labeled text field row: the label on the left, the field filling the rest.
struct SettingsFieldRow: View {
    let label: String
    @Binding var text: String
    var prompt: String = ""
    var multiline = false

    var body: some View {
        HStack(alignment: multiline ? .firstTextBaseline : .center, spacing: 12) {
            Text(label)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            if multiline {
                TextField(prompt, text: $text, axis: .vertical)
                    .lineLimit(2...5)
            } else {
                TextField(prompt, text: $text)
            }
        }
        .font(.body)
        .frame(maxWidth: .infinity, minHeight: SettingsRow.minHeight, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, SettingsRow.verticalPadding)
    }
}
