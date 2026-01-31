import Foundation

actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let keychainManager: KeychainManager
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private var isRefreshing = false
    private var refreshContinuations: [CheckedContinuation<AuthToken, Error>] = []

    // Retry configuration
    private let maxRetryAttempts = 3
    private let baseRetryDelay: UInt64 = 1_000_000_000 // 1 second in nanoseconds

    init(
        session: URLSession = .shared,
        keychainManager: KeychainManager = .shared
    ) {
        self.session = session
        self.keychainManager = keychainManager

        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    // MARK: - Public API

    func request<T: Decodable>(
        endpoint: APIEndpoint,
        body: (any Encodable)? = nil,
        responseType: T.Type
    ) async throws -> T {
        let request = try await buildRequest(endpoint: endpoint, body: body)
        return try await executeWithRetry(request: request, endpoint: endpoint)
    }

    func requestVoid(
        endpoint: APIEndpoint,
        body: (any Encodable)? = nil
    ) async throws {
        let request = try await buildRequest(endpoint: endpoint, body: body)
        let _: EmptyResponse = try await executeWithRetry(request: request, endpoint: endpoint)
    }

    /// Downloads raw file data (not JSON) from the given endpoint
    /// - Returns: Tuple of (file data, optional filename from Content-Disposition header)
    func downloadFile(endpoint: APIEndpoint) async throws -> (Data, String?) {
        let request = try await buildRequest(endpoint: endpoint, body: nil)
        return try await executeFileDownloadWithRetry(request: request, endpoint: endpoint)
    }

    func login(email: String, password: String) async throws -> AuthToken {
        var request = URLRequest(url: APIEndpoint.login.url)
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let formData = "username=\(email.urlEncoded)&password=\(password.urlEncoded)"
        request.httpBody = formData.data(using: .utf8)

        let token: AuthToken = try await execute(request: request)
        await keychainManager.saveTokens(token)
        return token
    }

    func logout() async {
        await keychainManager.deleteTokens()
    }

    // MARK: - Private Methods

    private func buildRequest(
        endpoint: APIEndpoint,
        body: (any Encodable)?
    ) async throws -> URLRequest {
        var request = URLRequest(url: endpoint.url)
        request.httpMethod = endpoint.method.rawValue

        if endpoint.requiresAuth {
            guard let token = await keychainManager.getAccessToken() else {
                throw APIError.unauthorized(nil)
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                request.httpBody = try encoder.encode(body)
            } catch {
                throw APIError.encodingFailed
            }
        }

        return request
    }

    private func executeWithRetry<T: Decodable>(
        request: URLRequest,
        endpoint: APIEndpoint,
        attempt: Int = 1
    ) async throws -> T {
        do {
            return try await execute(request: request)
        } catch APIError.unauthorized(_) where endpoint.requiresAuth {
            // Token refresh is separate from retry logic
            let newToken = try await refreshToken()

            var newRequest = request
            newRequest.setValue("Bearer \(newToken.accessToken)", forHTTPHeaderField: "Authorization")

            return try await execute(request: newRequest)
        } catch let error where shouldRetry(error: error, attempt: attempt) {
            // Exponential backoff: 1s, 2s, 4s
            let delay = baseRetryDelay * UInt64(1 << (attempt - 1))
            try await Task.sleep(nanoseconds: delay)

            return try await executeWithRetry(request: request, endpoint: endpoint, attempt: attempt + 1)
        }
    }

    /// Determines if an error is retryable (network errors and 5xx server errors)
    private func shouldRetry(error: Error, attempt: Int) -> Bool {
        guard attempt < maxRetryAttempts else { return false }

        switch error {
        case APIError.networkError:
            return true
        case APIError.serverError:
            return true
        default:
            return false
        }
    }

    private func executeFileDownloadWithRetry(
        request: URLRequest,
        endpoint: APIEndpoint,
        attempt: Int = 1
    ) async throws -> (Data, String?) {
        do {
            return try await executeFileDownload(request: request)
        } catch APIError.unauthorized(_) where endpoint.requiresAuth {
            // Token refresh is separate from retry logic
            let newToken = try await refreshToken()

            var newRequest = request
            newRequest.setValue("Bearer \(newToken.accessToken)", forHTTPHeaderField: "Authorization")

            return try await executeFileDownload(request: newRequest)
        } catch let error where shouldRetry(error: error, attempt: attempt) {
            // Exponential backoff: 1s, 2s, 4s
            let delay = baseRetryDelay * UInt64(1 << (attempt - 1))
            try await Task.sleep(nanoseconds: delay)

            return try await executeFileDownloadWithRetry(request: request, endpoint: endpoint, attempt: attempt + 1)
        }
    }

    private func executeFileDownload(request: URLRequest) async throws -> (Data, String?) {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.unknown
        }

        switch httpResponse.statusCode {
        case 200..<300:
            let filename = extractFilename(from: httpResponse)
            return (data, filename)

        case 401:
            let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data)
            throw APIError.unauthorized(errorResponse?.detail)

        case 403:
            let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data)
            throw APIError.forbidden(errorResponse?.detail ?? "Access denied")

        case 404:
            throw APIError.notFound

        case 500..<600:
            throw APIError.serverError(httpResponse.statusCode)

        default:
            throw APIError.unknown
        }
    }

    private func extractFilename(from response: HTTPURLResponse) -> String? {
        guard let contentDisposition = response.value(forHTTPHeaderField: "Content-Disposition") else {
            return nil
        }

        // Parse Content-Disposition header for filename
        // Handles: attachment; filename="example.pdf" or attachment; filename=example.pdf
        let components = contentDisposition.components(separatedBy: ";")
        for component in components {
            let trimmed = component.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("filename=") {
                var filename = String(trimmed.dropFirst("filename=".count))
                // Remove surrounding quotes if present
                if filename.hasPrefix("\"") && filename.hasSuffix("\"") {
                    filename = String(filename.dropFirst().dropLast())
                }
                return filename.isEmpty ? nil : filename
            }
        }
        return nil
    }

    private func execute<T: Decodable>(request: URLRequest) async throws -> T {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.unknown
        }

        switch httpResponse.statusCode {
        case 200..<300:
            if T.self == EmptyResponse.self {
                return EmptyResponse() as! T
            }
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decodingFailed(error)
            }

        case 400:
            let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data)
            throw APIError.badRequest(errorResponse?.detail ?? "Bad request")

        case 401:
            let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data)
            throw APIError.unauthorized(errorResponse?.detail)

        case 403:
            let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data)
            throw APIError.forbidden(errorResponse?.detail ?? "Access denied")

        case 404:
            throw APIError.notFound

        case 500..<600:
            throw APIError.serverError(httpResponse.statusCode)

        default:
            throw APIError.unknown
        }
    }

    private func refreshToken() async throws -> AuthToken {
        if isRefreshing {
            return try await withCheckedThrowingContinuation { continuation in
                refreshContinuations.append(continuation)
            }
        }

        isRefreshing = true

        do {
            guard let refreshToken = await keychainManager.getRefreshToken() else {
                throw APIError.tokenRefreshFailed
            }

            var request = URLRequest(url: APIEndpoint.refresh.url)
            request.httpMethod = HTTPMethod.post.rawValue
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(RefreshRequest(refreshToken: refreshToken))

            let token: AuthToken = try await execute(request: request)
            await keychainManager.saveTokens(token)

            isRefreshing = false
            for continuation in refreshContinuations {
                continuation.resume(returning: token)
            }
            refreshContinuations.removeAll()

            return token
        } catch {
            isRefreshing = false
            for continuation in refreshContinuations {
                continuation.resume(throwing: APIError.tokenRefreshFailed)
            }
            refreshContinuations.removeAll()

            await keychainManager.deleteTokens()
            throw APIError.tokenRefreshFailed
        }
    }
}

private struct EmptyResponse: Decodable {}

private extension String {
    var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}
