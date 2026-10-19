import Foundation
import HanSearchCore

actor NoteFixture {
    var fails = true
    var calls = 0
    func succeed() { fails = false }
    func open(_ id: String) async throws {
        calls += 1
        try await Task.sleep(for: .milliseconds(30))
        if fails { throw URLError(.cannotOpenFile) }
    }
}

@main struct HabitChecks {
    @MainActor static func main() async throws {
        let now = Date()
        let app = HabitCandidate(id: "app-row", identity: "app:fixture.logic", title: "Logic Pro", kind: .app)
        let note = HabitCandidate(id: "note-row", identity: "quick:note:private-id", title: "工作筆記", kind: .note)
        let file = HabitCandidate(id: "file-row", identity: "file:/fixture/private.docx", title: "Logic 課程.docx", kind: .file)
        let candidates = [note, app, file]
        var history = SearchHabitHistory(salt: "fixture")
        precondition(history.ordered(candidates, query: "logicpro", now: now) == candidates.map(\.id))
        history.record(query: "Logic Pro", identity: note.identity, kind: .note, now: now)
        precondition(history.ordered(candidates, query: "logicpro", now: now).first == app.id, "One accidental choice must not override an exact App name")
        history.record(query: "LOGICPRO", identity: note.identity, kind: .note, now: now)
        precondition(history.ordered(candidates, query: "logicpro", now: now).first == note.id)
        let ranked = history.ordered([app,file], query: "logicpro", now: now)
        precondition(ranked == [app.id,file.id], "Missing learned targets never appear")
        precondition(history.ordered(candidates, query: "Logic", now: now).first != note.id, "Query-specific boost must not leak to another query")
        var types = SearchHabitHistory(salt: "types")
        for _ in 0..<20 { types.record(query:"different", identity:app.identity, kind:.app, now:now) }
        let noteTie = HabitCandidate(id:"note",identity:"note",title:"測試",kind:.note)
        let appTie = HabitCandidate(id:"app",identity:"app:other",title:"測試",kind:.app)
        precondition(types.ordered([noteTie,appTie],query:"測試",now:now).first == appTie.id, "Type preference breaks comparable relevance ties")
        let exactNote = HabitCandidate(id:"exact",identity:"note:exact",title:"Exact",kind:.note)
        precondition(types.ordered([appTie,exactNote],query:"Exact",now:now).first == exactNote.id, "General App preference cannot override a clear title match")
        let fcpAlias = HabitCandidate(id:"fcp",identity:"app:fcp",title:"Final Cut Pro",kind:.app,aliases:["fcp","fcpx"])
        precondition(types.ordered([noteTie,fcpAlias],query:"fcp",now:now).first == fcpAlias.id, "Known aliases retain relevance when habits are present")
        let encoded = try JSONEncoder().encode(history)
        let text = String(decoding:encoded,as:UTF8.self)
        for secret in ["Logic Pro","LOGICPRO","private-id","工作筆記","/fixture/private.docx"] { precondition(!text.contains(secret)) }
        var decoded = try JSONDecoder().decode(SearchHabitHistory.self,from:encoded)
        precondition(decoded.ordered(candidates,query:"Logic Pro",now:now).first == note.id)
        precondition(SearchHabitHistory.queryKey("紅果短劇") == SearchHabitHistory.queryKey("红果短剧"))
        decoded.prune(now:now.addingTimeInterval(366*86400)); precondition(decoded.entries.isEmpty)
        var bounded = SearchHabitHistory(salt:"bounded")
        for index in 0..<2010 { bounded.record(query:"q\(index)",identity:"i\(index)",kind:.file,now:now.addingTimeInterval(Double(index))) }
        precondition(bounded.entries.count == 2000)
        let suite = "HanHabitChecks." + UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let habits = SearchHabitStore(defaults:defaults)
        habits.record(query:"logicpro",identity:app.identity,kind:.app)
        let reloaded = SearchHabitStore(defaults:defaults); precondition(reloaded.history.entries.count == 1)
        reloaded.enabled = false; reloaded.record(query:"secret",identity:"other",kind:.note)
        precondition(reloaded.history.entries.count == 1 && reloaded.ordered(candidates,query:"logicpro") == candidates.map(\.id))
        reloaded.clear(); precondition(reloaded.history.entries.isEmpty && defaults.data(forKey:"searchHabits.history.v1") == nil)
        reloaded.enabled = true
        var accepts = false, opened = 0
        let notes = NoteFixture()
        let store = SearchStore(loadSources:false,taskPreferences:defaults,sourcePreferences:defaults,resultOpener:{ _ in opened += 1; return accepts },noteOpener:{ try await notes.open($0) })
        store.query = "logicpro"
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("HanHabitFile-" + UUID().uuidString + ".txt")
        try Data("fixture".utf8).write(to:temp)
        defer { try? FileManager.default.removeItem(at:temp) }
        let result = SearchItem(url:temp,name:"Logic Pro",source:"fixture")
        store.results = [result]; store.selection = result.id
        store.openSelection(); precondition(store.habits.history.entries.isEmpty)
        accepts = true; store.openSelection(); precondition(store.habits.history.entries.count == 1 && opened == 2)
        let quickNote = QuickResult(id:"note:fixture",title:"工作筆記",subtitle:"",symbol:"note",action:.note("fixture"))
        store.quickResults = [quickNote]; store.selection = quickNote.id
        store.openSelection(); try await Task.sleep(for:.milliseconds(80))
        precondition(store.habits.history.entries.count == 1, "Failed note openings must not teach")
        await notes.succeed()
        store.openSelection(); store.query = "changed while opening"
        try await Task.sleep(for:.milliseconds(80))
        precondition(store.habits.history.entries.count == 2)
        store.query = "logicpro"; store.selection = quickNote.id; store.openSelection()
        try await Task.sleep(for:.milliseconds(80))
        precondition(store.allIDs.first == quickNote.id, "Learned Notes must cross the App/file section boundary")
        let calculator = QuickResult(id:"calculator",title:"2",subtitle:"",symbol:"equal",action:.details("fixture"))
        store.quickResults.insert(calculator,at:0)
        precondition(store.allIDs.first == calculator.id)
        store.mode = .calendar
        precondition(store.allIDs == store.allQuickResults.map(\.id) + store.results.map(\.id))
        store.habits.clear(); precondition(store.habits.history.entries.isEmpty)
        let aliases = SearchAliasStore(defaults: defaults)
        precondition(SearchAliasStore.parse("hgdj，短劇、HGdj") == ["hgdj", "短劇"])
        precondition(SearchAliasStore.parse(String(repeating: "x", count: 33)) == nil)
        precondition(SearchAliasStore.parse((0..<9).map(String.init).joined(separator: ",")) == nil)
        precondition(aliases.set(["MyAlias", "短劇"], for: "app:fixture"))
        let aliasReload = SearchAliasStore(defaults: defaults)
        precondition(aliasReload.matchingTargets("myalias") == ["app:fixture"])
        precondition(aliasReload.matchingTargets("短剧") == ["app:fixture"])
        precondition(aliasReload.matchingTargets("myali").isEmpty)
        precondition(aliasReload.set([], for: "app:fixture") && aliasReload.matchingTargets("myalias").isEmpty)
        print("PASS: per-query choices, general type preferences, cross-type keyboard/display order, exact-match protection, salted persistence without raw text, disable/clear, stale/bounded history, successful-only file/Note opening and original-query capture; fake openers only")
    }
}
