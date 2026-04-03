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

    private var scopedURL: URL?
    private let defaults: UserDefaults

    public static let bookmarkKey = "HomeDirectoryBookmark"

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Restore a previously stored bookmark on app launch.
    public func restoreBookmark() {
        guard let data = defaults.data(forKey: Self.bookmarkKey) else {
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
        accessState = .noBookmark
    }
}
