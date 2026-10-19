import Foundation

public enum CallbackFailure: Error, LocalizedError {
    case timedOut
    public var errorDescription: String? { "等待系統回覆逾時；請先處理或關閉系統授權視窗，再重新連接。" }
}

/// Bridges system callbacks without hanging forever or accepting a late reply after cancellation.
public enum TimedCallback {
    @MainActor
    public static func wait<Value: Sendable>(timeout: TimeInterval,
        start: (@escaping @Sendable (Result<Value, Error>) -> Void) -> Void) async throws -> Value {
        let deadline = DispatchTime.now() + timeout
        let state = CallbackState<Value>(deadline: deadline)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                guard state.install(continuation) else { return }
                let timer = DispatchWorkItem { state.finish(.failure(CallbackFailure.timedOut)) }
                state.installTimer(timer)
                DispatchQueue.global().asyncAfter(deadline: deadline, execute: timer)
                guard !Task.isCancelled else { state.finish(.failure(CancellationError())); return }
                start { state.finish($0) }
            }
        } onCancel: { state.finish(.failure(CancellationError())) }
    }
}

private final class CallbackState<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var result: Result<Value, Error>?
    private var timer: DispatchWorkItem?
    private let deadline: DispatchTime

    init(deadline: DispatchTime) { self.deadline = deadline }

    func install(_ continuation: CheckedContinuation<Value, Error>) -> Bool {
        lock.lock()
        if let result { lock.unlock(); continuation.resume(with: result); return false }
        self.continuation = continuation
        lock.unlock(); return true
    }
    func installTimer(_ timer: DispatchWorkItem) {
        lock.lock()
        if result != nil { lock.unlock(); timer.cancel(); return }
        self.timer = timer
        lock.unlock()
    }
    func finish(_ proposed: Result<Value, Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        // Queue scheduling can delay the watchdog past a late callback. Enforce the same
        // monotonic deadline at completion, regardless of which block happens to run first.
        let result: Result<Value, Error>
        switch proposed {
        case .failure(let error) where error is CancellationError: result = proposed
        default:
            result = DispatchTime.now().uptimeNanoseconds >= deadline.uptimeNanoseconds ? .failure(CallbackFailure.timedOut) : proposed
        }
        self.result = result
        let continuation = self.continuation, timer = self.timer
        self.continuation = nil; self.timer = nil
        lock.unlock()
        timer?.cancel(); continuation?.resume(with: result)
    }
}
