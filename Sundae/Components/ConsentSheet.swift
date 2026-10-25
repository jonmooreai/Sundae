import SwiftUI
import PhosphorSwift

/// A plain-words permission screen: what is about to happen, in a few points, then two buttons.
/// It always comes before the system prompt, so iOS never asks first.
struct ConsentSheet: View {
    struct Point {
        let glyph: Ph
        let text: String
    }

    let title: String
    let points: [Point]
    let agreeTitle: String
    let onAgree: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(title)
                        .font(Theme.display(28))
                        .padding(.top, 24)
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                            HStack(alignment: .top, spacing: 12) {
                                Icon(point.glyph, weight: .bold, size: 18)
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 28)
                                Text(point.text)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            VStack(spacing: 8) {
                PrimaryButton(title: agreeTitle) {
                    onAgree()
                    dismiss()
                }
                Button("Not now") { dismiss() }
                    .buttonStyle(.pill(.quiet, fullWidth: true))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(Theme.background)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
    }
}
