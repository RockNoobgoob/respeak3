import Foundation

/// Central locator for data repository instances.
final class RepositoryContainer {
    static let shared = RepositoryContainer()
    private init() {}
}
