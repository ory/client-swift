import Foundation

actor DeviceOperationCoordinator {
    static let shared = DeviceOperationCoordinator()
    private var activeScopes: Set<String> = []

    func perform<Result: Sendable>(
        scope: String,
        operation: @Sendable () async throws -> Result
    ) async throws -> Result {
        try Task.checkCancellation()
        guard activeScopes.insert(scope).inserted else {
            throw OryClientError.deviceAuthenticationOperationInProgress
        }
        defer { activeScopes.remove(scope) }
        return try await operation()
    }
}
