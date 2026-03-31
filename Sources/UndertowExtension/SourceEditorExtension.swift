import Foundation
import XcodeKit

/// Entry point for the Undertow Xcode Source Editor Extension.
///
/// Registers commands dynamically. Each command is lightweight — it extracts
/// editor content and forwards to the UndertowHelper via the bridge XPC service.
class SourceEditorExtension: NSObject, XCSourceEditorExtension {
    var commandDefinitions: [[XCSourceEditorCommandDefinitionKey: Any]] {
        commands.map { command in
            [
                .classNameKey: command.className,
                .identifierKey: command.identifier,
                .nameKey: command.name
            ]
        }
    }

    private var commands: [any UndertowCommand] {
        [PingCommand()]
    }
}

/// Protocol for Undertow extension commands.
protocol UndertowCommand {
    var className: String { get }
    var identifier: String { get }
    var name: String { get }
}
