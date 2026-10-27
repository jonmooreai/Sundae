import MapKit
import SwiftUI

/// The place behind a nearby idea, as a little card: a small map with the place pinned, how far
/// it is, Apple Maps' own place card for its photos and hours, and the way there. Everything here
/// is looked up by the place's public id or position, never by where the person is.
struct PlaceCard: View {
    let place: Suggestion.Place
    /// "6 min walk", "12 mi".
    let distance: String?
    /// False on short screens, where the picture would crowd the idea.
    var showsPicture = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @State private var lookup: PlaceLookup?
    @State private var placeCard: MKMapItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // A map, not Look Around: the street view at a place's position too often shows the
            // house next door.
            if showsPicture, let coordinate {
                map(of: coordinate)
                    .frame(height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding([.top, .horizontal], 8)
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
        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: lookup?.mapItem != nil)
        .mapItemDetailSheet(item: $placeCard)
        .task(id: place) {
            lookup = nil
            lookup = await PlaceLookup.find(place)
        }
    }
}

extension PlaceCard {
    private var coordinate: CLLocationCoordinate2D? {
        guard let latitude = place.latitude, let longitude = place.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// The streets around the place with a pin on it. It stays still, so the screen scrolls past
    /// it; a tap opens Apple's place card, or Maps.
    private func map(of coordinate: CLLocationCoordinate2D) -> some View {
        Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 600, longitudinalMeters: 600)),
            interactionModes: []) {
            Marker(place.name, coordinate: coordinate)
                .tint(Color.accentColor)
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .contentShape(Rectangle())
        .onTapGesture {
            if let item = lookup?.mapItem {
                placeCard = item
            } else if let url = place.mapsURL {
                openURL(url)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Map showing \(place.name)")
        .accessibilityAddTraits(.isButton)
    }
}

/// Apple Maps' record of a place, looked up once a place is on screen, for its place card. A
/// read-only MapKit object, made once and never changed, so it crosses to the screen safely.
final class PlaceLookup: @unchecked Sendable {
    let mapItem: MKMapItem?

    private init(mapItem: MKMapItem?) {
        self.mapItem = mapItem
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
        return PlaceLookup(mapItem: item)
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
