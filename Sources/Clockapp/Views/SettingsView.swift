import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        TabView {
            ClockifyTab().tabItem { Label(state.t(.tabClockify), systemImage: "cloud") }
            ScheduleEditorView().tabItem { Label(state.t(.tabSchedule), systemImage: "calendar") }
            GoalsTab().tabItem { Label(state.t(.tabGoals), systemImage: "target") }
            EarningsTab().tabItem { Label(state.t(.tabEarnings), systemImage: "eurosign.circle") }
        }
        .padding(20)
    }
}

// MARK: - Clockify tab

private struct ClockifyTab: View {
    @EnvironmentObject private var state: AppState
    @State private var apiKeyInput = ""
    @State private var mcpCopied = false

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
                Toggle(state.t(.receiveRC), isOn: Binding(
                    get: { state.settings.receivePrereleases },
                    set: { state.settings.receivePrereleases = $0; state.save(); state.checkForUpdates(silent: true) }
                ))
                Text(state.t(.receiveRCHelp))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(state.t(.sectionMCP)) {
                Toggle(state.t(.mcpEnable), isOn: Binding(
                    get: { state.settings.mcpEnabled },
                    set: { state.setMCPEnabled($0) }
                ))
                Text(state.t(.mcpHelp)).font(.caption).foregroundStyle(.secondary)

                if state.settings.mcpEnabled {
                    HStack(spacing: 6) {
                        Circle().fill(state.mcpRunning ? .green : .orange).frame(width: 7, height: 7)
                        Text(state.mcpRunning ? state.t(.mcpRunning) : state.t(.mcpStopped))
                            .font(.caption).foregroundStyle(.secondary)
                        if let err = state.mcpError, !state.mcpRunning {
                            Text("— \(err)").font(.caption2).foregroundStyle(.red).lineLimit(1)
                        }
                    }
                    if state.mcpRunning {
                        Text(state.t(.mcpUrlHelp)).font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Text(state.mcpURL).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            Spacer()
                            Button(mcpCopied ? state.t(.mcpCopied) : state.t(.mcpCopy)) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(state.mcpURL, forType: .string)
                                mcpCopied = true
                            }
                            .controlSize(.small)
                        }
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

// MARK: - Earnings tab

private struct EarningsTab: View {
    @EnvironmentObject private var state: AppState

    private var e: Binding<Earnings> {
        Binding(get: { state.earnings }, set: {
            let pairChanged = $0.currency != state.earnings.currency || $0.convertTo != state.earnings.convertTo
            state.earnings = $0
            state.save()
            if pairChanged { state.refreshExchangeRate() }
        })
    }

    var body: some View {
        Form {
            Section(state.t(.sectionEarnings)) {
                Toggle(state.t(.enableEarnings), isOn: e.enabled)

                HStack {
                    Text(state.t(.hourlyRate))
                    Spacer()
                    TextField("", value: e.hourlyRate, format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text(state.earnings.currency.symbol).foregroundStyle(.secondary)
                }

                Picker(state.t(.currency), selection: e.currency) {
                    ForEach(Currency.allCases) { c in
                        Text(c.displayName).tag(c)
                    }
                }

                Picker(state.t(.convertTo), selection: e.convertTo) {
                    ForEach(Currency.allCases) { c in
                        Text(c.displayName).tag(c)
                    }
                }
                if let rate = state.rateDescription {
                    LabeledContent(state.t(.currentRate), value: rate)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section(state.t(.sectionUrssaf)) {
                Toggle(state.t(.urssafDeduct), isOn: e.urssafEnabled)
                HStack {
                    Text(state.t(.urssafRate))
                    Spacer()
                    TextField("", value: e.urssafRatePercent, format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                        .disabled(!state.earnings.urssafEnabled)
                    Text("%").foregroundStyle(.secondary)
                }
                Text(state.t(.urssafHelp))
                    .font(.caption).foregroundStyle(.secondary)
            }

            if state.earnings.enabled && state.earnings.hourlyRate > 0 {
                Section(state.t(.earnedThisMonth)) {
                    LabeledContent(state.t(.gross).capitalized,
                                   value: Format.money(state.monthGross, state.earnings.currency,
                                                       converted: state.converted(state.monthGross),
                                                       into: state.earnings.convertTo))
                    if state.earnings.urssafEnabled {
                        LabeledContent("− \(state.t(.urssafLabel))",
                                       value: Format.money(state.monthUrssaf, state.earnings.currency))
                            .foregroundStyle(.secondary)
                        LabeledContent(state.t(.net).capitalized,
                                       value: Format.money(state.monthNet, state.earnings.currency,
                                                           converted: state.converted(state.monthNet),
                                                           into: state.earnings.convertTo))
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .formStyle(.grouped)
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
