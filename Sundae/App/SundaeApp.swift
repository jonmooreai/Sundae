import SwiftUI

@main
struct SundaeApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(model.appearance.colorScheme)
                .task { await model.start() }
                // A Maps button on the large widget comes through here and goes straight on to
                // Apple Maps. Nothing else is opened from a link.
                .onOpenURL { link in
                    if let maps = WidgetSnapshot.mapsDestination(from: link) { openURL(maps) }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await model.becameActive() }
                    }
                }
        }
    }
}
