#if DEBUG
import Foundation

struct NetworkLogEntry: Identifiable, Sendable {

    let id: UUID
    let date: Date
    let method: String
    let url: URL
    let requestHeaders: [String: String]
    let requestBody: Data?

    var statusCode: Int?
    var responseHeaders: [String: String]?
    var responseBody: Data?
    var errorDescription: String?

    var isFailure: Bool {
        if errorDescription != nil { return true }
        if let statusCode { return !(200..<300).contains(statusCode) }
        return false
    }

    var curlDescription: String {
        var lines = ["curl '\(url.absoluteString)'", "-X \(method)"]
        for (name, value) in requestHeaders.sorted(by: { $0.key < $1.key }) {
            lines.append("-H '\(name): \(value)'")
        }
        if let body = requestBody, let text = String(data: body, encoding: .utf8), !text.isEmpty {
            lines.append("--data '\(text)'")
        }
        var result = lines.joined(separator: " \\\n  ")
        if let statusCode {
            result += "\n\n# HTTP \(statusCode)"
        }
        if let error = errorDescription {
            result += "\n# Error: \(error)"
        }
        if let body = responseBody, let text = String(data: body, encoding: .utf8), !text.isEmpty {
            result += "\n# Response:\n\(text)"
        }
        return result
    }
}

actor NetworkHistoryStore {

    private var entries: [NetworkLogEntry] = []
    private let limit: Int

    init(limit: Int = 200) {
        self.limit = limit
    }

    func recordRequest(id: UUID, method: String, url: URL, headers: [String: String], body: Data?) {
        entries.append(
            NetworkLogEntry(id: id, date: Date(), method: method, url: url, requestHeaders: headers, requestBody: body)
        )
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
        }
    }

    func recordResponse(id: UUID, statusCode: Int, headers: [String: String], body: Data) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].statusCode = statusCode
        entries[index].responseHeaders = headers
        entries[index].responseBody = body
    }

    func recordFailure(id: UUID, message: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].errorDescription = message
    }

    func snapshot() -> [NetworkLogEntry] {
        entries.reversed()
    }

    func clear() {
        entries.removeAll()
    }
}
#endif
