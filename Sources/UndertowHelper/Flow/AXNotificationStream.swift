@preconcurrency import ApplicationServices
import Foundation

/// An `AsyncSequence` that yields Accessibility notifications from a running application.
///
/// Wraps `AXObserverCreateWithInfoCallback` and integrates with the main `CFRunLoop`
/// so that notifications arrive as async values.
struct AXNotificationStream: AsyncSequence {
    typealias Element = AXNotification

    struct AXNotification: @unchecked Sendable {
        let name: String
        let element: AXUIElement
    }

    private let pid: pid_t
    private let notifications: [String]

    /// Create a stream for the given application process and notification names.
    ///
    /// - Parameters:
    ///   - pid: The process identifier of the application to observe.
    ///   - notifications: AX notification names to subscribe to (e.g., `kAXFocusedUIElementChangedNotification`).
    init(pid: pid_t, notifications: [String]) {
        self.pid = pid
        self.notifications = notifications
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(pid: pid, notifications: notifications)
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        private let stream: AsyncStream<AXNotification>
        private var iterator: AsyncStream<AXNotification>.Iterator

        init(pid: pid_t, notifications: [String]) {
            let appElement = AXUIElementCreateApplication(pid)

            var streamContinuation: AsyncStream<AXNotification>.Continuation?
            let stream = AsyncStream<AXNotification> { continuation in
                streamContinuation = continuation
            }

            self.stream = stream
            self.iterator = stream.makeAsyncIterator()

            guard let continuation = streamContinuation else { return }

            // Store continuation in a heap-allocated box for the C callback
            let box = Unmanaged.passRetained(ContinuationBox(continuation))
            let pointer = box.toOpaque()

            continuation.onTermination = { _ in
                // Release the box when the stream terminates
                box.release()
            }

            var observer: AXObserver?
            let err = AXObserverCreateWithInfoCallback(pid, axCallback, &observer)
            guard err == .success, let observer else {
                continuation.finish()
                return
            }

            // Subscribe to each notification
            for name in notifications {
                let result = AXObserverAddNotification(
                    observer,
                    appElement,
                    name as CFString,
                    pointer
                )
                if result != .success && result != .notificationAlreadyRegistered {
                    fputs("AXNotificationStream: failed to register \(name): \(result.rawValue)\n", stderr)
                }
            }

            // Add observer to main run loop
            let runLoopSource = AXObserverGetRunLoopSource(observer)
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)

            // Store observer reference so it isn't deallocated
            let observerRef = Unmanaged.passRetained(observer as AnyObject)
            let notificationsCopy = notifications
            let appElementCopy = appElement

            continuation.onTermination = { _ in
                // Clean up: remove notifications and observer from run loop
                for name in notificationsCopy {
                    AXObserverRemoveNotification(observer, appElementCopy, name as CFString)
                }
                CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
                observerRef.release()
                box.release()
            }
        }

        mutating func next() async -> AXNotification? {
            await iterator.next()
        }
    }
}

// MARK: - C Callback Bridge

/// Heap-allocated box to pass the continuation through the C callback's `void*`.
private final class ContinuationBox: @unchecked Sendable {
    let continuation: AsyncStream<AXNotificationStream.AXNotification>.Continuation

    init(_ continuation: AsyncStream<AXNotificationStream.AXNotification>.Continuation) {
        self.continuation = continuation
    }
}

private func axCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notificationName: CFString,
    _ userInfo: CFDictionary?,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let box = Unmanaged<ContinuationBox>.fromOpaque(refcon).takeUnretainedValue()
    let notification = AXNotificationStream.AXNotification(
        name: notificationName as String,
        element: element
    )
    box.continuation.yield(notification)
}
