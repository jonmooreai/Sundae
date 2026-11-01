import PhotosUI
import SwiftUI
import UIKit

/// The system camera, full screen, for one photo. Hands back the picture taken, or nothing if the
/// person cancels. Nothing is saved to the library: a photo taken here is kept only if it is
/// posted, and like every photo it loses its location and camera details first (PhotoProcessor).
struct CameraCapture: UIViewControllerRepresentable {
    let onFinish: @MainActor (UIImage?) -> Void

    /// False on a device with no camera (the simulator, some iPads), so the option is not offered.
    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onFinish: @MainActor (UIImage?) -> Void

        init(onFinish: @escaping @MainActor (UIImage?) -> Void) {
            self.onFinish = onFinish
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}

/// Opens the camera over the current screen and adds the photo taken to this week's draft.
struct CameraCaptureCover: ViewModifier {
    @Binding var isPresented: Bool
    let compose: ComposeStore

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $isPresented) {
            CameraCapture { image in
                isPresented = false
                guard let image else { return }
                Task { await compose.addCameraPhoto(image) }
            }
            .ignoresSafeArea()
        }
    }
}

extension View {
    func cameraCapture(isPresented: Binding<Bool>, compose: ComposeStore) -> some View {
        modifier(CameraCaptureCover(isPresented: isPresented, compose: compose))
    }
}

/// The two ways to add photos from outside the week's grid: the Photos picker, for any album, and
/// the camera. Each adds straight to this week's draft.
struct PhotoSources: ViewModifier {
    let compose: ComposeStore
    @Binding var showsPicker: Bool
    @Binding var showsCamera: Bool
    @State private var items: [PhotosPickerItem] = []

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $showsPicker, selection: $items,
                          maxSelectionCount: max(1, compose.draft.remainingSlots),
                          selectionBehavior: .ordered, matching: .images, photoLibrary: .shared())
            .onChange(of: items) { _, picked in
                guard !picked.isEmpty else { return }
                Task {
                    await compose.importPickerItems(picked)
                    items = []
                }
            }
            .cameraCapture(isPresented: $showsCamera, compose: compose)
    }
}

extension View {
    func photoSources(compose: ComposeStore, showsPicker: Binding<Bool>, showsCamera: Binding<Bool>) -> some View {
        modifier(PhotoSources(compose: compose, showsPicker: showsPicker, showsCamera: showsCamera))
    }
}
