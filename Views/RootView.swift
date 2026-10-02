import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \\.updatedAt, order: .reverse) private var projects: [SongProject]

    @State private var selectedProject: SongProject?

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedProject) {
                Section("Songs") {
                    ForEach(projects) { project in
                        NavigationLink(value: project) {
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
            .navigationTitle("Anchord")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        let project = SongProject()
                        modelContext.insert(project)
                        selectedProject = project
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
            if selectedProject == nil {
                selectedProject = projects.first
            }
        }
    }
}
