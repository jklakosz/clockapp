import SwiftUI
import AppKit

/// Settings for auto-generating entry descriptions from Claude sessions.
struct AutoDescriptionTab: View {
    @EnvironmentObject private var state: AppState
    @State private var clientSecretDraft = ""

    private var a: Binding<AutoDescription> {
        Binding(get: { state.autoDescription }, set: { state.autoDescription = $0; state.save() })
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

            Section(state.t(.autoDescCalendar)) {
                Picker(state.t(.autoDescCalendarSource), selection: a.calendarSource) {
                    Text(state.t(.autoDescCalOff)).tag(CalendarSource.off)
                    Text(state.t(.autoDescCalAgent)).tag(CalendarSource.agent)
                    Text(state.t(.autoDescCalOAuth)).tag(CalendarSource.oauth)
                }

                switch state.autoDescription.calendarSource {
                case .off:
                    EmptyView()
                case .agent:
                    Text(state.t(.autoDescCalAgentHelp)).font(.caption).foregroundStyle(.secondary)
                case .oauth:
                    Text(state.t(.autoDescGoogleHelp)).font(.caption).foregroundStyle(.secondary)
                    LabeledContent(state.t(.autoDescGoogleClientId)) {
                        TextField("xxxxx.apps.googleusercontent.com", text: a.googleClientId)
                            .frame(maxWidth: 240)
                    }
                    if state.googleConnected {
                        HStack {
                            Label(state.t(.autoDescGoogleConnected), systemImage: "checkmark.seal.fill")
                                .font(.caption).foregroundStyle(.green)
                            Spacer()
                            Button(state.t(.autoDescGoogleDisconnect), role: .destructive) {
                                state.googleDisconnect()
                            }.controlSize(.small)
                        }
                    } else {
                        LabeledContent(state.t(.autoDescGoogleClientSecret)) {
                            SecureField("GOCSPX-…", text: $clientSecretDraft).frame(maxWidth: 240)
                        }
                        HStack {
                            Spacer()
                            Button(state.t(.autoDescGoogleConnect)) {
                                state.googleConnect(clientSecret: clientSecretDraft)
                                clientSecretDraft = ""
                            }
                            .controlSize(.small)
                            .disabled(state.googleConnecting || state.autoDescription.googleClientId.isEmpty)
                            if state.googleConnecting { ProgressView().controlSize(.small) }
                        }
                    }
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
