import SwiftUI

@main
struct TallyApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(Self.forcedScheme)
                .task { await model.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await model.becameActive() }
                    }
                }
        }
    }

    /// `-appearance dark` or `-appearance light` as a launch argument, for screenshots of either.
    private static var forcedScheme: ColorScheme? {
        switch UserDefaults.standard.string(forKey: "appearance") {
        case "dark": .dark
        case "light": .light
        default: nil
        }
    }
}
