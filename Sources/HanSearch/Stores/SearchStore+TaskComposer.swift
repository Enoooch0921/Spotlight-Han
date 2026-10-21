import AppKit
import HanSearchCore

@MainActor
extension SearchStore {
    @discardableResult func enterComposer() -> Bool {
        guard composerMode == nil, !actionInFlight, let destination = TaskComposerMode.command(query) else { return false }
        composerMode = destination
        refreshEventCalendars()
        composerInput = nil
        composerCreated = nil; composerError = ""; composerDraft = nil; composerReviewing = false
        query = ""; mode = .all; search(); focusToken = UUID()
        return true
    }
    func cancelComposer() {
        guard !actionInFlight else { return }
        composerTask?.cancel(); composerGeneration = UUID(); composerWantsReview = false
        composerMode = nil; composerDraft = nil; composerReviewing = false; composerParsing = false; composerCreated = nil; composerError = ""
        composerInput = nil
        query = ""; search(); focusToken = UUID()
    }
    func updateComposerPreview() {
        guard composerInput != query else { return }
        composerInput = query
        composerTask?.cancel(); composerGeneration = UUID()
        composerDraft = nil; composerReviewing = false; composerCreated = nil; composerError = ""; composerWantsReview = false
        let input = query, token = composerGeneration
        guard let mode = composerMode, !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { composerParsing = false; return }
        composerParsing = true
        let reference = Date()
        composerTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(180))
                var draft = try await naturalTaskParser.parse(input, mode: mode, now: reference)
                guard !Task.isCancelled, composerGeneration == token, composerMode == mode, query == input else { return }
                draft.calendarID = mode == .event && !defaultEventCalendarID.isEmpty ? defaultEventCalendarID : nil
                composerDraft = draft; composerReviewing = composerWantsReview
            } catch {
                guard !Task.isCancelled, composerGeneration == token else { return }
                composerError = error.localizedDescription
            }
            guard composerGeneration == token else { return }
            composerParsing = false; composerWantsReview = false; onLayoutChanged?()
        }
    }
    func reviewComposer() {
        guard !actionInFlight, composerCreated == nil else { return }
        if composerInput != query { updateComposerPreview() }
        if composerParsing { composerWantsReview = true }
        else if composerDraft != nil { composerReviewing = true; onLayoutChanged?() }
    }
    func previewTask(_ plan: TaskPlan) {
        pauseSearchForComposer()
        composerTask?.cancel(); composerGeneration = UUID(); composerWantsReview = false
        composerMode = plan.kind == .event ? .event : .reminder
        refreshEventCalendars()
        composerInput = query
        let resolved = plan.resolved(at: Date())
        composerDraft = TaskDraft(kind: plan.kind, title: plan.title, start: resolved.start, end: resolved.start.addingTimeInterval(plan.duration), isAllDay: plan.isAllDay, alarmOffset: plan.alarmOffset, calendarID: plan.kind == .event && !defaultEventCalendarID.isEmpty ? defaultEventCalendarID : nil, recurrence: plan.recurrence)
        composerReviewing = true; composerParsing = false; composerCreated = nil; composerError = ""
        results = []; quickResults = []; translationResult = nil; currencyResults = []; selection = nil
        onLayoutChanged?()
    }
    func confirmComposer() {
        guard composerReviewing, composerInput == query, !composerParsing, !actionInFlight, composerCreated == nil, let draft = composerDraft else { return }
        if let error = draft.validationError() { composerError = error; return }
        if let error = composerCalendarError { composerError = error; return }
        // Use the same foreground permission presentation as Settings; a floating launcher
        // must never sit above macOS consent. Do not overlap a queued source's consent.
        guard !authorizationInFlight else { composerError = "資料來源仍在連接中，請稍後再建立。"; return }
        actionInFlight = true; composerError = ""
        Task {
            do {
                let message = try await writeConfirmedTask(draft)
                let source: SearchMode = draft.kind == .event ? .calendar : .reminders
                if sourceHealth[source]?.hasSnapshot == true { sourceHealth[source]?.markChanged() }
                composerCreated = message; composerDraft = nil; composerReviewing = false
                composerError = ""; notice = "已建立"
            } catch { composerError = error.localizedDescription }
            actionInFlight = false; onLayoutChanged?(); refreshAuthorizedSources(changedOnly: true); startNextSource()
        }
    }
    private func writeConfirmedTask(_ draft: TaskDraft) async throws -> String {
        // Injected writers allow exercising the complete confirmation path without touching
        // personal EventKit data. Production always uses the authorised system writer below.
        if let taskWriter { return try await taskWriter(draft.plan) }
        let source: SearchMode = draft.kind == .event ? .calendar : .reminders
        if !PersonalSources.isAuthorized(source) {
            authorizationInFlight = true; prepareSystemAuthorization?()
            defer { finishTaskAuthorization() }
            try await PersonalSources.authorize(source)
        }
        // Consent may take minutes. Validate again immediately before saving.
        if let error = draft.validationError() { throw NaturalTaskFailure.invalid(error) }
        return try await TaskService.create(draft.plan)
    }
    var composerCalendarError: String? {
        guard let draft = composerDraft, draft.kind == .event, let id = draft.calendarID else { return nil }
        return eventCalendarChoices.contains { $0.id == id } ? nil : "原選行事曆已無法使用，請重新選擇。"
    }
    func refreshEventCalendars() { eventCalendarChoices = eventCalendarLoader() }
    func requestEventCalendarChoices() {
        guard !authorizationInFlight, !actionInFlight else { calendarSelectionError = "資料來源仍在連接中，請稍後再建立。"; return }
        if PersonalSources.isAuthorized(.calendar) { refreshEventCalendars(); calendarSelectionError = ""; return }
        calendarSelectionBusy = true; calendarSelectionError = ""; authorizationInFlight = true
        prepareSystemAuthorization?()
        Task {
            do { try await PersonalSources.authorize(.calendar); refreshEventCalendars() }
            catch { calendarSelectionError = error.localizedDescription }
            calendarSelectionBusy = false; finishTaskAuthorization(); startNextSource()
        }
    }
    private func finishTaskAuthorization() {
        authorizationInFlight = false
        NSApp.setActivationPolicy(settingsPresented ? .regular : .accessory)
        if !settingsPresented { showLauncher?() }
    }
}
