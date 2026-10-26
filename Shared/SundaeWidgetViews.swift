import SwiftUI
import UIKit
import WidgetKit

/// The widget's own colors, so the widget does not depend on the app's theme. Same cream and
/// warm charcoal as the app, same sage and cherry.
enum WidgetPalette {
    static var paper: Color { dynamic((251, 248, 243), (25, 23, 20)) }
    static var tile: Color { dynamic((242, 237, 228), (43, 40, 38)) }
    static let sage = Color(red: 0.32, green: 0.44, blue: 0.36)
    static let cherry = Color(red: 0.86, green: 0.26, blue: 0.30)
    /// Ink on the sundae artwork, which is light in either theme.
    static let artInk = Color(red: 0.16, green: 0.14, blue: 0.12)

    private static func dynamic(_ light: (CGFloat, CGFloat, CGFloat), _ dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(uiColor: UIColor { trait in
            let c = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0 / 255, green: c.1 / 255, blue: c.2 / 255, alpha: 1)
        })
    }

    static func serif(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .serif) }
}

/// Monday to Saturday: today's idea and what else the week holds. Sunday: a few of this week's
/// photos and a nudge to post. One view for the widget and for the preview in Settings.
struct SundaeWidgetView: View {
    let snapshot: WidgetSnapshot
    let family: WidgetFamily
    /// The widget's content margins. Nil reads them from the widget environment.
    var margins: EdgeInsets? = nil

    @Environment(\.widgetContentMargins) private var systemMargins

    private var inset: EdgeInsets { margins ?? systemMargins }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(snapshot.mode == .sunday ? (snapshot.hasPosted ? "Sundae: your week is up" : "Sundae: post your week")
                 : "Sundae: \(snapshot.countdown.lowercased())")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.mode == .sunday ? "Sundae" : snapshot.countdown)
                    .font(.caption2.weight(.semibold))
                    .widgetAccentable()
                Text(snapshot.mode == .sunday ? (snapshot.hasPosted ? "Your week is up." : "Post your week.")
                     : (snapshot.idea?.text ?? "Go make something worth posting."))
                    .font(.caption)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemMedium:
            snapshot.mode == .sunday ? AnyView(sundayMedium) : AnyView(weekdayMedium)
        default:
            snapshot.mode == .sunday ? AnyView(sundaySmall) : AnyView(weekdaySmall)
        }
    }

    // MARK: Monday to Saturday

    private var weekdaySmall: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(snapshot.dayName.uppercased())
                        .font(.caption2.weight(.semibold))
                        .tracking(0.6)
                        .widgetAccentable()
                    Text(snapshot.countdown)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                CherryArt(size: 22)
            }
            Spacer(minLength: 6)
            Text(snapshot.idea?.text ?? "Go make something worth posting.")
                .font(WidgetPalette.serif(17))
                .lineLimit(4)
                .minimumScaleFactor(0.7)
            if let place = snapshot.idea?.place {
                PlaceLine(place: place).padding(.top, 5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(inset)
    }

    private var weekdayMedium: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(snapshot.dayName.uppercased()) · \(snapshot.countdown.uppercased())")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .widgetAccentable()
                Spacer(minLength: 6)
                Text(snapshot.idea?.text ?? "Go make something worth posting.")
                    .font(WidgetPalette.serif(19))
                    .lineLimit(4)
                    .minimumScaleFactor(0.7)
                if let place = snapshot.idea?.place {
                    PlaceLine(place: place).padding(.top, 5)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("LATER")
                        .font(.caption2.weight(.semibold))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    CherryArt(size: 20)
                }
                ForEach(snapshot.upcoming, id: \.self) { day in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(day.day)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(day.text)
                            .font(.caption)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(width: 112, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(inset)
    }

    // MARK: Sunday

    private var headline: String { snapshot.hasPosted ? "Your week is up." : "Post your week." }

    private var photoCountLine: String {
        switch snapshot.weekPhotoCount {
        case 0: snapshot.hasPosted ? "Edit until midnight." : "Pick from this week."
        case 1: "1 photo since Monday"
        default: "\(snapshot.weekPhotoCount) photos since Monday"
        }
    }

    @ViewBuilder
    private var sundaySmall: some View {
        if let first = snapshot.photos.last {
            // One photo, edge to edge, with the line over a soft shadow at the foot.
            ZStack(alignment: .bottomLeading) {
                WidgetPhoto(data: first)
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 1) {
                    Text(headline)
                        .font(WidgetPalette.serif(16))
                        .widgetAccentable()
                    Text(photoCountLine)
                        .font(.caption2)
                        .opacity(0.85)
                }
                .foregroundStyle(.white)
                .padding(EdgeInsets(top: 0, leading: inset.leading - 2, bottom: inset.bottom - 4, trailing: inset.trailing))
            }
            .overlay(alignment: .topTrailing) {
                CherryArt(size: 22)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    .padding(EdgeInsets(top: inset.top - 4, leading: 0, bottom: 0, trailing: inset.trailing - 4))
            }
        } else {
            ZStack(alignment: .topLeading) {
                SundaeArt()
                VStack(alignment: .leading, spacing: 1) {
                    Text("It's Sunday.")
                        .font(WidgetPalette.serif(18))
                        .widgetAccentable()
                    Text(headline)
                        .font(.caption)
                }
                .foregroundStyle(WidgetPalette.artInk)
                .padding(inset)
            }
        }
    }

    private var sundayMedium: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                CherryArt(size: 24)
                Spacer(minLength: 4)
                Text("It's Sunday.")
                    .font(WidgetPalette.serif(20))
                    .widgetAccentable()
                Text(headline)
                    .font(.subheadline.weight(.medium))
                Text(photoCountLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 118, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .leading)

            if snapshot.photos.isEmpty {
                SundaeArt()
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                HStack(spacing: 6) {
                    ForEach(Array(snapshot.photos.suffix(3).enumerated()), id: \.offset) { _, data in
                        WidgetPhoto(data: data)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
        .padding(inset)
    }
}

/// A photo that fills exactly the space it is given and never spills out of it.
struct WidgetPhoto: View {
    let data: Data

    var body: some View {
        Color.clear
            .overlay {
                if let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .widgetAccentedRenderingMode(.desaturated)
                        .scaledToFill()
                } else {
                    WidgetPalette.tile
                }
            }
            .clipped()
    }
}

/// The cherry from the app icon.
struct CherryArt: View {
    var size: CGFloat = 22

    var body: some View {
        Image("Cherry")
            .resizable()
            .widgetAccentedRenderingMode(.accentedDesaturated)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The whipped cream and cherry from the app icon, filling its space, cherry kept in view.
struct SundaeArt: View {
    var body: some View {
        Color.clear
            .overlay(alignment: .bottom) {
                Image("SundaeArt")
                    .resizable()
                    .widgetAccentedRenderingMode(.desaturated)
                    .scaledToFill()
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

/// "Tartine · 8 min walk" under a nearby idea.
struct PlaceLine: View {
    let place: Suggestion.Place

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "mappin")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WidgetPalette.sage)
            Text(line)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var line: String {
        if let minutes = place.walkMinutes { return "\(place.name) · \(minutes) min walk" }
        if let meters = place.distanceMeters {
            let distance = Measurement(value: meters, unit: UnitLength.meters)
                .formatted(.measurement(width: .abbreviated, usage: .road))
            return "\(place.name) · \(distance)"
        }
        return place.name
    }
}
