import ApplicationServices
import AppKit
import Foundation
import UndertowKit

/// Observes Xcode state via the Accessibility API and NSWorkspace notifications.
///
/// Tracks the active file, cursor position, workspace URL, and scheme/destination
/// by subscribing to AX notifications and workspace activation events.
actor XcodeObserver {
    /// Current state snapshot.
    struct XcodeState: Sendable {
        var activeFile: String?
        var cursorLine: Int?
        var workspaceURL: String?
        var activeScheme: String?
        var activeDestination: String?
        var recentNavigation: [String] = []
    }

    private(set) var state = XcodeState()
    private var observerTask: Task<Void, Never>?
    private var activationTask: Task<Void, Never>?
    private var continuation: AsyncStream<XcodeState>.Continuation?

    /// Stream of Xcode state updates.
    let stateUpdates: AsyncStream<XcodeState>

    private let maxNavigationHistory = 20

    init() {
        var captured: AsyncStream<XcodeState>.Continuation?
        self.stateUpdates = AsyncStream { captured = $0 }
        self.continuation = captured
    }

    /// Start observing Xcode.
    func start() {
        AXUIElement.setGlobalMessagingTimeout(3)
        startWorkspaceMonitoring()
        connectToActiveXcode()
    }

    /// Stop observing.
    func stop() {
        observerTask?.cancel()
        activationTask?.cancel()
        observerTask = nil
        activationTask = nil
        continuation?.finish()
    }

    // MARK: - Workspace Monitoring

    private func startWorkspaceMonitoring() {
        activationTask = Task { @MainActor [weak self] in
            let center = NSWorkspace.shared.notificationCenter

            // Monitor app activation
            let activations = center.notifications(
                named: NSWorkspace.didActivateApplicationNotification
            )

            for await notification in activations {
                guard !Task.isCancelled else { return }
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                        as? NSRunningApplication,
                      app.isXcode else { continue }

                let pid = app.processIdentifier
                await self?.observeXcode(pid: pid)
            }
        }

        // Also check if Xcode is already running
        Task { @MainActor [weak self] in
            if let xcode = NSWorkspace.shared.runningApplications.first(where: \.isXcode) {
                let pid = xcode.processIdentifier
                await self?.observeXcode(pid: pid)
            }
        }
    }

    // MARK: - AX Observation

    private func connectToActiveXcode() {
        Task { @MainActor [weak self] in
            guard let xcode = NSWorkspace.shared.runningApplications.first(where: \.isXcode) else {
                return
            }
            let pid = xcode.processIdentifier
            await self?.observeXcode(pid: pid)
        }
    }

    private func observeXcode(pid: pid_t) {
        // Cancel previous observer
        observerTask?.cancel()

        let notificationNames = [
            kAXFocusedUIElementChangedNotification,
            kAXMainWindowChangedNotification,
            kAXValueChangedNotification,
        ]

        let stream = AXNotificationStream(pid: pid, notifications: notificationNames)
        let appElement = AXUIElementCreateApplication(pid)

        // Read initial state
        updateStateFromWindow(appElement: appElement)

        observerTask = Task { [weak self] in
            for await notification in stream {
                guard !Task.isCancelled else { return }
                await self?.handleNotification(notification, appElement: appElement)
            }
        }
    }

    private func handleNotification(
        _ notification: AXNotificationStream.AXNotification,
        appElement: AXUIElement
    ) {
        switch notification.name {
        case kAXFocusedUIElementChangedNotification:
            updateFocusedElement(notification.element, appElement: appElement)

        case kAXMainWindowChangedNotification:
            updateStateFromWindow(appElement: appElement)

        case kAXValueChangedNotification:
            // Text changed — update cursor position
            if notification.element.isSourceEditor || notification.element.role == "AXTextArea" {
                updateCursorPosition(from: notification.element)
            }

        default:
            break
        }
    }

    // MARK: - State Extraction

    private func updateFocusedElement(_ element: AXUIElement, appElement: AXUIElement) {
        // Check if the focused element is a source editor or its parent
        if element.isSourceEditor || element.role == "AXTextArea" {
            updateCursorPosition(from: element)
        }

        // Update document URL from the focused/main window
        updateStateFromWindow(appElement: appElement)
    }

    private func updateStateFromWindow(appElement: AXUIElement) {
        // Get active document from the focused window
        if let window = appElement.focusedWindow ?? appElement.mainWindow {
            if let doc = window.document {
                let path = doc
                    .replacingOccurrences(of: "file://", with: "")
                    .removingPercentEncoding ?? doc

                if path != state.activeFile {
                    // Track navigation
                    if let previous = state.activeFile {
                        state.recentNavigation.insert(previous, at: 0)
                        if state.recentNavigation.count > maxNavigationHistory {
                            state.recentNavigation = Array(state.recentNavigation.prefix(maxNavigationHistory))
                        }
                    }
                    state.activeFile = path
                }
            }

            // Extract workspace URL from window children
            if let workspacePath = window.extractWorkspacePath() {
                state.workspaceURL = workspacePath
            }

            // Try to extract scheme/destination from toolbar
            extractSchemeAndDestination(from: window)
        }

        emitState()
    }

    private func updateCursorPosition(from element: AXUIElement) {
        guard let range = element.selectedTextRange else { return }

        // Convert byte offset to line number
        if let content = element.stringValue {
            let line = lineNumber(at: range.location, in: content)
            state.cursorLine = line
        } else {
            state.cursorLine = nil
        }

        emitState()
    }

    /// Extract scheme and destination from Xcode's toolbar area.
    private func extractSchemeAndDestination(from window: AXUIElement) {
        // Xcode's scheme/destination is in the toolbar area.
        // The toolbar contains a popup button or static text with scheme info.
        // This is best-effort — toolbar structure varies by Xcode version.
        for child in window.children {
            if let desc = child.axDescription, desc.contains("scheme") || child.role == "AXToolbar" {
                for toolbarChild in child.children {
                    let title = toolbarChild.title ?? toolbarChild.stringValue ?? ""
                    if !title.isEmpty {
                        // Heuristic: scheme names don't contain ">" or device names
                        if title.contains(" > ") {
                            let parts = title.components(separatedBy: " > ")
                            if parts.count >= 2 {
                                state.activeScheme = parts[0].trimmingCharacters(in: .whitespaces)
                                state.activeDestination = parts[1].trimmingCharacters(in: .whitespaces)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func lineNumber(at offset: Int, in text: String) -> Int {
        var line = 0
        var currentOffset = 0
        for char in text {
            if currentOffset >= offset { break }
            if char == "\n" { line += 1 }
            currentOffset += 1
        }
        return line
    }

    private func emitState() {
        continuation?.yield(state)
    }
}
