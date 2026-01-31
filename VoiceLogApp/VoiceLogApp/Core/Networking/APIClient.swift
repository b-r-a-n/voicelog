import Foundation

actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let keychainManager: KeychainManager
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private var isRefreshing = false
    private var refreshContinuations: [CheckedContinuation<AuthToken, Error>] = []

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
        endpoint: APIEndpoint
    ) async throws -> T {
        do {
            return try await execute(request: request)
        } catch APIError.unauthorized(_) where endpoint.requiresAuth {
            let newToken = try await refreshToken()

            var newRequest = request
            newRequest.setValue("Bearer \(newToken.accessToken)", forHTTPHeaderField: "Authorization")

            return try await execute(request: newRequest)
        }
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

        // DEBUG: Log raw response for auth debugging
        #if DEBUG
        let rawJSON = String(data: data, encoding: .utf8) ?? "<non-UTF8 data>"
        print("[APIClient DEBUG] \(request.httpMethod ?? "?") \(request.url?.path ?? "?")")
        print("[APIClient DEBUG] Status: \(httpResponse.statusCode)")
        print("[APIClient DEBUG] Response type: \(T.self)")
        print("[APIClient DEBUG] Raw JSON: \(rawJSON)")
        #endif

        switch httpResponse.statusCode {
        case 200..<300:
            if T.self == EmptyResponse.self {
                return EmptyResponse() as! T
            }
            do {
                return try decoder.decode(T.self, from: data)
            } catch let decodingError {
                // DEBUG: Log detailed decoding error
                #if DEBUG
                print("[APIClient DEBUG] Decoding failed for type: \(T.self)")
                if let error = decodingError as? DecodingError {
                    switch error {
                    case .keyNotFound(let key, let context):
                        print("[APIClient DEBUG] Missing key: '\(key.stringValue)' at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                    case .typeMismatch(let type, let context):
                        print("[APIClient DEBUG] Type mismatch: expected \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                        print("[APIClient DEBUG] Debug description: \(context.debugDescription)")
                    case .valueNotFound(let type, let context):
                        print("[APIClient DEBUG] Value not found: expected \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                    case .dataCorrupted(let context):
                        print("[APIClient DEBUG] Data corrupted at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                        print("[APIClient DEBUG] Debug description: \(context.debugDescription)")
                    @unknown default:
                        print("[APIClient DEBUG] Unknown decoding error: \(error)")
                    }
                } else {
                    print("[APIClient DEBUG] Non-DecodingError: \(decodingError)")
                }
                #endif
                throw APIError.decodingFailed(decodingError)
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
