import SwiftUI
import AppKit

/// Settings for auto-generating entry descriptions from Claude sessions.
struct AutoDescriptionTab: View {
    @EnvironmentObject private var state: AppState

    private var a: Binding<AutoDescription> {
        Binding(get: { state.autoDescription }, set: { state.autoDescription = $0; state.save() })
    }

    /// Shows the effective template (the default when unset); editing stores an override.
    private var promptBinding: Binding<String> {
        Binding(
            get: {
                let t = state.autoDescription.promptTemplate
                return t.isEmpty ? AutoDescriptionService.defaultPromptTemplate : t
            },
            set: { state.autoDescription.promptTemplate = $0; state.save() }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle(state.t(.autoDescEnable), isOn: a.enabled)
                Text(state.t(.autoDescHelp)).font(.caption).foregroundStyle(.secondary)
            }

            Section(state.t(.autoDescMappings)) {
                Text(state.t(.autoDescProjectFolders)).font(.caption).foregroundStyle(.secondary)
                ForEach(a.mappings) { $m in
                    VStack(alignment: .leading, spacing: 4) {
                        ProjectPicker(projects: state.projects, selection: $m.projectId,
                                      label: state.t(.project))
                        HStack {
                            Text(m.folderPath.isEmpty ? "—" : m.folderPath)
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button(state.t(.chooseFolder)) {
                                if let p = pickFolder() { $m.folderPath.wrappedValue = p }
                            }.controlSize(.small)
                            Button(role: .destructive) {
                                state.autoDescription.mappings.removeAll { $0.id == m.id }
                                state.save()
                            } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless).controlSize(.small)
                        }
                    }
                    .padding(.vertical, 2)
                }
                Button {
                    state.autoDescription.mappings.append(ProjectFolder())
                    state.save()
                } label: { Label(state.t(.add), systemImage: "plus") }
            }

            Section {
                LabeledContent(state.t(.autoDescSessionsRoot)) {
                    HStack {
                        TextField("~/.claude/projects", text: a.claudeSessionsRoot)
                            .frame(maxWidth: 240)
                        Button(state.t(.chooseFolder)) {
                            if let p = pickFolder() { state.autoDescription.claudeSessionsRoot = p; state.save() }
                        }.controlSize(.small)
                    }
                }
                Text(state.t(.autoDescSessionsHelp)).font(.caption).foregroundStyle(.secondary)

                LabeledContent(state.t(.autoDescCommand)) {
                    TextField("claude", text: a.claudeCommand).frame(maxWidth: 240)
                }
                Text(state.t(.autoDescCommandHelp)).font(.caption).foregroundStyle(.secondary)
            }

            Section(state.t(.autoDescPromptTitle)) {
                Text(state.t(.autoDescPromptHelp)).font(.caption).foregroundStyle(.secondary)
                TextEditor(text: promptBinding)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 200)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.25)))
                Text("{{day}} · {{timeRange}} · {{project}} · {{existingDescription}} · {{sessionContext}}")
                    .font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                HStack {
                    Spacer()
                    Button(state.t(.autoDescPromptReset)) {
                        state.autoDescription.promptTemplate = ""
                        state.save()
                    }
                    .controlSize(.small)
                    .disabled(state.autoDescription.promptTemplate.isEmpty)
                }
            }

            Section {
                Toggle(state.t(.autoDescScheduleEnable), isOn: a.scheduledEnabled)
                if state.autoDescription.scheduledEnabled {
                    DatePicker(state.t(.autoDescScheduleAt), selection: scheduleTime,
                               displayedComponents: .hourAndMinute)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func pickFolder() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true // reveal dotfolders like ~/.claude
        panel.treatsFilePackagesAsDirectories = true
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    private var scheduleTime: Binding<Date> {
        Binding(
            get: {
                let m = state.autoDescription.scheduledMinuteOfDay
                return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
            },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                state.autoDescription.scheduledMinuteOfDay = (c.hour ?? 0) * 60 + (c.minute ?? 0)
                state.save()
            }
        )
    }
}
