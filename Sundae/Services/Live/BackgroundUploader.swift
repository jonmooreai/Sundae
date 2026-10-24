import Foundation
import Synchronization

/// Uploads photo bytes to pre-signed URLs through a background `URLSession`, so a 15-photo
/// dump finishes even if the app is closed mid-way.
///
/// If the process dies before a task completes, its continuation is gone; the upload still
/// finishes, and the pending-post queue retries the dump save with the same upload ids, which
/// the server accepts idempotently.
final class BackgroundUploader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    static let shared = BackgroundUploader()

    private let pending = Mutex<[Int: CheckedContinuation<Void, any Error>]>([:])
    private let statuses = Mutex<[Int: Int]>([:])

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: "com.sundae.app.uploads")
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.allowsCellularAccess = true
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    private var stagingDirectory: URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "uploads", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func upload(_ data: Data, to url: URL, headers: [String: String], contentType: String) async throws {
        let file = stagingDirectory.appending(path: UUID().uuidString + ".jpg")
        try data.write(to: file, options: .atomic)
        defer { try? FileManager.default.removeItem(at: file) }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }

        let task = session.uploadTask(with: request, fromFile: file)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            pending.withLock { $0[task.taskIdentifier] = continuation }
            task.resume()
        }
    }

    // MARK: URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse {
            statuses.withLock { $0[dataTask.taskIdentifier] = http.statusCode }
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let continuation = pending.withLock { $0.removeValue(forKey: task.taskIdentifier) }
        let status = statuses.withLock { $0.removeValue(forKey: task.taskIdentifier) }
            ?? (task.response as? HTTPURLResponse)?.statusCode
        guard let continuation else { return }
        if let error {
            continuation.resume(throwing: error is URLError ? SundaeError.offline : error)
            return
        }
        if let status, !(200..<300).contains(status) {
            continuation.resume(throwing: SundaeError.notAuthorized)
            return
        }
        continuation.resume()
    }
}
