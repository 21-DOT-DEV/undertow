import Foundation
import UndertowKit

/// Observes file system changes in the project directory using FSEvents.
///
/// Maintains a rolling buffer of the last 50 events or 10 minutes,
/// whichever is smaller. Emits events as an AsyncStream.
actor FileSystemObserver {
    private var eventStream: FSEventStreamRef?
    private var events: [FileEvent] = []
    private var continuation: AsyncStream<FileEvent>.Continuation?

    private let maxEvents = 50
    private let maxAge: TimeInterval = 600 // 10 minutes

    /// The path being watched.
    let watchPath: String

    /// Stream of file system events.
    let fileEvents: AsyncStream<FileEvent>

    init(path: String) {
        self.watchPath = path
        var captured: AsyncStream<FileEvent>.Continuation?
        self.fileEvents = AsyncStream { captured = $0 }
        self.continuation = captured
    }

    /// Start watching the directory for changes.
    func start() {
        guard eventStream == nil else { return }

        let pathsToWatch = [watchPath] as CFArray
        let latency: CFTimeInterval = 1.0 // 1 second debounce

        // Store self pointer for the C callback
        let pointer = Unmanaged.passRetained(EventHandler(observer: self)).toOpaque()

        var context = FSEventStreamContext(
            version: 0,
            info: pointer,
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags: FSEventStreamCreateFlags =
            UInt32(kFSEventStreamCreateFlagUseCFTypes)
            | UInt32(kFSEventStreamCreateFlagFileEvents)
            | UInt32(kFSEventStreamCreateFlagNoDefer)

        guard let stream = FSEventStreamCreate(
            nil,
            eventCallback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else {
            fputs("FileSystemObserver: failed to create FSEventStream\n", stderr)
            return
        }

        eventStream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)
        fputs("FileSystemObserver: watching \(watchPath)\n", stderr)
    }

    /// Stop watching and clean up.
    func stop() {
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            eventStream = nil
        }
        continuation?.finish()
    }

    /// Get recent file events, pruning old ones.
    func recentEvents() -> [FileEvent] {
        pruneOldEvents()
        return events
    }

    // MARK: - Internal

    fileprivate func handleEvent(path: String, flags: FSEventStreamEventFlags) {
        // Skip hidden files, DerivedData, build artifacts, .git, Xcode workspace state
        let fileName = (path as NSString).lastPathComponent
        if fileName.hasPrefix(".") { return }
        if path.contains("/DerivedData/") { return }
        if path.contains("/.build/") { return }
        if path.contains("/.git/") { return }
        if path.contains("/xcuserdata/") { return }
        if path.contains(".xcworkspace/") { return }
        if fileName.hasSuffix(".tmp") || fileName.contains(".sb-") { return }

        let type: FileEvent.EventType
        if flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0 {
            type = .created
        } else if flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 {
            type = .deleted
        } else if flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 {
            type = .renamed
        } else if flags & UInt32(kFSEventStreamEventFlagItemModified) != 0 {
            type = .modified
        } else {
            return // Ignore other event types (e.g., metadata changes)
        }

        // Deduplicate: skip if the same path+type was seen within the last 2 seconds
        if let last = events.last(where: { $0.path == path && $0.type == type }),
           Date.now.timeIntervalSince(last.timestamp) < 2.0 {
            return
        }

        let event = FileEvent(path: path, type: type)
        events.append(event)
        pruneOldEvents()
        continuation?.yield(event)
    }

    private func pruneOldEvents() {
        let cutoff = Date.now.addingTimeInterval(-maxAge)
        events.removeAll { $0.timestamp < cutoff }
        if events.count > maxEvents {
            events = Array(events.suffix(maxEvents))
        }
    }
}

// MARK: - FSEvents C Callback Bridge

/// Reference type to bridge between the C callback and the actor.
private final class EventHandler: @unchecked Sendable {
    let observer: FileSystemObserver

    init(observer: FileSystemObserver) {
        self.observer = observer
    }
}

private func eventCallback(
    _ streamRef: ConstFSEventStreamRef,
    _ clientCallBackInfo: UnsafeMutableRawPointer?,
    _ numEvents: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let clientCallBackInfo else { return }
    let handler = Unmanaged<EventHandler>.fromOpaque(clientCallBackInfo)
        .takeUnretainedValue()

    let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()

    for i in 0..<numEvents {
        guard let path = CFArrayGetValueAtIndex(paths, i) else { continue }
        let pathString = Unmanaged<CFString>.fromOpaque(path)
            .takeUnretainedValue() as String
        let flags = eventFlags[i]

        Task {
            await handler.observer.handleEvent(path: pathString, flags: flags)
        }
    }
}
