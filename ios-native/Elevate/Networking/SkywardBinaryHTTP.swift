import Foundation

/// Authenticated binary resources stay on the configured Skyward origin and
/// are never logged. Resource URLs containing session values remain transient.
enum SkywardBinaryHTTP {
    struct Resource: Sendable {
        var data: Data
        var mimeType: String
    }

    static func resourceURL(relativePath: String, baseUrl: String) throws -> URL {
        guard let base = URL(string: baseUrl), base.scheme == "https",
              let url = URL(string: relativePath, relativeTo: base)?.absoluteURL,
              url.scheme == base.scheme, url.host?.lowercased() == base.host?.lowercased(),
              url.port == base.port, url.user == nil, url.password == nil,
              url.fragment == nil else {
            throw SkywardError.invalidResponse("resource location is invalid")
        }
        return url
    }

    static func loadPhoto(relativePath: String, baseUrl: String) async throws -> Data {
        let url = try resourceURL(relativePath: relativePath, baseUrl: baseUrl)
        guard url.lastPathComponent.range(of: #"^qdirconfig\d+\.p$"#, options: .regularExpression) != nil,
              URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: { $0.name == "StuPic" }) == true else {
            throw SkywardError.invalidResponse("student photo location is unrecognized")
        }
        let result = try await fetch(url: url, maximumBytes: 4_000_000,
                                     allowedMIMETypes: ["image/jpeg", "image/png", "image/gif", "image/heic", "image/heif"])
        return result.data
    }

    static func validateContent(_ data: Data, mimeType: String) throws {
        let bytes = [UInt8](data.prefix(16))
        let valid: Bool
        switch mimeType {
        case "application/pdf": valid = data.starts(with: Data("%PDF-".utf8))
        case "image/jpeg": valid = bytes.starts(with: [0xFF, 0xD8, 0xFF])
        case "image/png": valid = bytes.starts(with: [137, 80, 78, 71, 13, 10, 26, 10])
        case "image/gif": valid = data.starts(with: Data("GIF87a".utf8)) || data.starts(with: Data("GIF89a".utf8))
        case "image/heic", "image/heif":
            valid = bytes.count >= 12 && Array(bytes[4..<8]) == Array("ftyp".utf8)
                && ["heic", "heix", "hevc", "hevx", "mif1", "msf1"].contains(String(bytes: bytes[8..<12], encoding: .ascii) ?? "")
        default: valid = false
        }
        guard valid else { throw SkywardError.invalidResponse("resource contents do not match its format") }
    }

    static func fetch(url: URL, maximumBytes: Int, allowedMIMETypes: Set<String>) async throws -> Resource {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        let delegate = SameOriginRedirectDelegate(origin: url)
        let (bytes, response) = try await SkywardHTTP.session.bytes(for: request, delegate: delegate)
        guard let http = response as? HTTPURLResponse, let finalURL = http.url,
              SameOriginRedirectDelegate.matches(finalURL, origin: url) else {
            throw SkywardError.invalidResponse("resource response is unrecognized")
        }
        try SkywardHTTP.checkSessionRedirect(finalURL)
        if http.statusCode == 401 || http.statusCode == 403 { throw SkywardError.sessionExpired }
        var mime = (http.mimeType ?? "").lowercased()
        let isText = mime.hasPrefix("text/") || mime.contains("xml") || mime.contains("json")
        let bound = isText ? min(maximumBytes, 4_000_000) : maximumBytes
        guard http.expectedContentLength <= Int64(bound) else {
            throw SkywardError.invalidResponse("resource exceeds size limit")
        }
        var data = Data()
        if http.expectedContentLength > 0 { data.reserveCapacity(Int(http.expectedContentLength)) }
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < bound else { throw SkywardError.invalidResponse("resource exceeds size limit") }
            data.append(byte)
        }
        if isText, let text = String(data: data, encoding: .utf8) {
            try SkywardHTTP.checkSessionExpired(text)
        }
        guard (200..<300).contains(http.statusCode), allowedMIMETypes.contains(mime), !data.isEmpty else {
            throw SkywardError.invalidResponse("resource is unavailable or has an unsupported format")
        }
        if mime == "application/octet-stream" {
            guard let recognized = ["application/pdf", "image/jpeg", "image/png", "image/gif"].first(where: { (try? validateContent(data, mimeType: $0)) != nil }) else {
                throw SkywardError.invalidResponse("document format is unsupported")
            }
            mime = recognized
        }
        try validateContent(data, mimeType: mime)
        return Resource(data: data, mimeType: mime)
    }
}

private final class SameOriginRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let origin: URL
    init(origin: URL) { self.origin = origin }

    static func matches(_ target: URL, origin: URL) -> Bool {
        target.scheme == origin.scheme && target.host?.lowercased() == origin.host?.lowercased()
            && target.port == origin.port && target.user == nil && target.password == nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map { Self.matches($0, origin: origin) } == true ? request : nil)
    }
}
