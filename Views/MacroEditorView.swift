import SwiftUI

/// Manage chat command macros: `/trigger` → a saved prompt template.
struct MacroEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = CommandMacroStore.shared
    @State private var newMacro: CommandMacro?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($store.macros) { $macro in
                        NavigationLink {
                            MacroForm(macro: $macro)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("/\(macro.trigger)")
                                    .font(.body.weight(.semibold).monospaced())
                                Text(macro.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { store.macros.remove(atOffsets: $0) }
                    .onMove { store.macros.move(fromOffsets: $0, toOffset: $1) }
                } footer: {
                    Text("Type /trigger in Song Chat, optionally followed by more text. Placeholders like {lyrics} and {input} are filled in when the macro runs.")
                }

                Section {
                    Button("Restore Built-in Macros") { store.restoreBuiltIns() }
                }
            }
            .navigationTitle("Command Macros")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        newMacro = CommandMacro(trigger: "", title: "", template: "{input}")
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New macro")
                }
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }
            .sheet(item: $newMacro) { draft in
                NewMacroSheet(draft: draft) { saved in
                    store.macros.append(saved)
                }
            }
        }
    }
}

private struct NewMacroSheet: View {
    @State var draft: CommandMacro
    let onSave: (CommandMacro) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = CommandMacroStore.shared

    private var isValid: Bool {
        !draft.trigger.isEmpty && store.macro(for: draft.trigger) == nil
            && !draft.template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            MacroForm(macro: $draft)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if draft.title.isEmpty { draft.title = "/\(draft.trigger)" }
                            onSave(draft)
                            dismiss()
                        }
                        .disabled(!isValid)
                    }
                }
        }
    }
}

private struct MacroForm: View {
    @Binding var macro: CommandMacro

    var body: some View {
        Form {
            Section {
                HStack(spacing: 2) {
                    Text("/")
                        .foregroundStyle(.secondary)
                    TextField("trigger", text: Binding(
                        get: { macro.trigger },
                        set: { macro.trigger = CommandMacro.normalizedTrigger($0) }
                    ))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                }
                .font(.body.monospaced())
                TextField("What it does", text: $macro.title)
            } header: {
                Text("Command")
            }

            Section {
                TextEditor(text: $macro.template)
                    .frame(minHeight: 160)
                FlowLayout(spacing: 6) {
                    ForEach(CommandMacro.placeholders, id: \.self) { placeholder in
                        Button(placeholder) { macro.template += placeholder }
                            .font(.caption.monospaced())
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            } header: {
                Text("Prompt Template")
            } footer: {
                Text("{input} is whatever you type after the command. The AI already sees the whole song, so placeholders are optional.")
            }
        }
        .navigationTitle(macro.trigger.isEmpty ? "New Macro" : "/\(macro.trigger)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
