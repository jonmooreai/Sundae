import SwiftUI

/// The privacy details, read from Shared/privacy.json: the same file the server's /privacy page is
/// built from, so the app and the page can never say different things.
struct PrivacyPolicy: Decodable, Sendable {
    struct Section: Decodable, Identifiable, Sendable {
        let title: String
        let items: [String]
        var id: String { title }
    }

    let app: String
    let title: String
    let summary: String
    let updated: String
    let sections: [Section]

    nonisolated static func bundled(_ bundle: Bundle = .main) -> PrivacyPolicy? {
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

/// What the app uses, what it never collects, and how to delete it all. In the app, so it can be
/// read any time without a browser.
struct PrivacyView: View {
    private let policy = PrivacyPolicy.bundled()

    var body: some View {
        List {
            if let policy {
                Section {
                    Text(policy.summary)
                    Text("Updated \(policy.updatedLabel)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(policy.sections) { section in
                    Section(section.title) {
                        ForEach(section.items, id: \.self) { item in
                            Text(item)
                        }
                    }
                }
            } else {
                Text("The privacy details could not be loaded. Reinstalling the app brings them back.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Privacy")
    }
}
