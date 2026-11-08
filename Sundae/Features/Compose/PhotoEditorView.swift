import CoreImage
import SwiftUI

/// Crop, turn, and the light and color of one photo, before it is posted. The photo sits on
/// cream with the tools under it: drag to move it in the frame, pinch to come closer, and each
/// slider starts in the middle, where the photo is as it was. Done keeps it; it can be opened
/// again and changed, or put back, until the week is posted.
struct PhotoEditorView: View {
    let photo: DraftPhoto
    /// The photo's pixels before any edits.
    let load: () async -> Data?
    /// The edits and the finished picture, or nil for the photo put back as it was.
    let onDone: (PhotoEdits, ProcessedPhoto?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Tool: CaseIterable, Identifiable {
        case crop, brightness, contrast, saturation, warmth
        var id: Self { self }

        var title: String {
            switch self {
            case .crop: "Crop"
            case .brightness: "Brightness"
            case .contrast: "Contrast"
            case .saturation: "Saturation"
            case .warmth: "Warmth"
            }
        }

        var glyph: Ph {
            switch self {
            case .crop: Glyph.crop
            case .brightness: Glyph.brightness
            case .contrast: Glyph.contrast
            case .saturation: Glyph.saturation
            case .warmth: Glyph.warmth
            }
        }
    }

    /// What changes the picture itself; moving the crop only moves it.
    private struct Look: Equatable {
        var quarterTurns: Int
        var straighten: Double
        var brightness: Double
        var contrast: Double
        var saturation: Double
        var warmth: Double

        init(_ edits: PhotoEdits) {
            quarterTurns = edits.quarterTurns
            straighten = edits.straighten
            brightness = edits.brightness
            contrast = edits.contrast
            saturation = edits.saturation
            warmth = edits.warmth
        }
    }

    @State private var edits = PhotoEdits()
    @State private var tool: Tool = .crop
    @State private var data: Data?
    @State private var base: CIImage?
    @State private var preview: UIImage?
    @State private var failed = false
    @State private var isSaving = false
    @State private var renderFailed = false
    @State private var dragStart: PhotoEdits?
    @State private var zoomStart: Double?

    private var isMoving: Bool { dragStart != nil || zoomStart != nil }

    var body: some View {
        VStack(spacing: 0) {
            header
            canvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            controls
                .frame(height: 132)
                .padding(.horizontal, Theme.pagePadding)
            tools
        }
        .frame(maxWidth: Theme.columnWidth)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
        .task { await start() }
        .onChange(of: Look(edits)) { _, _ in redraw() }
        .alert("We couldn't keep those changes", isPresented: $renderFailed) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your photo is as it was. Give it another try.")
        }
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            Text("Edit photo")
                .font(Theme.display(22))
            HStack {
                Button("Cancel") { dismiss() }
                    .textButtonTint()
                Spacer()
                Button {
                    Task { await finish() }
                } label: {
                    ZStack {
                        Text("Done").opacity(isSaving ? 0 : 1)
                        if isSaving { ProgressView().tint(.white) }
                    }
                }
                .buttonStyle(.pill(.primary, size: .small))
                .disabled(base == nil || isSaving)
            }
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.vertical, 10)
    }

    // MARK: - Canvas

    @ViewBuilder
    private var canvas: some View {
        if let preview {
            GeometryReader { geo in
                let room = CGSize(width: max(1, geo.size.width - Theme.pagePadding * 2), height: max(1, geo.size.height - 24))
                let layout = Self.layout(image: preview.size, edits: edits, room: room)
                let placed = Image(uiImage: preview)
                    .resizable()
                    .frame(width: layout.shown.width, height: layout.shown.height)
                    .offset(x: -CGFloat(edits.offsetX) * layout.slack.width, y: -CGFloat(edits.offsetY) * layout.slack.height)
                ZStack {
                    // The rest of the photo, faint, beyond the frame, while cropping.
                    placed.opacity(tool == .crop ? 0.22 : 0)
                    placed
                        .frame(width: layout.frame.width, height: layout.frame.height)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .overlay {
                            if tool == .crop {
                                ThirdsGrid().opacity(isMoving ? 1 : 0.55)
                            }
                        }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .contentShape(Rectangle())
                .gesture(moveGesture(slack: layout.slack).simultaneously(with: zoomGesture))
                .onTapGesture(count: 2) {
                    withAnimation(reduceMotion ? nil : .snappy) {
                        edits.zoom = 1
                        edits.offsetX = 0
                        edits.offsetY = 0
                    }
                }
                .animation(reduceMotion || isMoving ? nil : .snappy(duration: 0.3), value: edits.aspect)
                .accessibilityElement()
                .accessibilityLabel("The photo. Drag to move it in the frame, pinch to come closer.")
            }
        } else if failed {
            EmptyState(glyph: Glyph.photos, message: "We couldn't open this photo. Check your connection and try again.")
        } else {
            ProgressView()
        }
    }

    /// Where the photo sits: the frame of the chosen shape fitted to the room, the photo just
    /// covering it at zoom 1 and larger past that, and how far it can move each way.
    private static func layout(image: CGSize, edits: PhotoEdits, room: CGSize) -> (frame: CGSize, shown: CGSize, slack: CGSize) {
        guard image.width > 0, image.height > 0 else { return (room, room, .zero) }
        let shape = edits.aspect.ratio ?? image.width / image.height
        var frame = room
        if room.width / room.height > shape { frame.width = room.height * shape } else { frame.height = room.width / shape }
        let cover = max(frame.width / image.width, frame.height / image.height) * CGFloat(max(1, edits.zoom))
        let shown = CGSize(width: image.width * cover, height: image.height * cover)
        let slack = CGSize(width: max(0, (shown.width - frame.width) / 2), height: max(0, (shown.height - frame.height) / 2))
        return (frame, shown, slack)
    }

    /// Dragging moves the photo with the finger; the crop is what stays in the frame.
    private func moveGesture(slack: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let start = dragStart ?? edits
                dragStart = start
                if slack.width > 0 { edits.offsetX = PhotoEditing.clamp(start.offsetX - Double(value.translation.width / slack.width)) }
                if slack.height > 0 { edits.offsetY = PhotoEditing.clamp(start.offsetY - Double(value.translation.height / slack.height)) }
            }
            .onEnded { _ in dragStart = nil }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = zoomStart ?? edits.zoom
                zoomStart = start
                edits.zoom = min(5, max(1, start * Double(value.magnification)))
            }
            .onEnded { _ in zoomStart = nil }
    }

    // MARK: - Controls

    @ViewBuilder
    private var controls: some View {
        switch tool {
        case .crop:
            VStack(spacing: 12) {
                straightenSlider
                HStack(spacing: 8) {
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(PhotoEdits.Aspect.allCases, id: \.self) { aspect in
                                chip(aspect.label, isOn: edits.aspect == aspect) {
                                    withAnimation(reduceMotion ? nil : .snappy) {
                                        edits.aspect = aspect
                                        edits.zoom = 1
                                        edits.offsetX = 0
                                        edits.offsetY = 0
                                    }
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    Button {
                        Haptics.light()
                        edits.quarterTurns = (edits.quarterTurns + 1) % 4
                    } label: {
                        Icon(Glyph.rotate, size: 20)
                            .frame(width: 40, height: 40)
                            .background(Theme.fill, in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Turn a quarter")
                }
                HStack {
                    Spacer()
                    Button("Start over") {
                        withAnimation(reduceMotion ? nil : .snappy) { edits = PhotoEdits() }
                    }
                    .font(.subheadline)
                    .textButtonTint()
                    .disabled(edits.isUntouched)
                }
            }
            .padding(.top, 8)
        default:
            VStack(spacing: 8) {
                HStack {
                    Text(tool.title)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if value(for: tool) != 0 {
                        Button("Reset") { setValue(0, for: tool) }
                            .font(.subheadline)
                            .textButtonTint()
                    }
                    Text(Self.label(value(for: tool)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(minWidth: 36, alignment: .trailing)
                }
                Slider(value: Binding(get: { value(for: tool) }, set: { setValue($0, for: tool) }), in: -1...1)
                    .tint(Color.accentColor)
                    .accessibilityLabel(tool.title)
                    .accessibilityValue(Self.label(value(for: tool)))
            }
            .padding(.top, 18)
        }
    }

    /// A fine turn, from the middle: right turns the photo clockwise, a few degrees at most, in
    /// half degrees. Back at the middle it settles there with a tap of feedback.
    private var straightenSlider: some View {
        HStack(spacing: 10) {
            Text("Straighten")
                .font(.subheadline.weight(.semibold))
            Slider(value: Binding(get: { edits.straighten }, set: { raw in
                let value = abs(raw) < 0.3 ? 0 : raw
                if value == 0, edits.straighten != 0 { Haptics.light() }
                edits.straighten = value
            }), in: PhotoEdits.straightenRange, step: 0.5)
            .tint(Color.accentColor)
            .accessibilityLabel("Straighten")
            .accessibilityValue(Self.degrees(edits.straighten))
            Text(Self.degrees(edits.straighten))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 44, alignment: .trailing)
                .onTapGesture(count: 2) { edits.straighten = 0 }
        }
    }

    /// "+2.5°", "0°", "-4°".
    private static func degrees(_ value: Double) -> String {
        let rounded = (value * 2).rounded() / 2
        let number = rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", abs(rounded))
        if rounded > 0 { return "+\(number)\u{00B0}" }
        if rounded < 0 { return rounded == rounded.rounded() ? "\(number)\u{00B0}" : "-\(number)\u{00B0}" }
        return "0\u{00B0}"
    }

    private func chip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 13)
                .frame(height: 34)
                .background(isOn ? Theme.fill : .clear, in: Capsule())
                .foregroundStyle(isOn ? .primary : .secondary)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// "+25", "0", "-40".
    private static func label(_ value: Double) -> String {
        let percent = Int((value * 100).rounded())
        return percent > 0 ? "+\(percent)" : "\(percent)"
    }

    private func value(for tool: Tool) -> Double {
        switch tool {
        case .crop: 0
        case .brightness: edits.brightness
        case .contrast: edits.contrast
        case .saturation: edits.saturation
        case .warmth: edits.warmth
        }
    }

    /// Close to the middle settles on the middle, so the photo as it was is easy to find again.
    private func setValue(_ raw: Double, for tool: Tool) {
        let value = abs(raw) < 0.04 ? 0 : raw
        if value == 0, self.value(for: tool) != 0 { Haptics.light() }
        switch tool {
        case .crop: break
        case .brightness: edits.brightness = value
        case .contrast: edits.contrast = value
        case .saturation: edits.saturation = value
        case .warmth: edits.warmth = value
        }
    }

    private func isChanged(_ tool: Tool) -> Bool {
        switch tool {
        case .crop: edits.quarterTurns != 0 || edits.straighten != 0 || edits.aspect != .original || edits.zoom != 1 || edits.offsetX != 0 || edits.offsetY != 0
        default: value(for: tool) != 0
        }
    }

    // MARK: - Tools

    private var tools: some View {
        HStack(spacing: 0) {
            ForEach(Tool.allCases) { item in
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { tool = item }
                } label: {
                    VStack(spacing: 4) {
                        Icon(item.glyph, weight: tool == item ? .fill : .regular, size: 22)
                        Text(item.title)
                            .font(.caption2.weight(tool == item ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 4, height: 4)
                            .opacity(isChanged(item) ? 1 : 0)
                    }
                    .foregroundStyle(tool == item ? .primary : .secondary)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isChanged(item) ? "\(item.title), changed" : item.title)
                .accessibilityAddTraits(tool == item ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }

    // MARK: - Work

    private func start() async {
        edits = photo.edits ?? PhotoEdits()
        guard let loaded = await load(), let image = PhotoEditing.previewBase(loaded) else {
            failed = true
            return
        }
        data = loaded
        base = image
        redraw()
    }

    private func redraw() {
        guard let base else { return }
        preview = PhotoEditing.preview(base, edits)
    }

    private func finish() async {
        guard let data else { return }
        if edits.isUntouched {
            onDone(edits, nil)
            dismiss()
            return
        }
        isSaving = true
        let rendered = await PhotoEditing.renderInBackground(data, edits)
        isSaving = false
        guard let rendered else {
            renderFailed = true
            return
        }
        Haptics.light()
        onDone(edits, rendered)
        dismiss()
    }
}

/// The lines that split a crop into thirds, for lining things up.
private struct ThirdsGrid: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                for i in 1...2 {
                    let x = geo.size.width * CGFloat(i) / 3
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geo.size.height))
                    let y = geo.size.height * CGFloat(i) / 3
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
            }
            .stroke(Color.white.opacity(0.8), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
