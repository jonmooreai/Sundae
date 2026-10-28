import SwiftUI

/// The signed-in home: the example notes, saved to the account on the server. Replace it with the
/// app's own first screen; it shows the whole path from a tap to the database and back.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var draft = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                composer
                List {
                    ForEach(model.notes) { note in
                        Text(note.text)
                            .listRowBackground(Color.clear)
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { model.notes[$0].id }
                        Task { await model.deleteNotes(ids) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .overlay { emptyState }
                .refreshable { await model.loadNotes() }
            }
            .background(Theme.background)
            .navigationTitle("Tally")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                TextField("Write a note", text: $draft)
                    .submitLabel(.done)
                    .onSubmit { Task { await add() } }
                    .padding(12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                Button("Add") { Task { await add() } }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .disabled(isSaving || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(Theme.danger)
            }
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.vertical, 10)
    }

    /// In the middle of the list's space, on the screen's own background.
    @ViewBuilder
    private var emptyState: some View {
        if model.notes.isEmpty {
            if model.loadFailed {
                ContentUnavailableView {
                    Label("Couldn't load your notes", systemImage: "wifi.slash")
                } description: {
                    Text("Check your connection, then pull to try again.")
                }
            } else {
                ContentUnavailableView("No notes yet", systemImage: "note.text",
                                       description: Text("Anything you write here is saved to your account."))
            }
        }
    }

    private func add() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        do {
            try await model.addNote(text)
            draft = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
