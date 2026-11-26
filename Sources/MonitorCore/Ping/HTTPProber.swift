import Foundation

/// Times small HTTPS requests over a kept-alive connection, for hosts whose TCP handshake ends at a
/// nearby edge server (Google Cloud's front ends) while the request itself is answered in the region.
///
/// The time measured is from sending the request to the first byte of the response, taken from
/// URLSession's task metrics, so connection setup and TLS are never counted, even on the first request.
final class HTTPProber: NSObject, URLSessionDataDelegate {
    private let queue: DispatchQueue
    private let onResult: (Int, Float?) -> Void
    private var session: URLSession?
    private var pending: [Int: (target: Int, ms: Float?)] = [:]

    init(queue: DispatchQueue, onResult: @escaping (Int, Float?) -> Void) {
        self.queue = queue
        self.onResult = onResult
    }

    /// Sends one request for `target`. Must be called on `queue`.
    func probe(target: Int, host: String, path: String) {
        guard let url = URL(string: "https://\(host)\(path)") else { return onResult(target, nil) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 2)
        request.setValue("Dotwell", forHTTPHeaderField: "User-Agent")
        let task = ensureSession().dataTask(with: request)
        pending[task.taskIdentifier] = (target, nil)
        task.resume()
    }

    /// Drops the connection and forgets requests in flight. Must be called on `queue`.
    func reset() {
        session?.invalidateAndCancel()
        session = nil
        pending.removeAll()
    }

    private func ensureSession() -> URLSession {
        if let session { return session }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpMaximumConnectionsPerHost = 1
        configuration.timeoutIntervalForRequest = 2
        configuration.waitsForConnectivity = false
        let delegateQueue = OperationQueue()
        delegateQueue.underlyingQueue = queue
        delegateQueue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
        self.session = session
        return session
    }

    // MARK: - URLSessionDataDelegate (called on `queue`)

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard session === self.session, let transaction = metrics.transactionMetrics.last,
            let start = transaction.requestStartDate, let end = transaction.responseStartDate
        else { return }
        pending[task.taskIdentifier]?.ms = Float(end.timeIntervalSince(start) * 1000)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard session === self.session, let request = pending.removeValue(forKey: task.taskIdentifier) else {
            return
        }
        // Any HTTP status counts: the server answered from the region.
        onResult(request.target, error == nil ? request.ms : nil)
    }

    /// The body is never needed.
    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        completionHandler(.allow)
    }
}
