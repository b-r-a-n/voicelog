import Foundation

enum APIError: Error, LocalizedError {
    case unauthorized(String?)
    case badRequest(String)
    case forbidden(String)
    case notFound
    case serverError(Int)
    case networkError(Error)
    case decodingFailed(Error)
    case encodingFailed
    case tokenRefreshFailed
    case unknown

    var errorDescription: String? {
        switch self {
        case .unauthorized(let message):
            return message ?? "Unauthorized"
        case .badRequest(let message):
            return message
        case .forbidden(let message):
            return message
        case .notFound:
            return "Resource not found"
        case .serverError(let code):
            return "Server error (\(code))"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingFailed(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .encodingFailed:
            return "Failed to encode request"
        case .tokenRefreshFailed:
            return "Session expired. Please log in again."
        case .unknown:
            return "An unknown error occurred"
        }
    }
}

struct APIErrorResponse: Decodable {
    let detail: String
}
