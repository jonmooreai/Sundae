import SwiftUI
import UIKit

/// Pinch a photo in a post to look closer. It lifts above everything else on screen and grows and
/// moves with both fingers. Lift one and the other moves it around at that size; put it back down
/// to pinch again. It settles back into its place when every finger lets go, the way photos do in
/// Messages and Instagram. One per window: `SundayShell` holds it and draws `PhotoZoomLayer`.
@MainActor
@Observable
final class PhotoZoom {
    struct Item: Equatable {
        let source: PhotoSource
        /// Where the photo sits, in the window's coordinates.
        let frame: CGRect
        let cornerRadius: CGFloat
    }

    static let maxScale: CGFloat = 5

    private(set) var item: Item?
    /// 1 at rest.
    private(set) var scale: CGFloat = 1
    /// Where the fingers came down, and where they are now, in the window's coordinates.
    private(set) var start: CGPoint = .zero
    private(set) var current: CGPoint = .zero
    private var isSettling = false

    var isZooming: Bool { item != nil }

    func begin(_ item: Item, at point: CGPoint) {
        guard self.item == nil else { return }
        self.item = item
        scale = 1
        start = point
        current = point
        isSettling = false
    }

    func change(scale: CGFloat, at point: CGPoint) {
        guard item != nil, !isSettling else { return }
        // A little give below 1, so pinching in feels like something, then back to size.
        self.scale = min(max(scale, 0.85), Self.maxScale)
        current = point
    }

    /// Back into place, then gone. Safe to call more than once.
    func end(reduceMotion: Bool) {
        guard item != nil, !isSettling else { return }
        isSettling = true
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.35, bounce: 0.15)) {
            scale = 1
            current = start
        } completion: {
            self.item = nil
            self.isSettling = false
        }
    }
}

/// Where a view is on screen, kept without redrawing anything: a feed that scrolls moves every
/// photo every frame, and only a pinch needs to know where one is.
@MainActor
final class ScreenFrame {
    var rect: CGRect = .zero
}

/// The lifted photo and the dimmed screen behind it, drawn over the whole window.
struct PhotoZoomLayer: View {
    @Environment(PhotoZoom.self) private var zoom

    var body: some View {
        if let item = zoom.item {
            let scale = zoom.scale
            // The point under the fingers stays under them as the photo grows and moves.
            let center = CGPoint(x: zoom.current.x + (item.frame.midX - zoom.start.x) * scale,
                                 y: zoom.current.y + (item.frame.midY - zoom.start.y) * scale)
            ZStack {
                Color.black.opacity(min(0.6, max(0, scale - 1) * 0.9))
                ZoomedPhoto(source: item.source, size: item.frame.size)
                    .frame(width: item.frame.width, height: item.frame.height)
                    .clipShape(RoundedRectangle(cornerRadius: item.cornerRadius, style: .continuous))
                    .scaleEffect(scale)
                    .position(center)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// The photo at the size it was on screen straight away (already in memory), then sharp enough
/// for a close look once a bigger copy is decoded.
private struct ZoomedPhoto: View {
    let source: PhotoSource
    let size: CGSize
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if case .placeholder(let seed) = source {
                PlaceholderPhoto(seed: seed)
            } else if let image {
                // Whole, as the carousel shows it.
                Image(uiImage: image).resizable().scaledToFit()
            }
        }
        .task(id: source) {
            if let quick = await ImageCache.image(for: source, size: PixelSize(size, scale: displayScale)) {
                image = quick
            }
            let close = CGSize(width: size.width * 3, height: size.height * 3)
            if let sharp = await ImageCache.image(for: source, size: PixelSize(close, scale: displayScale)),
               !Task.isCancelled {
                image = sharp
            }
        }
    }
}

extension View {
    /// Lets two fingers lift and zoom this photo. Does nothing where no `PhotoZoom` is provided.
    /// `frame` is read when a pinch starts: where the photo is on screen, in the window.
    func pinchToZoom(_ source: PhotoSource, frame: @escaping () -> CGRect, cornerRadius: CGFloat, zoom: PhotoZoom?,
                     reduceMotion: Bool) -> some View {
        modifier(PinchToZoom(source: source, frame: frame, cornerRadius: cornerRadius, zoom: zoom, reduceMotion: reduceMotion))
    }
}

private struct PinchToZoom: ViewModifier {
    let source: PhotoSource
    let frame: () -> CGRect
    let cornerRadius: CGFloat
    let zoom: PhotoZoom?
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if let zoom {
            content.gesture(PinchRecognizer(
                onBegin: { point in
                    zoom.begin(.init(source: source, frame: frame(), cornerRadius: cornerRadius), at: point)
                },
                onChange: { scale, point in zoom.change(scale: scale, at: point) },
                onEnd: { zoom.end(reduceMotion: reduceMotion) }
            ))
        } else {
            content
        }
    }
}

/// UIKit's own pinch: it reports where the fingers are as they move, which SwiftUI's does not,
/// and once it starts it keeps the photos from paging and the feed from scrolling under it. It
/// carries on while one finger stays down, which is what lets one finger pan a zoomed photo.
private struct PinchRecognizer: UIGestureRecognizerRepresentable {
    let onBegin: (CGPoint) -> Void
    let onChange: (CGFloat, CGPoint) -> Void
    let onEnd: () -> Void

    func makeUIGestureRecognizer(context: Context) -> SteadyPinch {
        SteadyPinch()
    }

    func handleUIGestureRecognizerAction(_ recognizer: SteadyPinch, context: Context) {
        let raw = context.converter.location(in: .global)
        switch recognizer.state {
        case .began:
            recognizer.start(at: raw)
            onBegin(raw)
            onChange(recognizer.zoom, raw)
        case .changed:
            let (scale, point) = recognizer.follow(raw)
            onChange(scale, point)
        case .ended, .cancelled, .failed:
            onEnd()
        default:
            break
        }
    }
}

/// A pinch that keeps the photo steady when a finger lifts or comes back down. UIKit reports the
/// middle of the fingers that are down, so that point leaps when their number changes, and its
/// scale needs two fingers. Here both carry on from where they were at that moment: with one
/// finger the photo keeps its size and follows it, and a second finger picks the pinch back up.
private final class SteadyPinch: UIPinchGestureRecognizer {
    private(set) var zoom: CGFloat = 1
    private var fingers = 0
    private var point: CGPoint = .zero
    /// Added to UIKit's point, so the photo stays put when the fingers change.
    private var shift: CGPoint = .zero
    /// The photo's size, and UIKit's scale, when the fingers last changed.
    private var zoomBase: CGFloat = 1
    private var scaleBase: CGFloat = 1

    func start(at raw: CGPoint) {
        fingers = numberOfTouches
        point = raw
        shift = .zero
        zoomBase = 1
        scaleBase = scale > 0 ? scale : 1
        zoom = 1
    }

    func follow(_ raw: CGPoint) -> (CGFloat, CGPoint) {
        if numberOfTouches != fingers {
            fingers = numberOfTouches
            shift = CGPoint(x: point.x - raw.x, y: point.y - raw.y)
            zoomBase = zoom
            scaleBase = scale > 0 ? scale : 1
        }
        point = CGPoint(x: raw.x + shift.x, y: raw.y + shift.y)
        if fingers >= 2 {
            zoom = min(max(zoomBase * scale / scaleBase, 0.85), PhotoZoom.maxScale)
        }
        return (zoom, point)
    }
}
