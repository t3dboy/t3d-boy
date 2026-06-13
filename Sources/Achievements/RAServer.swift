// T3d Boy — RetroAchievements HTTP transport.
//
// rc_client hands us a fully-formed request (URL, optional POST body, content
// type) plus a C response callback and an opaque callback_data pointer. We perform
// the request asynchronously with URLSession, then invoke the rcheevos response
// callback ON THE MAIN QUEUE — rc_client is single-threaded and expects responses
// to be delivered on the same thread that calls rc_client_do_frame (which we run
// on the main queue). The response body must outlive the synchronous callback, so
// we keep the Data alive for the duration of the call.

import Foundation
import rcheevos

enum RAServer {
    /// Set true to log requests/responses (tokens are redacted). Off by default.
    static var verboseLogging = false

    /// The rc_client server_call callback. Non-capturing → C function pointer.
    static let callback: rc_client_server_call_t = { request, callback, callbackData, _ in
        guard let request, let url = request.pointee.url,
              let nsURL = URL(string: String(cString: url)) else {
            // Hand rcheevos a synthetic client-error so it can fail cleanly.
            RAServer.deliverError(callback, callbackData, status: Int32(RC_API_SERVER_RESPONSE_CLIENT_ERROR))
            return
        }

        var req = URLRequest(url: nsURL)
        req.timeoutInterval = 30

        if let post = request.pointee.post_data {
            let body = String(cString: post)
            if !body.isEmpty {
                req.httpMethod = "POST"
                req.httpBody = body.data(using: .utf8)
                if let ct = request.pointee.content_type {
                    req.setValue(String(cString: ct), forHTTPHeaderField: "Content-Type")
                }
            }
        }

        if RAServer.verboseLogging {
            print("[RA] \(req.httpMethod ?? "GET") \(RAServer.redact(nsURL.absoluteString))")
        }

        let task = URLSession.shared.dataTask(with: req) { data, response, error in
            let http = response as? HTTPURLResponse
            let status = Int32(http?.statusCode ?? 0)

            // Marshal back onto the main queue: rc_client is not thread-safe and
            // responses must land on the do_frame thread.
            DispatchQueue.main.async {
                if let error {
                    if RAServer.verboseLogging { print("[RA] network error: \(error.localizedDescription)") }
                    RAServer.deliverError(callback, callbackData,
                                          status: Int32(RC_API_SERVER_RESPONSE_RETRYABLE_CLIENT_ERROR))
                    return
                }
                let payload = data ?? Data()
                payload.withUnsafeBytes { raw in
                    var resp = rc_api_server_response_t()
                    resp.body = raw.bindMemory(to: CChar.self).baseAddress
                    resp.body_length = payload.count
                    resp.http_status_code = status
                    callback?(&resp, callbackData)
                }
            }
        }
        task.resume()
    }

    /// Invoke the rcheevos callback with an empty body and a sentinel status code,
    /// so rc_client treats the request as a (retryable) client failure.
    private static func deliverError(_ callback: rc_client_server_callback_t?,
                                     _ data: UnsafeMutableRawPointer?,
                                     status: Int32) {
        DispatchQueue.main.async {
            var resp = rc_api_server_response_t()
            resp.body = nil
            resp.body_length = 0
            resp.http_status_code = status
            callback?(&resp, data)
        }
    }

    /// Strip query-string secrets (token=, p=) before logging a URL.
    private static func redact(_ url: String) -> String {
        var s = url
        for key in ["token", "p", "password"] {
            if let range = s.range(of: "\(key)=") {
                let valueStart = range.upperBound
                let valueEnd = s[valueStart...].firstIndex(of: "&") ?? s.endIndex
                s.replaceSubrange(valueStart..<valueEnd, with: "REDACTED")
            }
        }
        return s
    }
}
