import Foundation

/// Global actor for serializing XPC communication.
///
/// All XPC connection management and method calls should be isolated
/// to this actor to prevent data races on connection state.
@globalActor public enum XPCServiceActor: GlobalActor {
    public actor ActorType {}
    public static let shared = ActorType()
}
