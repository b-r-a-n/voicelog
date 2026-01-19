import Foundation

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

enum APIEndpoint {
    static var baseURL: URL {
        #if USE_PRODUCTION_API || !DEBUG
        URL(string: "https://voicelog.fly.dev")!
        #elseif targetEnvironment(simulator)
        URL(string: "http://localhost:8000")!
        #else
        // Real devices need the Mac's local IP
        URL(string: "http://192.168.1.217:8000")!
        #endif
    }

    // Auth
    case register
    case login
    case refresh
    case me

    // Notes
    case createNote
    case listNotes
    case getNote(id: Int)
    case updateNote(id: Int)
    case deleteNote(id: Int)
    case summarizeNote(id: Int)
    case exportNote(id: Int)

    // Tags
    case createTag
    case listTags
    case updateTag(id: Int)
    case deleteTag(id: Int)
    case addTagToNote(noteId: Int)
    case removeTagFromNote(noteId: Int, tagId: Int)

    // Sync
    case sync

    // Export
    case downloadExport(exportId: String)

    var path: String {
        switch self {
        case .register: return "/auth/register"
        case .login: return "/auth/login"
        case .refresh: return "/auth/refresh"
        case .me: return "/auth/me"
        case .createNote, .listNotes: return "/notes/"
        case .getNote(let id), .updateNote(let id), .deleteNote(let id):
            return "/notes/\(id)"
        case .summarizeNote(let id): return "/notes/\(id)/summarize"
        case .exportNote(let id): return "/notes/\(id)/export"
        case .createTag, .listTags: return "/tags/"
        case .updateTag(let id), .deleteTag(let id): return "/tags/\(id)"
        case .addTagToNote(let noteId): return "/notes/\(noteId)/tags"
        case .removeTagFromNote(let noteId, let tagId): return "/notes/\(noteId)/tags/\(tagId)"
        case .sync: return "/sync"
        case .downloadExport(let exportId): return "/export/\(exportId)"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .register, .login, .refresh, .createNote, .summarizeNote, .exportNote,
             .createTag, .addTagToNote, .sync:
            return .post
        case .me, .listNotes, .getNote, .listTags, .downloadExport:
            return .get
        case .updateNote, .updateTag:
            return .put
        case .deleteNote, .deleteTag, .removeTagFromNote:
            return .delete
        }
    }

    var requiresAuth: Bool {
        switch self {
        case .register, .login, .refresh:
            return false
        default:
            return true
        }
    }

    var url: URL {
        APIEndpoint.baseURL.appendingPathComponent(path)
    }
}
