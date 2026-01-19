import Foundation
import SwiftUI

@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published private(set) var currentUser: User?
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isLoading = false

    private let apiClient: APIClient
    private let keychainManager: KeychainManager

    private init(
        apiClient: APIClient = .shared,
        keychainManager: KeychainManager = .shared
    ) {
        self.apiClient = apiClient
        self.keychainManager = keychainManager

        Task {
            await checkAuthStatus()
        }
    }

    func checkAuthStatus() async {
        let hasTokens = await keychainManager.hasValidTokens()
        if hasTokens {
            do {
                let user: User = try await apiClient.request(
                    endpoint: .me,
                    responseType: User.self
                )
                currentUser = user
                isAuthenticated = true
            } catch {
                // Token invalid, clear it
                await keychainManager.deleteTokens()
                isAuthenticated = false
                currentUser = nil
            }
        } else {
            isAuthenticated = false
            currentUser = nil
        }
    }

    func register(name: String, email: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }

        let user: User = try await apiClient.request(
            endpoint: .register,
            body: UserRegister(name: name, email: email, password: password),
            responseType: User.self
        )

        // Now log in
        _ = try await apiClient.login(email: email, password: password)
        currentUser = user
        isAuthenticated = true
    }

    func login(email: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }

        _ = try await apiClient.login(email: email, password: password)

        let user: User = try await apiClient.request(
            endpoint: .me,
            responseType: User.self
        )
        currentUser = user
        isAuthenticated = true
    }

    func logout() async {
        await apiClient.logout()
        do {
            try await SyncManager.shared.clearAllData()
        } catch {
            print("Failed to clear local data: \(error)")
        }
        currentUser = nil
        isAuthenticated = false
    }
}
