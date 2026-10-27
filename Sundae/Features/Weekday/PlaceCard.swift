import MapKit
import SwiftUI

/// The place behind a nearby idea, as a little card: the street outside it from Apple's Look
/// Around where Apple has it, how far it is, Apple Maps' own place card for its photos and hours,
/// and the way there. Everything here is looked up by the
/// place's public id or position, never by where the person is.
struct PlaceCard: View {
    let place: Suggestion.Place
    /// "6 min walk", "12 mi".
    let distance: String?
    /// False on short screens, where the picture would crowd the idea.
    var showsPicture = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lookup: PlaceLookup?
    @State private var placeCard: MKMapItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsPicture, let scene = lookup?.scene {
                LookAroundPreview(initialScene: scene, allowsNavigation: true, showsRoadLabels: false,
                                  pointsOfInterest: .excludingAll, badgePosition: .bottomTrailing)
                    .frame(height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding([.top, .horizontal], 8)
                    .accessibilityLabel("Look Around at \(place.name)")
                    .transition(.opacity)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                if let distance {
                    HStack(spacing: 5) {
                        Icon(Glyph.pin, weight: .fill, size: 13)
                            .foregroundStyle(Color.accentColor)
                        Text(distance)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            HStack(spacing: 8) {
                if let item = lookup?.mapItem {
                    Button {
                        placeCard = item
                    } label: {
                        HStack(spacing: 6) {
                            Icon(Glyph.photos, size: 15)
                            Text("Photos and hours")
                        }
                    }
                    .buttonStyle(.pill(.secondary, size: .small))
                    .transition(.opacity)
                }
                if let url = place.mapsURL {
                    Link(destination: url) {
                        HStack(spacing: 6) {
                            Icon(Glyph.pin, size: 15)
                            Text("Directions")
                        }
                    }
                    .buttonStyle(.pill(.secondary, size: .small))
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: lookup?.scene != nil)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: lookup?.mapItem != nil)
        .mapItemDetailSheet(item: $placeCard)
        .task(id: place) {
            lookup = nil
            lookup = await PlaceLookup.find(place)
        }
    }
}

/// Apple Maps' record of a place and Apple's street-level view of it, looked up once a place is on
/// screen. Read-only MapKit objects, made once and never changed, so they cross to the screen safely.
final class PlaceLookup: @unchecked Sendable {
    let mapItem: MKMapItem?
    let scene: MKLookAroundScene?

    private init(mapItem: MKMapItem?, scene: MKLookAroundScene?) {
        self.mapItem = mapItem
        self.scene = scene
    }

    /// By Apple's id when the idea has one; for ideas saved before that, by name close to where
    /// the place is. Nothing found is fine: the card shows what it has.
    nonisolated static func find(_ place: Suggestion.Place) async -> PlaceLookup {
        var item: MKMapItem?
        if let raw = place.mapsID, let id = MKMapItem.Identifier(rawValue: raw) {
            item = try? await MKMapItemRequest(mapItemIdentifier: id).mapItem
        }
        if item == nil, let latitude = place.latitude, let longitude = place.longitude {
            item = await search(place.name, near: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
        }
        var scene: MKLookAroundScene?
        if let item {
            scene = try? await MKLookAroundSceneRequest(mapItem: item).scene
        } else if let latitude = place.latitude, let longitude = place.longitude {
            scene = try? await MKLookAroundSceneRequest(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)).scene
        }
        return PlaceLookup(mapItem: item, scene: scene)
    }

    /// The result with the same name within a few hundred meters, or nothing.
    nonisolated private static func search(_ name: String, near coordinate: CLLocationCoordinate2D) async -> MKMapItem? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = name
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000)
        guard let response = try? await MKLocalSearch(request: request).start() else { return nil }
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return response.mapItems.first { item in
            guard item.name?.lowercased() == name.lowercased() else { return false }
            let there = item.placemark.coordinate
            return CLLocation(latitude: there.latitude, longitude: there.longitude).distance(from: here) < 300
        }
    }
}
