import SwiftUI

struct ModelManagerView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Apple") {
                    Label("Apple Intelligence", systemImage: "apple.intelligence")
                    Text("Uses Apple's on-device Foundation Model when available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Local Models") {
                    ForEach(ModelCatalog.examples) { model in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(model.name)
                                    .font(.headline)
                                Spacer()
                                Text(model.sizeDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text(model.specialties.joined(separator: " · "))
                                .font(.subheadline)

                            Text("\(model.quantization) · minimum \(model.minimumMemoryGB) GB memory")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button("Download") {
                                // TODO: Hugging Face download manager.
                            }
                        }
                    }
                }

                Section {
                    Text("Downloaded models will run locally. Anchord will eventually recommend compatible models based on device capabilities, available memory, model format, and task specialization.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("AI Models")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
