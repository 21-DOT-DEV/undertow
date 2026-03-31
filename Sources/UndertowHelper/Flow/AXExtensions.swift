import ApplicationServices
import AppKit
import Foundation

// MARK: - AXUIElement Convenience Extensions

extension AXUIElement {
    /// Safely copy an attribute value, returning `nil` on failure.
    func copyValue<T>(key: String, as type: T.Type = T.self) -> T? {
        var value: AnyObject?
        let err = AXUIElementCopyAttributeValue(self, key as CFString, &value)
        guard err == .success else { return nil }
        return value as? T
    }

    /// The element's string value.
    var stringValue: String? {
        copyValue(key: kAXValueAttribute)
    }

    /// The element's role (e.g., "AXTextArea", "AXGroup").
    var role: String? {
        copyValue(key: kAXRoleAttribute)
    }

    /// The element's description.
    var axDescription: String? {
        copyValue(key: kAXDescriptionAttribute)
    }

    /// The element's identifier.
    var identifier: String? {
        copyValue(key: kAXIdentifierAttribute)
    }

    /// The element's title.
    var title: String? {
        copyValue(key: kAXTitleAttribute)
    }

    /// The document URL associated with this element (often a window).
    var document: String? {
        copyValue(key: kAXDocumentAttribute)
    }

    /// The children of this element.
    var children: [AXUIElement] {
        copyValue(key: kAXChildrenAttribute, as: [AXUIElement].self) ?? []
    }

    /// The focused child element.
    var focusedUIElement: AXUIElement? {
        copyValue(key: kAXFocusedUIElementAttribute)
    }

    /// All windows of this application element.
    var windows: [AXUIElement] {
        copyValue(key: kAXWindowsAttribute, as: [AXUIElement].self) ?? []
    }

    /// The main window.
    var mainWindow: AXUIElement? {
        copyValue(key: kAXMainWindowAttribute)
    }

    /// The focused window.
    var focusedWindow: AXUIElement? {
        copyValue(key: kAXFocusedWindowAttribute)
    }

    /// The selected text range as a CFRange.
    var selectedTextRange: CFRange? {
        var value: AnyObject?
        let err = AXUIElementCopyAttributeValue(self, kAXSelectedTextRangeAttribute as CFString, &value)
        guard err == .success, let axValue = value else { return nil }
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(axValue as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    /// Set the global AX messaging timeout to prevent hangs.
    static func setGlobalMessagingTimeout(_ seconds: Float) {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), seconds)
    }

    /// Create an AXUIElement for a running application.
    static func fromApplication(_ app: NSRunningApplication) -> AXUIElement {
        AXUIElementCreateApplication(app.processIdentifier)
    }
}

// MARK: - Xcode-Specific Helpers

extension AXUIElement {
    /// Whether this is a Xcode workspace window.
    var isXcodeWorkspaceWindow: Bool {
        let desc = axDescription ?? ""
        let ident = identifier ?? ""
        return desc == "Xcode.WorkspaceWindow" || ident == "Xcode.WorkspaceWindow"
    }

    /// Whether this is a source editor element.
    var isSourceEditor: Bool {
        axDescription == "Source Editor"
    }

    /// Find the source editor in this element's subtree.
    /// Uses breadth-first search limited to 4 levels deep to avoid performance issues.
    func findSourceEditor(maxDepth: Int = 4) -> AXUIElement? {
        if isSourceEditor { return self }

        var queue: [(element: AXUIElement, depth: Int)] = [(self, 0)]
        while !queue.isEmpty {
            let (current, depth) = queue.removeFirst()
            guard depth < maxDepth else { continue }

            for child in current.children {
                if child.isSourceEditor { return child }
                queue.append((child, depth + 1))
            }
        }

        return nil
    }

    /// Extract the workspace path from window children.
    /// Xcode window children include a path element describing the workspace location.
    func extractWorkspacePath() -> String? {
        for child in children {
            if let desc = child.axDescription,
               desc.hasPrefix("/"),
               desc.count > 1 {
                return desc.trimmingCharacters(in: .newlines)
            }
        }
        return nil
    }
}

// MARK: - NSRunningApplication Extension

extension NSRunningApplication {
    /// Whether this application is Xcode.
    var isXcode: Bool {
        bundleIdentifier == "com.apple.dt.Xcode"
    }
}
