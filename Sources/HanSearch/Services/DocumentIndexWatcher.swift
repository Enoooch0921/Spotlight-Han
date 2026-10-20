import Foundation
import CoreServices

/// Native watcher setup can wait on filesystem providers. Keep all setup/teardown
/// on its own queue so a selected folder can never block the Settings window.
final class DocumentIndexWatcher {
    private let queue = DispatchQueue(label: "local.hansearch.document-events", qos: .utility)
    private let state = State()
    private final class State: @unchecked Sendable {
        var stream: FSEventStreamRef?
        var rootKey: [String] = []
        func stop() {
            if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
            stream = nil
            rootKey = []
        }
        deinit { stop() }
    }
    private final class Context: @unchecked Sendable {
        let changed: @Sendable () -> Void
        let excluded: String
        init(excluded: String, changed: @escaping @Sendable () -> Void) { self.excluded = excluded; self.changed = changed }
    }
    func start(roots: [URL], excluded: URL, changed: @escaping @Sendable () -> Void) {
        queue.async { [state, queue] in
            let paths = roots.map { $0.resolvingSymlinksInPath().path }.sorted()
            let key = paths + [excluded.resolvingSymlinksInPath().path]
            if state.stream != nil && state.rootKey == key { return }
            state.stop()
            guard !roots.isEmpty else { return }
            let box = Context(excluded: excluded.resolvingSymlinksInPath().path, changed: changed)
            var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(box).toOpaque(), retain: { pointer in
                guard let pointer else { return nil }; _ = Unmanaged<Context>.fromOpaque(pointer).retain(); return pointer
            }, release: { pointer in if let pointer { Unmanaged<Context>.fromOpaque(pointer).release() } }, copyDescription: nil)
            let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
                guard let info else { return }
                let box = Unmanaged<Context>.fromOpaque(info).takeUnretainedValue()
                let paths = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
                let canonical = paths.prefix(count).map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
                if canonical.contains(where: { $0 != box.excluded && !$0.hasPrefix(box.excluded + "/") }) { box.changed() }
            }
            let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagIgnoreSelf)
            state.stream = FSEventStreamCreate(nil, callback, &context, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 2, flags)
            if let stream = state.stream {
                FSEventStreamSetDispatchQueue(stream, queue)
                if FSEventStreamStart(stream) {
                    state.rootKey = key
                    // Reconcile edits made while native watcher setup was waiting.
                    box.changed()
                } else { state.stop() }
            }
        }
    }
    func stop() { queue.async { [state] in state.stop() } }
    deinit { stop() }
}
