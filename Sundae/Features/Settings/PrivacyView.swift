import SwiftUI

/// The privacy details, read from Shared/privacy.json: the same file the server's /privacy page
/// is built from, so the app and the page can never say different things.
struct PrivacyPolicy: Decodable {
    struct Section: Decodable, Identifiable {
        let title: String
        let items: [String]
        var id: String { title }
    }

    let title: String
    let summary: String
    let updated: String
    let sections: [Section]

    static func bundled(_ bundle: Bundle = .main) -> PrivacyPolicy? {
        guard let url = bundle.url(forResource: "privacy", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PrivacyPolicy.self, from: data)
    }

    /// "October 26, 2026" from "2026-10-26".
    var updatedLabel: String {
        let parsed = try? Date.ISO8601FormatStyle().year().month().day().parse(updated)
        return parsed.map { $0.formatted(.dateTime.month(.wide).day().year()) } ?? updated
    }
}

/// What Sundae uses, what it never collects, and who sees what. In the app, so it can be read any
/// time without a browser or a website.
struct PrivacyView: View {
    private let policy = PrivacyPolicy.bundled()

    var body: some View {
        SettingsScreen(title: "Privacy") {
            if let policy {
                VStack(alignment: .leading, spacing: 6) {
                    Text(policy.summary)
                        .font(.body)
                    Text("Updated \(policy.updatedLabel)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)

                ForEach(policy.sections) { section in
                    SettingsGroup(title: section.title) {
                        ForEach(section.items, id: \.self) { item in
                            Text(item)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                        }
                    }
                }
            } else {
                Text("The privacy details could not be loaded. Reinstalling Sundae brings them back.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }
}

/// The same page from the sign-in screen, before there is an account or a navigation stack.
struct PrivacySheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PrivacyView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
