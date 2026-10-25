import SwiftUI

/// Exactly what "ideas near you" does, before it does it. The points to get across, in order:
/// weekdays only, a neighborhood-sized area, no account attached, nothing on your photos.
struct LocationConsentSheet: View {
    let onAgree: () -> Void

    var body: some View {
        ConsentSheet(
            title: "Use your location for weekday ideas?",
            points: [
                .init(glyph: Glyph.calendar,
                      text: "Monday to Saturday only. When you open Sundae on a weekday, it looks once to pick today's idea from your neighborhood. On Sunday it never looks, whatever this is set to."),
                .init(glyph: Glyph.lock,
                      text: "Your exact spot stays on this phone. Only a neighborhood-sized area, about a kilometer across, is looked up, with no account attached."),
                .init(glyph: Glyph.block,
                      text: "Never on your photos, never shown to friends, never saved. Turn it off any time in Settings."),
            ],
            agreeTitle: "Use my location on weekdays",
            onAgree: onAgree
        )
    }
}
