import SwiftUI

/// Which screen the app is on: waiting for the session, signing in, choosing a username, or in.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if model.isRestoringSession {
                ProgressView()
            } else if model.isSignedIn {
                HomeView()
            } else if model.signupTicket != nil {
                UsernameView()
            } else {
                SignInView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: model.isSignedIn)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: model.signupTicket)
    }
}
