import Foundation
import Observation

/// Manages security-scoped bookmark persistence and access state.
///
/// Accepts a `UserDefaults` instance for testability. In production, use the
/// App Group suite; in tests, use a unique ephemeral suite.
@Observable
public final class BookmarkManager {
    public enum AccessState: Equatable {
        case noBookmark
        case bookmarkStale
        case accessGranted
    }

    public private(set) var accessState: AccessState = .noBookmark

    /// Whether bookmark data exists in UserDefaults.
    /// Cached at init to avoid reading from the app group container in view bodies,
    /// which can trigger the sandbox "access data from other apps" dialog.
    public private(set) var hasStoredBookmark: Bool = false

    private var scopedURL: URL?
    private let defaults: UserDefaults

    public static let bookmarkKey = "HomeDirectoryBookmark"

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        // Read once at init time — happens at app startup before any views render.
        self.hasStoredBookmark = defaults.data(forKey: Self.bookmarkKey) != nil
    }

    /// Restore a previously stored bookmark.
    ///
    /// Call this only from user-initiated flows (e.g. Permissions tab onAppear)
    /// because resolving a stale bookmark can trigger an OS permission dialog
    /// during development (when the app is re-signed).
    public func restoreBookmark() {
        guard let data = defaults.data(forKey: Self.bookmarkKey) else {
            hasStoredBookmark = false
            accessState = .noBookmark
            return
        }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                // Re-create bookmark from the resolved URL (Apple-recommended)
                let freshData = try url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                defaults.set(freshData, forKey: Self.bookmarkKey)
            }

            guard url.startAccessingSecurityScopedResource() else {
                accessState = .bookmarkStale
                return
            }

            scopedURL = url
            accessState = .accessGranted
        } catch {
            accessState = .bookmarkStale
        }
    }

    /// Store bookmark data for a granted URL and start accessing it.
    public func storeAndAccess(url: URL) throws {
        let bookmarkData = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(bookmarkData, forKey: Self.bookmarkKey)
        hasStoredBookmark = true

        guard url.startAccessingSecurityScopedResource() else {
            accessState = .bookmarkStale
            return
        }

        scopedURL = url
        accessState = .accessGranted
    }

    /// Revoke stored access and remove the bookmark.
    public func revokeAccess() {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
        defaults.removeObject(forKey: Self.bookmarkKey)
        hasStoredBookmark = false
        accessState = .noBookmark
    }
}
