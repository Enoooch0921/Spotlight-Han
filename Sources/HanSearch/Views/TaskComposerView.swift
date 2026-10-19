import SwiftUI
import HanSearchCore

struct TaskComposerView: View {
    @ObservedObject var store: SearchStore
    private var event: Bool { store.composerMode == .event }
    private var validationError: String? { store.composerDraft?.validationError() ?? store.composerCalendarError }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(L.text(event ? "新增行事曆行程" : "新增提醒事項"), systemImage: event ? "calendar.badge.plus" : "checklist").font(.headline)
                Spacer()
                Text(L.text("本機解析 · 確認後才建立")).font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let created = store.composerCreated {
                        Label(L.text("已建立"), systemImage: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
                        Text(created).textSelection(.enabled)
                    } else if store.composerReviewing, let draft = store.composerDraft {
                        Text(L.text("確認預覽")).font(.title3.weight(.semibold))
                        TextField(L.text("事項名稱"), text: draftBinding(\.title)).textFieldStyle(.roundedBorder).accessibilityLabel(L.text("事項名稱"))
                        Toggle(L.text(event ? "全天" : "只設定日期（不指定通知時間）"), isOn: allDayBinding)
                        DatePicker(L.text(event ? "開始" : "提醒時間"), selection: startBinding, displayedComponents: draft.isAllDay ? [.date] : [.date, .hourAndMinute])
                        if event {
                            DatePicker(L.text(draft.isAllDay ? "結束日期（含當天）" : "結束"), selection: endBinding, displayedComponents: draft.isAllDay ? [.date] : [.date, .hourAndMinute])
                            if !draft.isAllDay {
                                Picker(L.text("提前通知"), selection: alarmBinding) {
                                    Text(L.text("不另設通知")).tag(0)
                                    Text(L.text("開始時")).tag(1)
                                    ForEach(alarmMinutes, id: \.self) { minutes in Text(L.format("提前 %@ 分鐘", String(minutes))).tag(minutes + 1) }
                                }
                            }
                        }
                        if event {
                            EventCalendarPicker(store: store, selection: calendarBinding, label: "本次加入行事曆")
                            Text(L.text("本次選擇只套用這一筆；預設行事曆可在 Han 設定更改。")).font(.caption).foregroundStyle(.secondary)
                        } else { destination }
                        if !event && draft.isAllDay { Text(L.text("只設定到期日期，通知行為依系統提醒事項的設定。")).font(.caption).foregroundStyle(.secondary) }
                        Text(L.text("可調整預覽欄位；修改上方文字會重新解析。")).font(.caption).foregroundStyle(.secondary)
                    } else if let draft = store.composerDraft {
                        Text(draft.title).font(.title2.weight(.medium))
                        Label(dateDescription(draft.start, allDay: draft.isAllDay), systemImage: draft.isAllDay ? "sun.max" : "clock")
                        if event {
                            Text(L.text("結束") + "：" + dateDescription(draft.isAllDay ? Calendar.current.date(byAdding: .day, value: -1, to: draft.end)! : draft.end, allDay: draft.isAllDay)).foregroundStyle(.secondary)
                            if let offset = draft.alarmOffset { Text(L.format("提前 %@ 分鐘", String(Int(-offset / 60)))).foregroundStyle(.secondary) }
                        }
                        destination
                        Text(L.text("按 Return 進入確認預覽，可調整日期與內容。")).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(L.text(event ? "例如：明天下午3點到4點和鼎達叔叔開會" : "例如：30分鐘後喝水")).font(.title3)
                        Text(L.text(event ? "也可以輸入「下下週一上午10點開會30分鐘」。只填日期會建立全天行程。" : "也可以輸入「明天上午9點交報告」。只填日期會建立不指定時間的提醒事項。"))
                            .font(.callout).foregroundStyle(.secondary)
                        Text(L.text("輸入後先看解析結果，再按 Return 檢查預覽。")).font(.caption).foregroundStyle(.secondary)
                    }
                    if !store.composerError.isEmpty {
                        Label(L.text(store.composerError), systemImage: "exclamationmark.circle").foregroundStyle(.orange).font(.callout)
                    } else if store.composerReviewing, let validationError {
                        Label(L.text(validationError), systemImage: "exclamationmark.circle").foregroundStyle(.orange).font(.callout)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.disabled(store.actionInFlight)
            Spacer(minLength: 0)
            Divider()
            HStack {
                Button(L.text(store.composerCreated == nil ? "取消" : "完成")) { store.cancelComposer() }.disabled(store.actionInFlight)
                Spacer()
                if store.actionInFlight { ProgressView().controlSize(.small); Text(L.text("正在建立…")).font(.caption) }
                else if store.composerCreated == nil {
                    if store.composerReviewing {
                        Button(L.text("確認建立")) { store.confirmComposer() }
                            .buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: [.command])
                            .disabled(validationError != nil || store.composerDraft == nil)
                            .help(L.text("確認建立 ⌘Return"))
                    } else {
                        Button(L.text("預覽與調整 ↵")) { store.reviewComposer() }.buttonStyle(.borderedProminent).disabled(store.composerDraft == nil || store.composerParsing)
                    }
                }
            }
        }.padding(22).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private var destination: some View {
        Label(TaskService.destinationTitle(for: event ? .event : .reminder, calendarID: store.composerDraft?.calendarID), systemImage: event ? "calendar" : "list.bullet")
            .font(.callout).foregroundStyle(.secondary)
    }
    private var calendarBinding: Binding<String> {
        Binding(get: { store.composerDraft?.calendarID ?? "" }, set: { value in
            guard var draft = store.composerDraft else { return }
            draft.calendarID = value.isEmpty ? nil : value
            store.composerDraft = draft; store.composerError = ""
        })
    }
    private func dateDescription(_ date: Date, allDay: Bool) -> String {
        let formatter = DateFormatter(); formatter.locale = store.interfaceLanguage.locale
        formatter.dateStyle = .full; formatter.timeStyle = allDay ? .none : .short
        return formatter.string(from: date) + (allDay ? " · " + L.text("全天") : "")
    }
    private func draftBinding<T>(_ key: WritableKeyPath<TaskDraft, T>) -> Binding<T> {
        let fallback = store.composerDraft![keyPath: key]
        return Binding(get: { store.composerDraft?[keyPath: key] ?? fallback }, set: { value in
            guard var draft = store.composerDraft else { return }
            draft[keyPath: key] = value; store.composerDraft = draft; store.composerError = ""
        })
    }
    private var startBinding: Binding<Date> {
        Binding(get: { store.composerDraft?.start ?? Date() }, set: { value in
            guard var draft = store.composerDraft else { return }
            let duration = draft.end.timeIntervalSince(draft.start)
            draft.start = draft.isAllDay ? Calendar.current.startOfDay(for: value) : value
            draft.end = draft.start.addingTimeInterval(duration)
            store.composerDraft = draft; store.composerError = ""
        })
    }
    private var endBinding: Binding<Date> {
        Binding(get: {
            guard let draft = store.composerDraft else { return Date() }
            return draft.isAllDay ? Calendar.current.date(byAdding: .day, value: -1, to: draft.end)! : draft.end
        }, set: { value in
            guard var draft = store.composerDraft else { return }
            draft.end = draft.isAllDay ? Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: value))! : value
            store.composerDraft = draft; store.composerError = ""
        })
    }
    private var allDayBinding: Binding<Bool> {
        Binding(get: { store.composerDraft?.isAllDay ?? false }, set: { value in
            guard var draft = store.composerDraft else { return }
            draft.isAllDay = value
            if value {
                draft.start = Calendar.current.startOfDay(for: draft.start)
                draft.end = Calendar.current.date(byAdding: .day, value: 1, to: draft.start)!
                draft.alarmOffset = nil
            } else {
                draft.start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: draft.start)!
                draft.end = draft.start.addingTimeInterval(3600)
            }
            store.composerDraft = draft; store.composerError = ""
        })
    }
    private var alarmMinutes: [Int] { Array(Set([5,10,15,30,60,1440] + (store.composerDraft?.alarmOffset.map { [Int(-$0 / 60)] } ?? []))).filter { $0 > 0 }.sorted() }
    private var alarmBinding: Binding<Int> {
        Binding(get: { store.composerDraft?.alarmOffset.map { Int(-$0 / 60) + 1 } ?? 0 }, set: { value in
            guard var draft = store.composerDraft else { return }
            draft.alarmOffset = value == 0 ? nil : -Double(value - 1) * 60
            store.composerDraft = draft; store.composerError = ""
        })
    }
}
