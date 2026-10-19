import Foundation
import Darwin

public final class ProcessCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    public init() {}
    public func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

public enum ProcessFailure: Error, LocalizedError {
    case failed(String)
    public var errorDescription: String? {
        switch self { case .failed(let message): return message }
    }
}

public enum ProcessRunner {
    public static func run(_ executable: String, _ arguments: [String], timeout: Double = 15,
                           cancellation: ProcessCancellation? = nil, outputLimit: Int? = nil, onLine: ((Data) -> Void)? = nil) throws -> Data {
        if cancellation?.isCancelled == true { throw CancellationError() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        let watchdog = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "local.hansearch.process-watchdog"))
        watchdog.schedule(deadline: .now(), repeating: .milliseconds(100))
        watchdog.setEventHandler {
            guard process.isRunning, Date() >= deadline || cancellation?.isCancelled == true else { return }
            // osascript can remain inside an Apple event after SIGTERM. Ensure the pipe eventually closes.
            kill(process.processIdentifier, SIGKILL)
        }
        watchdog.resume()
        defer { watchdog.cancel(); try? output.fileHandleForReading.close() }
        var data = Data(), pending = Data()
        while true {
            let chunk = output.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            if let outputLimit, data.count + chunk.count > outputLimit {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                process.waitUntilExit()
                throw ProcessFailure.failed("文件或搜尋輸出過大，請縮小搜尋範圍。")
            }
            data.append(chunk)
            if let onLine {
                pending.append(chunk)
                while let newline = pending.firstIndex(of: 10) {
                    onLine(Data(pending[..<newline])); pending.removeSubrange(...newline)
                }
            }
        }
        if let onLine, !pending.isEmpty { onLine(pending) }
        process.waitUntilExit()
        if cancellation?.isCancelled == true { throw CancellationError() }
        guard process.terminationStatus == 0 else {
            throw ProcessFailure.failed("搜尋或文件讀取未完成（可能逾時或無法讀取）。")
        }
        return data
    }
}
