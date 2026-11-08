import Photos
import SwiftUI
import UIKit
import WidgetKit

/// The widgets as they will look on this phone: the same view the widget draws, at this
/// screen's real widget sizes, with today's real idea and this week's real photos.
struct WidgetGalleryView: View {
    @Environment(AppModel.self) private var model
    @State private var mode: WidgetSnapshot.Mode = .weekday
    @State private var photos: (thumbnails: [Data], count: Int) = ([], 0)
    @State private var photosArePosted = false
    /// The width the page has for the previews: on a narrow screen (an iPhone Duo closed, with
    /// its side strip) less than a real large widget, which then shows a little smaller.
    @State private var room: CGFloat = 0
    @State private var photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    var body: some View {
        let sizes = WidgetMetrics.current()
        let snapshot = WidgetSnapshotBuilder.snapshot(
            at: Date(), mode: mode, catalog: model.suggestions, shared: model.shared,
            photos: mode == .sunday ? photos : ([], 0), photosArePosted: photosArePosted)

        SettingsScreen(title: "Widgets") {
            SegmentedChoice(options: [(WidgetSnapshot.Mode.weekday, "Monday to Saturday"), (.sunday, "Sundae")],
                            selection: $mode)
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { room = $0 }

            let scale = room > 0 ? min(1, (room - 28) / sizes.large.width) : 1
            VStack(alignment: .leading, spacing: 18) {
                preview(snapshot, family: .systemSmall, size: sizes.small, scale: scale, label: "Small")
                preview(snapshot, family: .systemMedium, size: sizes.medium, scale: scale, label: "Wide")
                preview(snapshot, family: .systemLarge, size: sizes.large, scale: scale, label: "Large")
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .animation(.snappy(duration: 0.3), value: mode)

            Text(mode == .weekday ? "Today's idea, or a few to read through. Nearby ones open in Maps." : "A few photos from this week, and a nudge to post.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if mode == .sunday { photosNote }

            SettingsGroup(title: "Add it") {
                step(1, "Touch and hold your Home Screen.")
                step(2, "Tap Edit, then Add Widget.")
                step(3, "Find Sundae and pick a size.")
            }
        }
        .onAppear { mode = model.isSunday ? .sunday : .weekday }
        .task { await loadPhotos() }
    }

    /// One size, drawn exactly as on the Home Screen, made smaller as a whole only when the page
    /// is narrower than the widget, so its words and photos keep their places.
    private func preview(_ snapshot: WidgetSnapshot, family: WidgetFamily, size: CGSize, scale: CGFloat, label: String) -> some View {
        VStack(spacing: 8) {
            WidgetPreview(snapshot: snapshot, family: family, size: size)
                .scaleEffect(scale)
                .frame(width: size.width * scale, height: size.height * scale)
                .id("\(label)-\(snapshot.mode.rawValue)")
                .transition(.opacity)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: family == .systemSmall ? .leading : .center)
    }

    /// Photos are read on the phone with the app's own access. Asking here is optional.
    @ViewBuilder
    private var photosNote: some View {
        switch photoStatus {
        case .notDetermined:
            SettingsGroup(footer: "Read on this phone. Never uploaded.") {
                SettingsActionRow(title: "Show this week's photos") {
                    Task {
                        photoStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                        await loadPhotos()
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                }
            }
        case .denied, .restricted:
            SettingsGroup(footer: "Photos is off for Sundae, so on Sundae the widget shows a sundae.") {
                SettingsActionRow(title: "Open iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
        default:
            if photos.count == 0 {
                Text("No photos from this week yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 14, alignment: .leading)
            Text(text).font(.body)
        }
        .frame(maxWidth: .infinity, minHeight: SettingsRow.minHeight, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, SettingsRow.verticalPadding)
    }

    private func loadPhotos() async {
        photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let start = SundayClock().weekStart()
        // Posted this week: the post's photos, as the widget shows them. Otherwise a few from the library.
        let ids = model.shared.postedWeekStart == start ? model.shared.postedAssetIDs(forWeekStarting: start) : []
        let posted = await Task.detached(priority: .userInitiated) { WidgetPhotos.posted(ids, limit: 4) }.value
        if !posted.isEmpty {
            photos = (posted, ids.count)
            photosArePosted = true
            return
        }
        photos = await Task.detached(priority: .userInitiated) {
            WidgetPhotos.thisWeek(weekStart: start, until: Date(), limit: 4)
        }.value
        photosArePosted = false
    }
}

/// A widget preview at its real size, or smaller as a whole when the page is narrower than it
/// (an iPhone Duo closed, beside its side strip), so it is never cut off.
struct FittedWidgetPreview: View {
    let snapshot: WidgetSnapshot
    let family: WidgetFamily
    let size: CGSize

    var body: some View {
        GeometryReader { geo in
            let scale = min(1, max(0.1, (geo.size.width - 32) / size.width))
            WidgetPreview(snapshot: snapshot, family: family, size: size)
                .scaleEffect(scale)
                .frame(width: size.width * scale, height: size.height * scale)
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(height: size.height)
    }
}

/// One widget drawn exactly as on the Home Screen, for Settings and onboarding. Only a picture:
/// its buttons do nothing here.
struct WidgetPreview: View {
    let snapshot: WidgetSnapshot
    let family: WidgetFamily
    let size: CGSize

    var body: some View {
        SundaeWidgetView(snapshot: snapshot, family: family, margins: WidgetMetrics.margins)
            .frame(width: size.width, height: size.height)
            .background(WidgetPalette.paper)
            .clipShape(RoundedRectangle(cornerRadius: WidgetMetrics.cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
            .allowsHitTesting(false)
    }
}

/// Home Screen widget sizes and corners, by screen width. The numbers iOS uses on each phone.
enum WidgetMetrics {
    static let margins = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
    static let cornerRadius: CGFloat = 22

    @MainActor
    static func current() -> (small: CGSize, medium: CGSize, large: CGSize) {
        let screen = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
        let width = screen?.bounds.width ?? 393
        let height = screen?.bounds.height ?? 852
        let pair: (side: CGFloat, wide: CGFloat) = switch width {
        case 744...: (155, 342)          // iPad
        case 428...: (170, 364)          // Plus and Pro Max
        case 414...: (169, 360)
        case 400...: (162, 348)          // 16 Pro and 17
        case 390...: (158, 338)
        case 375...: height < 700 ? (148, 321) : (155, 329)
        default: (141, 292)
        }
        // The large widget is as wide as the wide one and a little over two squares tall.
        return (CGSize(width: pair.side, height: pair.side), CGSize(width: pair.wide, height: pair.side),
                CGSize(width: pair.wide, height: (pair.side * 2.24).rounded()))
    }
}
