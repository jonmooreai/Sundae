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
    @State private var photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    var body: some View {
        let sizes = WidgetMetrics.current()
        let snapshot = WidgetSnapshotBuilder.snapshot(
            at: Date(), mode: mode, catalog: model.suggestions, shared: model.shared,
            photos: mode == .sunday ? photos : ([], 0))

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Picker("Day", selection: $mode.animation(.snappy(duration: 0.3))) {
                    Text("Monday to Saturday").tag(WidgetSnapshot.Mode.weekday)
                    Text("Sunday").tag(WidgetSnapshot.Mode.sunday)
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 18) {
                    preview(snapshot, family: .systemMedium, size: sizes.medium, label: "Wide")
                    preview(snapshot, family: .systemSmall, size: sizes.small, label: "Small")
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 30, style: .continuous))

                Text(mode == .weekday
                     ? "Monday to Saturday it shows today's idea, the same one the app shows, and what the next days hold. Ideas near you appear here too when that is on."
                     : "On Sunday it shows a few photos you took this week and a nudge to post. Once your week is up, it says so.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if mode == .sunday { photosNote }

                steps
            }
            .padding(Theme.pagePadding)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle("Widgets")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { mode = model.isSunday ? .sunday : .weekday }
        .task { await loadPhotos() }
    }

    private func preview(_ snapshot: WidgetSnapshot, family: WidgetFamily, size: CGSize, label: String) -> some View {
        VStack(spacing: 8) {
            SundaeWidgetView(snapshot: snapshot, family: family, margins: WidgetMetrics.margins)
                .frame(width: size.width, height: size.height)
                .background(WidgetPalette.paper)
                .clipShape(RoundedRectangle(cornerRadius: WidgetMetrics.cornerRadius, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                .id("\(label)-\(snapshot.mode.rawValue)")
                .transition(.opacity)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: family == .systemSmall ? .leading : .center)
    }

    /// Photos are read on the phone with the app's own access. Asking here is optional and says why.
    @ViewBuilder
    private var photosNote: some View {
        switch photoStatus {
        case .notDetermined:
            VStack(alignment: .leading, spacing: 10) {
                Text("The Sunday widget can show a few photos you took this week. It reads them on this phone with the same Photos access as posting. Nothing is copied or uploaded.")
                    .font(.subheadline)
                Button("Allow Photos") {
                    Task {
                        photoStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                        await loadPhotos()
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                }
                .buttonStyle(.pill(.secondary, size: .small))
            }
            .card(padding: 14)
        case .denied, .restricted:
            VStack(alignment: .leading, spacing: 8) {
                Text("Photos is off for Sundae, so the Sunday widget shows the sundae instead of your week.")
                    .font(.subheadline)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("Open iOS Settings", destination: url)
                        .font(.subheadline.weight(.medium))
                        .textButtonTint()
                }
            }
            .card(padding: 14)
        default:
            if photos.count == 0 {
                Text("No photos from this week yet. Take a few and they show up here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add it")
                .font(.headline)
            step(1, "Touch and hold an empty spot on your Home Screen until the apps jiggle.")
            step(2, "Tap Edit in the top corner, then Add Widget.")
            step(3, "Search for Sundae, swipe to the size you want, and tap Add Widget.")
            Text("It works on iPhone and iPad Home Screens, in StandBy, and on the Lock Screen as a one-line version.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 16, alignment: .leading)
            Text(text).font(.subheadline)
        }
    }

    private func loadPhotos() async {
        photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let start = SundayClock().weekStart()
        photos = await Task.detached(priority: .userInitiated) {
            WidgetPhotos.thisWeek(weekStart: start, until: Date())
        }.value
    }
}

/// Home Screen widget sizes and corners, by screen width. The numbers iOS uses on each phone.
enum WidgetMetrics {
    static let margins = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
    static let cornerRadius: CGFloat = 22

    @MainActor
    static func current() -> (small: CGSize, medium: CGSize) {
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
        return (CGSize(width: pair.side, height: pair.side), CGSize(width: pair.wide, height: pair.side))
    }
}
