import Foundation

public enum ProcessFailure: Error, LocalizedError {
    case failed(String)
    public var errorDescription: String? {
        switch self { case .failed(let message): return message }
    }
}

public enum ProcessRunner {
    public static func run(_ executable: String, _ arguments: [String], timeout: Double = 15) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let watchdog = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        guard process.terminationStatus == 0 else {
            throw ProcessFailure.failed("搜尋或文件讀取未完成（可能逾時或無法讀取）。")
        }
        return data
    }
}
