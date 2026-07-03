import SwiftUI

/// A searchable dropdown that groups projects by client (non-selectable client
/// header, projects indented below). Built as an inline expanding list rather than
/// a native Menu so it can host a live search field — which Menus cannot.
struct ProjectPicker: View {
    @EnvironmentObject private var state: AppState
    let projects: [Project]
    @Binding var selection: String?
    var noneTitle: String? = nil
    var label: String? = nil

    @State private var expanded = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private static let noClientKey = "\u{0}noclient"
    private var noneLabel: String { noneTitle ?? state.t(.noProject) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if expanded { searchAndList }
        }
    }

    // MARK: - Collapsed header row

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.12)) { expanded.toggle() }
        } label: {
            HStack(spacing: 8) {
                if let label { Text(label).foregroundStyle(.primary) }
                Spacer(minLength: 8)
                selectedDisplay
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onChange(of: expanded) { now in
            if now { DispatchQueue.main.async { searchFocused = true } }
            else { query = "" }
        }
    }

    @ViewBuilder private var selectedDisplay: some View {
        if let p = selectedProject {
            HStack(spacing: 6) {
                Circle().fill(p.color).frame(width: 8, height: 8)
                Text(p.name).lineLimit(1)
            }
        } else {
            Text(noneLabel).foregroundStyle(.secondary)
        }
    }

    // MARK: - Expanded search + list

    private var searchAndList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(state.t(.searchProject), text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if noneMatches {
                        row(title: noneLabel, color: nil, checked: selection == nil, indented: false) {
                            select(nil)
                        }
                    }
                    ForEach(filteredGroups, id: \.client) { group in
                        Text(clientHeader(group.client).uppercased())
                            .font(.caption2).fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        ForEach(group.projects) { p in
                            row(title: p.name, color: p.color, checked: selection == p.id, indented: true) {
                                select(p.id)
                            }
                        }
                    }
                    if filteredGroups.isEmpty && !noneMatches {
                        Text(state.t(.noResult)).font(.caption).foregroundStyle(.secondary).padding(.vertical, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
    }

    private func row(title: String, color: Color?, checked: Bool, indented: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let color { Circle().fill(color).frame(width: 8, height: 8) }
                Text(title).lineLimit(1)
                Spacer(minLength: 6)
                if checked { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .padding(.leading, indented ? 12 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func select(_ id: String?) {
        selection = id
        withAnimation(.easeInOut(duration: 0.12)) { expanded = false }
    }

    // MARK: - Grouping & filtering

    private var selectedProject: Project? {
        guard let selection else { return nil }
        return projects.first { $0.id == selection }
    }

    private var noneMatches: Bool {
        query.isEmpty || noneLabel.localizedCaseInsensitiveContains(query)
    }

    private func clientHeader(_ raw: String) -> String {
        raw == Self.noClientKey ? state.t(.noClient) : raw
    }

    private func matches(_ p: Project) -> Bool {
        query.isEmpty
            || p.name.localizedCaseInsensitiveContains(query)
            || (p.clientName ?? "").localizedCaseInsensitiveContains(query)
    }

    /// Projects grouped by client (clients A→Z, "Sans client" last), filtered by query.
    private var filteredGroups: [(client: String, projects: [Project])] {
        let dict = Dictionary(grouping: projects.filter(matches)) { proj -> String in
            let c = proj.clientName?.trimmingCharacters(in: .whitespaces) ?? ""
            return c.isEmpty ? Self.noClientKey : c
        }
        return dict
            .map { (client: $0.key, projects: $0.value.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }) }
            .sorted { lhs, rhs in
                if lhs.client == Self.noClientKey { return false }
                if rhs.client == Self.noClientKey { return true }
                return lhs.client.localizedCompare(rhs.client) == .orderedAscending
            }
    }
}
