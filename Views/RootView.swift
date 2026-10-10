import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \.updatedAt, order: .reverse) private var projects: [SongProject]

    @State private var selectedProjectID: UUID?

    private var selectedProject: SongProject? {
        guard let selectedProjectID else { return nil }
        return projects.first(where: { $0.id == selectedProjectID })
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedProjectID) {
                Section("Songs") {
                    ForEach(projects) { project in
                        NavigationLink(value: project.id) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(project.title)
                                    .font(.headline)
                                Text(project.genre.isEmpty ? "No genre yet" : project.genre)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let project = projects.first(where: { $0.id == id }) {
                    SongEditorView(project: project)
                }
            }
            .navigationTitle("Anchord")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        let project = SongProject()
                        modelContext.insert(project)
                        selectedProjectID = project.id
                    } label: {
                        Label("New Song", systemImage: "plus")
                    }
                }
            }
        } detail: {
            if let selectedProject {
                SongEditorView(project: selectedProject)
            } else {
                ContentUnavailableView(
                    "Start a Song",
                    systemImage: "music.note.list",
                    description: Text("Create a project to begin writing.")
                )
            }
        }
        .onAppear {
            if selectedProjectID == nil {
                selectedProjectID = projects.first?.id
            }
        }
    }
}
