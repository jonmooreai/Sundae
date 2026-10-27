import AVFoundation
import CoreMotion
import Observation
import SwiftUI
import UIKit

/// The app's mark: the felt cherry from the app icon. A picture, not a drawing, so it keeps its
/// wool texture; the image is square with the cherry centered, so any size frames it the same.
struct CherryMark: View {
    var size: CGFloat = 32

    var body: some View {
        Image("Cherry")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The cherry on the weekday screen, leaning as the phone tilts, like a cherry sitting on a plate
/// you are holding. Still with Reduce Motion on.
struct TiltingCherry: View {
    var size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var tilt = DeviceTilt()

    var body: some View {
        let lean = reduceMotion ? 0 : tilt.lean
        CherryMark(size: size)
            .rotationEffect(.degrees(lean * 16), anchor: .bottom)
            .offset(x: CGFloat(lean) * size * 0.14)
            // A loose spring, so it settles with a little sway instead of tracking the sensor exactly.
            .animation(.interpolatingSpring(stiffness: 120, damping: 9), value: lean)
            .onAppear { update() }
            .onDisappear { tilt.stop() }
            .onChange(of: scenePhase) { _, _ in update() }
            .onChange(of: reduceMotion) { _, _ in update() }
    }

    private func update() {
        if scenePhase == .active, !reduceMotion { tilt.start() } else { tilt.stop() }
    }
}

/// How far the phone leans left or right, from -1 to 1. Read from the motion sensors only while
/// the cherry is on screen; it never leaves the phone, is never kept, and needs no permission.
@MainActor
@Observable
final class DeviceTilt {
    private(set) var lean: Double = 0
    private let motion = CMMotionManager()

    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1 / 30
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let side = data?.gravity.x else { return }
            MainActor.assumeIsolated { self?.follow(side) }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
    }

    /// Smoothed, and only updated when it moves enough to see, so the screen redraws rarely. The
    /// sensor measures along the phone, not the screen, so it only counts held upright; turned on
    /// its side, the cherry settles straight.
    private func follow(_ side: Double) {
        let scene = UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        let along: Double = switch scene?.effectiveGeometry.interfaceOrientation {
        case .portrait?: side
        case .portraitUpsideDown?: -side
        default: 0
        }
        let next = lean * 0.8 + max(-1, min(1, along)) * 0.2
        if abs(next - lean) > 0.004 { lean = next }
    }
}

/// The cherry's little squeak (CherrySqueak.m4a). It plays even with the ring switch on silent,
/// softly, and mixes with anything already playing instead of stopping it.
@MainActor
enum CherrySound {
    private static let player: AVAudioPlayer? = {
        guard let url = Bundle.main.url(forResource: "CherrySqueak", withExtension: "m4a"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.volume = 0.5
        player.prepareToPlay()
        return player
    }()

    static func play() {
        let session = AVAudioSession.sharedInstance()
        if session.category != .playback || !session.categoryOptions.contains(.mixWithOthers) {
            try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        }
        guard let player else { return }
        player.currentTime = 0
        player.play()
    }
}

/// Tap the cherry and it wobbles, with a squeak. Nothing happens otherwise; that is the point.
/// With Reduce Motion on it stays still and only the squeak and the tap are felt.
private struct WobbleOnTap: ViewModifier {
    @State private var taps = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: 0.0, trigger: taps) { view, angle in
                view.rotationEffect(.degrees(angle), anchor: .bottom)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(-12, duration: 0.10)
                    CubicKeyframe(9, duration: 0.12)
                    CubicKeyframe(-5, duration: 0.10)
                    CubicKeyframe(2, duration: 0.08)
                    CubicKeyframe(0, duration: 0.10)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                Haptics.light()
                CherrySound.play()
                guard !reduceMotion else { return }
                taps += 1
            }
    }
}

extension View {
    func wobbleOnTap() -> some View { modifier(WobbleOnTap()) }
}

/// Three fanned, rounded photo cards. Used where the app asks for photos.
struct PhotoStackIcon: View {
    var size: CGFloat = 72

    var body: some View {
        ZStack {
            card.rotationEffect(.degrees(-10)).offset(x: -size * 0.16, y: size * 0.04)
            card.rotationEffect(.degrees(8)).offset(x: size * 0.16, y: size * 0.02)
            card.overlay {
                Icon(Glyph.photos, size: size * 0.36)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size * 1.5, height: size * 1.2)
        .accessibilityHidden(true)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
            .fill(Theme.surfaceRaised)
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            }
            .frame(width: size * 0.78, height: size * 0.98)
            .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
    }
}
