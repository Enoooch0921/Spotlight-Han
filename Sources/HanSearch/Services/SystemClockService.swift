import AppKit
import HanSearchCore

/// The companion shortcut uses Apple's Clock action; this app never owns a ringing timer.
enum SystemClockService {
    static let shortcutName = "Spotlight-Han-System-Clock"
    static let receipt = "SPOTLIGHT_HAN_CLOCK_CREATED_V1"
    static func isConnected() throws -> Bool {
        let data = try ProcessRunner.run("/usr/bin/shortcuts", ["list"], timeout: 15)
        return String(decoding: data, as: UTF8.self).split(separator: "\n").contains { $0 == shortcutName }
    }
    @MainActor static func install() {
        guard let url = Bundle.main.url(forResource: shortcutName, withExtension: "shortcut") else { return }
        NSWorkspace.shared.open(url)
    }
    @MainActor static func openClock() { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Clock.app")) }

    static func create(_ plan: TaskPlan) throws -> String {
        guard try isConnected() else { throw ProcessFailure.failed("請至設定按「連接系統時鐘」，加入一次橋接捷徑，再執行此指令。") }
        let now = Date()
        let date = try ClockAlarmRequest.date(for: plan, now: now)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("alarm.json"), output = directory.appendingPathComponent("receipt.txt")
        // A local JSON file avoids shell interpolation, clipboard access, and URL leakage.
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "HH:mm"
        let data = try JSONSerialization.data(withJSONObject: ["time": formatter.string(from: date), "title": plan.title])
        try data.write(to: input, options: .atomic)
        do { _ = try ProcessRunner.run("/usr/bin/shortcuts", ["run", shortcutName, "--input-path", input.path, "--output-path", output.path], timeout: 60) }
        catch { throw ProcessFailure.failed("系統時鐘捷徑未完成。請開啟時鐘確認，避免直接重試而重複建立。") }
        guard let returned = try? String(contentsOf: output, encoding: .utf8), returned.trimmingCharacters(in: .whitespacesAndNewlines) == receipt else {
            throw ProcessFailure.failed("沒有收到橋接捷徑的完成回覆；請開啟系統時鐘確認，避免重複建立。")
        }
        return "系統時鐘已完成新增鬧鐘「\(plan.title)」\n" + date.formatted(date: .abbreviated, time: .shortened) + " · Apple 時鐘"
    }
}
