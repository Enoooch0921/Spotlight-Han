import SwiftUI
import AppKit

struct EventCalendarPicker: View {
    @ObservedObject var store: SearchStore
    @Binding var selection: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(L.text(label), selection: $selection) {
                Text(L.text("跟隨系統預設") + " · " + TaskService.destinationTitle(for: .event)).tag("")
                ForEach(store.eventCalendarChoices) { calendar in Text(calendar.label).tag(calendar.id) }
                if !selection.isEmpty, !store.eventCalendarChoices.contains(where: { $0.id == selection }) {
                    Text(L.text("原選行事曆已無法使用，請重新選擇。")).tag(selection)
                }
            }.disabled(store.calendarSelectionBusy || store.actionInFlight)
            HStack {
                Button(L.text(store.eventCalendarChoices.isEmpty ? "讀取可寫入的行事曆…" : "重新讀取行事曆清單")) { store.requestEventCalendarChoices() }
                    .controlSize(.small).disabled(store.authorizationInFlight || store.actionInFlight)
                if store.calendarSelectionBusy { ProgressView().controlSize(.small) }
            }
            if !store.calendarSelectionError.isEmpty { Text(L.text(store.calendarSelectionError)).font(.caption).foregroundStyle(.orange) }
        }
        .onAppear { store.refreshEventCalendars() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in store.refreshEventCalendars() }
    }
}
