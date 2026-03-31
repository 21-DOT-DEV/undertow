import Foundation

/// Bridges XPC callback-based APIs to Swift async/await.
///
/// Wraps an `AsyncThrowingStream.Continuation` to ensure it is always
/// finished exactly once, even if the caller forgets.
public final class AutoFinishContinuation<T: Sendable>: Sendable {
    private let continuation: AsyncThrowingStream<T, Error>.Continuation

    public init(continuation: AsyncThrowingStream<T, Error>.Continuation) {
        self.continuation = continuation
    }

    deinit {
        continuation.finish()
    }

    public func resume(returning value: T) {
        continuation.yield(value)
        continuation.finish()
    }

    public func resume(throwing error: Error) {
        continuation.finish(throwing: error)
    }
}

/// Calls an XPC method and returns its result as an async value.
///
/// Usage:
/// ```swift
/// let result: Data = try await withXPCService(connection) { proxy, cont in
///     proxy.someMethod { data, error in
///         if let error { cont.resume(throwing: error) }
///         else { cont.resume(returning: data) }
///     }
/// }
/// ```
@XPCServiceActor
public func withXPCService<T: Sendable, P>(
    _ connection: NSXPCConnection,
    as protocol: P.Type,
    _ body: @escaping @Sendable (P, AutoFinishContinuation<T>) -> Void
) async throws -> T {
    let stream = AsyncThrowingStream<T, Error> { continuation in
        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            continuation.finish(throwing: error)
        }
        guard let service = proxy as? P else {
            continuation.finish(throwing: XPCError.failedToCreateProxy)
            return
        }
        body(service, AutoFinishContinuation(continuation: continuation))
    }
    for try await result in stream {
        return result
    }
    throw XPCError.noResponse
}

/// Errors specific to XPC communication.
public enum XPCError: Error, LocalizedError {
    case failedToCreateProxy
    case noResponse
    case connectionInvalidated
    case helperNotRunning

    public var errorDescription: String? {
        switch self {
        case .failedToCreateProxy: "Failed to create XPC remote object proxy"
        case .noResponse: "No response received from XPC service"
        case .connectionInvalidated: "XPC connection was invalidated"
        case .helperNotRunning: "UndertowHelper is not running"
        }
    }
}
