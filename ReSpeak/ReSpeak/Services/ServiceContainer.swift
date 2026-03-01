import Foundation

/// Central service locator for application-wide services.
final class ServiceContainer {
    static let shared = ServiceContainer()
    private init() {}
}
