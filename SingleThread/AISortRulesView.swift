import SingleThreadCore
import SwiftUI

// MARK: - AISortRulesView

/// The AI Sort Rules sub-menu: the freeform rules editor, a manual refresh
/// directly beneath it, and the live sorted & filtered preview below. Keeping
/// the editor and the preview on one pushed screen lets a rule change be read
/// against the real ordering without navigating away. The preview uses
/// `previewFont` — very small — so both surfaces fit on a single screen.
struct AISortRulesView: View {
    // MARK: Internal

    @Binding var aiSortRules: String

    let isAIRankingAvailable: Bool

    let store: ReminderStore

    /// The current visible set as display rows — sorted and filtered by the
    /// store exactly as the main reminder card sees it. Internal so tests can
    /// assert the order without rendering the pushed destination.
    var listDisplays: [ReminderDisplay] {
        store.visibleReminders.map { reminder in ReminderDisplay(reminder: reminder) }
    }

    var body: some View {
        Form {
            Section {
                if isAIRankingAvailable {
                    TextEditor(text: $aiSortRules)
                        .frame(minHeight: 88)
                        .accessibilityLabel(Text("AI Sort Rules"))
                        .accessibilityIdentifier("aiSortRulesEditor")

                    Button {
                        Task { await refresh() }
                    } label: {
                        HStack {
                            Label("Refresh", systemImage: "arrow.clockwise")
                            Spacer()
                            if isRefreshing {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isRefreshing)
                    .accessibilityValue(
                        isRefreshing
                            ? LocalizedStringResource("Refreshing", table: "Localizable", bundle: .main)
                            .resolvedInAppLanguage()
                            : "")
                    .accessibilityIdentifier("aiSortRefreshButton")
                } else {
                    // No point offering a rules editor the device cannot use;
                    // explain the fallback instead.
                    Label {
                        Text(LocalizedStringKey(
                            "This device doesn't support on-device AI, "
                                + "so reminders stay in priority order."))
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityIdentifier("aiSortUnavailableMessage")
                }
            } header: {
                Text("AI Sort Rules")
            } footer: {
                if isAIRankingAvailable {
                    SettingsCaption(
                        text: "Describe how reminders should be ordered. On-device AI applies these rules.")
                }
            }

            Section {
                if listDisplays.isEmpty {
                    Text("No reminders match the current filters.")
                        .font(previewFont)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("filteredRemindersEmptyState")
                } else {
                    ForEach(Array(listDisplays.enumerated()), id: \.offset) { _, display in
                        ReminderDisplayRow(display: display, font: previewFont)
                    }
                }
            } header: {
                Text("Sorted & Filtered")
            } footer: {
                SettingsCaption(text: "Preview how your reminders are ordered right now.")
            }
        }
        .localizedNavigationTitle("AI Sort Rules")
        .settingsSubscreenLayout()
    }

    // MARK: Private

    @State private var isRefreshing = false

    /// Very small, because the preview shares the screen with the editor.
    private let previewFont: Font = .caption2

    /// Manual refresh: re-reads reminders from the store, then asks the app
    /// layer to re-rank even when the rules and candidate set are unchanged, so
    /// a tap always re-runs the model rather than being absorbed by the
    /// coordinator's input-digest dedupe.
    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await store.reload(clearSkipped: store.allSkipped)
        store.requestAIRerank()
    }
}

// MARK: - Previews

#Preview("Rules") {
    let eventStore = InMemoryEventStore()
    let today = Calendar.current.dateComponents([.year, .month, .day], from: Date())
    let first = eventStore.makeReminder(
        title: "Call the dentist",
        notes: nil,
        dueDate: today,
        recurrenceRule: nil)
    let second = eventStore.makeReminder(
        title: "Ship the release",
        notes: nil,
        dueDate: today,
        recurrenceRule: nil)
    NavigationStack {
        AISortRulesView(
            aiSortRules: .constant("Clients first, then anything overdue."),
            isAIRankingAvailable: true,
            store: ReminderStore(
                eventStore: eventStore,
                loadsReminders: false,
                reminders: [first, second]))
    }
}
