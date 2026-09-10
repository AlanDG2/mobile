import Foundation

enum AppConfiguration {
    private static let defaultProdBaseURL = URL(string: "https://vetify.ikeapp.com/")!
    private static let defaultQABaseURL = URL(string: "https://vetify-qa.ikeapp.com/")!

    static var baseURL: URL {
        if let url = urlFromInfoPlist(key: "BASE_URL") {
            return url
        }
        #if VETIFY_QA
        return defaultQABaseURL
        #else
        return defaultProdBaseURL
        #endif
    }

    static var allowedHost: String {
        if let host = stringFromInfoPlist(key: "HOST"), !host.isEmpty {
            return host
        }
        #if VETIFY_QA
        return "vetify-qa.ikeapp.com"
        #else
        return "vetify.ikeapp.com"
        #endif
    }

    /// Resuelve un deep link (path relativo como "/citas/123", o URL absoluta) contra baseURL.
    static func url(forPath path: String) -> URL? {
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)
        }
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return URL(string: trimmed, relativeTo: baseURL)?.absoluteURL
    }

    private static func urlFromInfoPlist(key: String) -> URL? {
        guard let raw = stringFromInfoPlist(key: key) else { return nil }
        return URL(string: raw)
    }

    private static func stringFromInfoPlist(key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else {
            return nil
        }
        return trimmed
    }
}
