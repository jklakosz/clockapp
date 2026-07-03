import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        TabView {
            ClockifyTab().tabItem { Label(state.t(.tabClockify), systemImage: "cloud") }
            ScheduleEditorView().tabItem { Label(state.t(.tabSchedule), systemImage: "calendar") }
            GoalsTab().tabItem { Label(state.t(.tabGoals), systemImage: "target") }
        }
        .padding(20)
    }
}

// MARK: - Clockify tab

private struct ClockifyTab: View {
    @EnvironmentObject private var state: AppState
    @State private var apiKeyInput = ""

    var body: some View {
        Form {
            Section(state.t(.sectionConnection)) {
                SecureField(state.t(.apiKey), text: $apiKeyInput)
                Text(state.t(.apiHelp))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(state.t(.connect)) { state.setAPIKey(apiKeyInput) }
                        .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button(state.t(.refreshProjects)) { Task { await state.connect() } }
                        .disabled(!state.clockify.isConfigured)
                    Spacer()
                    statusView
                }
            }

            if !state.projects.isEmpty {
                Section(state.t(.defaultProject)) {
                    Toggle(state.t(.useLastProject), isOn: Binding(
                        get: { state.settings.useLastProjectAsDefault },
                        set: { state.settings.useLastProjectAsDefault = $0; state.save() }
                    ))
                    ProjectPicker(projects: state.projects, selection: Binding(
                        get: { state.settings.defaultProjectId },
                        set: { state.settings.defaultProjectId = $0; state.save() }
                    ), label: state.t(.defaultProject))
                    .disabled(state.settings.useLastProjectAsDefault)
                    if state.settings.useLastProjectAsDefault {
                        let p = state.project(for: state.settings.lastUsedProjectId)
                        let label: String = {
                            guard let p else { return state.t(.noneYet) }
                            if let client = p.clientName, !client.isEmpty {
                                return "\(client) › \(p.name)"
                            }
                            return p.name
                        }()
                        Text(state.t(.lastUsedFmt, label))
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(state.t(.projectsLoadedFmt, state.projects.count))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section(state.t(.sectionDisplay)) {
                Toggle(state.t(.showSeconds), isOn: Binding(
                    get: { state.settings.showSecondsInMenuBar },
                    set: { state.settings.showSecondsInMenuBar = $0; state.save() }
                ))
                Toggle(state.t(.launchAtLogin), isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.setLaunchAtLogin($0) }
                ))
            }

            Section(state.t(.sectionUpdates)) {
                HStack {
                    Text(state.t(.currentVersionFmt, state.appVersion))
                        .foregroundStyle(.secondary)
                    Spacer()
                    updateStatusView
                }
                HStack {
                    Button(state.t(.checkUpdates)) { state.checkForUpdates() }
                        .disabled(state.updateStatus == .checking || state.updateStatus == .installing)
                    if case .available = state.updateStatus {
                        Button(state.t(.updInstall)) { state.installUpdate() }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }

            Section(state.t(.sectionLanguage)) {
                Picker(state.t(.sectionLanguage), selection: Binding(
                    get: { state.settings.language },
                    set: { state.settings.language = $0; state.save() }
                )) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text("\(lang.flag)  \(lang.displayName)").tag(lang)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { apiKeyInput = KeychainStore.shared.apiKey ?? "" }
    }

    @ViewBuilder private var updateStatusView: some View {
        switch state.updateStatus {
        case .idle:
            EmptyView()
        case .checking:
            Text(state.t(.updChecking)).font(.caption).foregroundStyle(.secondary)
        case .upToDate:
            Label(state.t(.updUpToDate), systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        case .available(let v):
            Label(state.t(.updAvailableFmt, v), systemImage: "arrow.down.circle.fill")
                .font(.caption).foregroundStyle(.blue)
        case .installing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(state.t(.updInstalling)).font(.caption).foregroundStyle(.secondary)
            }
        case .failed(let msg):
            Label(state.t(.updFailedFmt, msg), systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.red).lineLimit(2)
        }
    }

    @ViewBuilder private var statusView: some View {
        switch state.connection {
        case .connected(let name):
            Label(name, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .connecting:
            ProgressView().controlSize(.small)
        case .failed(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red).lineLimit(2)
        case .disconnected:
            Label(state.t(.notConnected), systemImage: "circle").foregroundStyle(.secondary)
        }
    }
}

// MARK: - Goals tab

private struct GoalsTab: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            Section(state.t(.sectionHourGoals)) {
                Toggle(state.t(.enableGoals), isOn: Binding(
                    get: { state.goals.enabled },
                    set: { state.goals.enabled = $0; state.save() }
                ))
                Stepper(state.t(.dailyGoalSettingFmt, Format.hoursMinutes(state.goals.dailyMinutes)),
                        value: Binding(
                            get: { state.goals.dailyMinutes },
                            set: { state.goals.dailyMinutes = $0; state.save() }),
                        in: 30...(16 * 60), step: 30)
                Stepper(state.t(.weeklyGoalSettingFmt, Format.hoursMinutes(state.goals.weeklyMinutes)),
                        value: Binding(
                            get: { state.goals.weeklyMinutes },
                            set: { state.goals.weeklyMinutes = $0; state.save() }),
                        in: 60...(80 * 60), step: 60)
            }

            Section(state.t(.sectionReminders)) {
                Toggle(state.t(.notifyWindowStart), isOn: Binding(
                    get: { state.settings.nudgesEnabled },
                    set: {
                        state.settings.nudgesEnabled = $0
                        if $0 { NotificationService.shared.requestAuthorizationIfNeeded() }
                        state.save()
                    }
                ))
                Text(state.t(.remindersHelp))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
