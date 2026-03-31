import Foundation

/// XPC protocol implemented by the UndertowHelper background agent.
///
/// This protocol is used by the host app and extension (via the bridge)
/// to communicate with the helper's flow engine, memory store, and tools.
@objc public protocol HelperXPCProtocol {
    /// Returns the current flow context as JSON-encoded data.
    func getFlowContext(withReply reply: @escaping (Data?, Error?) -> Void)

    /// Performs a semantic search over the codebase. Query is JSON-encoded.
    func semanticSearch(query: Data, withReply reply: @escaping (Data?, Error?) -> Void)

    /// Retrieves relevant memories for the given query. Query is JSON-encoded.
    func getMemories(query: Data, withReply reply: @escaping (Data?, Error?) -> Void)

    /// Saves a new memory. Content is JSON-encoded.
    func saveMemory(content: Data, withReply reply: @escaping (Error?) -> Void)

    /// Creates a named checkpoint of the current project state.
    func createCheckpoint(name: String, withReply reply: @escaping (Error?) -> Void)

    /// Lists all available checkpoints as JSON-encoded data.
    func listCheckpoints(withReply reply: @escaping (Data?, Error?) -> Void)

    /// Reverts the project to a named checkpoint.
    func revertToCheckpoint(name: String, withReply reply: @escaping (Error?) -> Void)

    /// Health check. Returns immediately if the helper is alive.
    func ping(withReply reply: @escaping () -> Void)
}
