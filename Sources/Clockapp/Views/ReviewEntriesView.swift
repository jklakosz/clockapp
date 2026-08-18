import SwiftUI

/// Popup shown when the assistant proposes descriptions via `submit_entries`.
/// The user reviews/edits each one, then publishes to Clockify (or cancels).
struct ReviewEntriesView: View {
    @EnvironmentObject private var state: AppState
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(state.t(.reviewTitle)).font(.headline)
            Text("\(state.reviewItems.count) · \(state.t(.reviewIntro))")
                .font(.caption).foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(state.reviewItems.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(state.reviewItems[i].timeRange)
                                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                                if let p = state.reviewItems[i].projectName {
                                    Text("· \(p)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            TextField("Description", text: $state.reviewItems[i].description, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(1...4)
                        }
                        .padding(8)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(minHeight: 220, maxHeight: 560)

            HStack {
                Button(state.t(.cancel)) { state.cancelReview(); onClose() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(state.t(.reviewPublish)) { state.publishReview(); onClose() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(state.reviewItems.isEmpty)
            }
        }
        .padding(18)
        .frame(width: 460)
    }
}
