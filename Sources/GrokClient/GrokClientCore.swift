import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - GrokClient Core
public class GrokClient {
    let baseURL: String
    let rootBaseURL: String
    let webBaseURL: String
    let cookies: [String: String]
    var session: URLSession
    public var isDebug: Bool = false

    let headers: [String: String] = [
        "accept": "*/*",
        "accept-language": "en-US,en;q=0.9",
        "content-type": "application/json",
        "origin": "https://grok.com",
        "priority": "u=1, i",
        "referer": "https://grok.com/",
        "sec-ch-ua": "\"Chromium\";v=\"148\", \"Google Chrome\";v=\"148\", \"Not/A)Brand\";v=\"99\"",
        "sec-ch-ua-arch": "\"arm\"",
        "sec-ch-ua-bitness": "\"64\"",
        "sec-ch-ua-full-version": "\"148.0.7778.168\"",
        "sec-ch-ua-full-version-list": "\"Chromium\";v=\"148.0.7778.168\", \"Google Chrome\";v=\"148.0.7778.168\", \"Not/A)Brand\";v=\"99.0.0.0\"",
        "sec-ch-ua-mobile": "?0",
        "sec-ch-ua-model": "\"\"",
        "sec-ch-ua-platform": "\"macOS\"",
        "sec-ch-ua-platform-version": "\"15.6.1\"",
        "sec-fetch-dest": "empty",
        "sec-fetch-mode": "cors",
        "sec-fetch-site": "same-origin",
        "user-agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36"
    ]

    enum RestNamespace {
        case appChat
        case root
        case web

        var pathPrefix: String {
            switch self {
            case .appChat:
                return "/rest/app-chat"
            case .root:
                return "/rest"
            case .web:
                return ""
            }
        }
    }

    var cookieHeader: String {
        cookies
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "; ")
    }

    public static let defaultModeId = GrokMode.defaultMode.id

    /// Deprecated Grok 3 server-side system prompt presets.
    ///
    /// These values are kept for source compatibility, but they are no longer
    /// sent to Grok. Configure instructions in Grok agent settings instead.
    public enum PersonalityType: String, CaseIterable {
        case romance = "grok3_personality_romance_me"
        case medicalAdvisor = "grok3_personality_medical_advisor"
        case latestNews = "grok3_personality_latest_news"
        case unhingedComedian = "grok3_personality_unhinged_comedian"
        case loyalFriend = "grok3_personality_loyal_friend"
        case homeworkHelper = "grok3_personality_homework_helper"
        case trustedTherapist = "grok3_personality_trusted_therapist"
        case none = ""

        public var displayName: String {
            switch self {
            case .romance: return "Romance Me"
            case .medicalAdvisor: return "Medical Advisor"
            case .latestNews: return "Latest News"
            case .unhingedComedian: return "Unhinged Comedian"
            case .loyalFriend: return "Loyal Friend"
            case .homeworkHelper: return "Homework Helper"
            case .trustedTherapist: return "Trusted Therapist"
            case .none: return "Default (No Personality)"
            }
        }

        public var description: String {
            switch self {
            case .romance: return "A flirty and romantic personality"
            case .medicalAdvisor: return "A helpful medical information advisor"
            case .latestNews: return "Focused on providing the latest news and current events"
            case .unhingedComedian: return "A wild and unhinged comedian"
            case .loyalFriend: return "A supportive and loyal friend"
            case .homeworkHelper: return "A patient tutor focused on helping with homework"
            case .trustedTherapist: return "A compassionate therapeutic personality"
            case .none: return "Standard Grok personality"
            }
        }
    }

    private static func normalizedBaseURLs(from configuredBaseURL: String?) -> (appChat: String, root: String, web: String) {
        let rawBaseURL = configuredBaseURL
            ?? ProcessInfo.processInfo.environment["GROK_BASE_URL"]
            ?? "https://grok.com/rest"
        let trimmed = rawBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if trimmed.hasSuffix("/rest/app-chat") {
            let root = String(trimmed.dropLast("/app-chat".count))
            let web = String(root.dropLast("/rest".count))
            return (trimmed, root, web)
        }

        if trimmed.hasSuffix("/rest") {
            let web = String(trimmed.dropLast("/rest".count))
            return ("\(trimmed)/app-chat", trimmed, web)
        }

        let root = "\(trimmed)/rest"
        return ("\(root)/app-chat", root, trimmed)
    }

    /// Initializes the GrokClient with cookie credentials
    /// - Parameters:
    ///   - cookies: A dictionary of cookie name-value pairs for authentication
    ///   - isDebug: Whether to print debug information (default: false)
    /// - Throws: GrokError.invalidCredentials if credentials are empty
    public init(
        cookies: [String: String],
        isDebug: Bool = false,
        baseURL configuredBaseURL: String? = nil,
        session injectedSession: URLSession? = nil
    ) throws {
        guard !cookies.isEmpty else {
            throw GrokError.invalidCredentials
        }

        let resolvedBaseURLs = Self.normalizedBaseURLs(from: configuredBaseURL)
        self.baseURL = resolvedBaseURLs.appChat
        self.rootBaseURL = resolvedBaseURLs.root
        self.webBaseURL = resolvedBaseURLs.web
        self.cookies = cookies
        self.isDebug = isDebug

        if let injectedSession {
            self.session = injectedSession
            return
        }

        // #if os(Linux)
        //     // Linux: URLSession cookie support is limited, so skip setting cookies.
        //     self.session = URLSession(configuration: .default)
        // #else
        let configuration = URLSessionConfiguration.default
        var httpCookies = [HTTPCookie]()
        for (name, value) in cookies {
            if let cookie = HTTPCookie(properties: [
                .domain: "grok.com",
                .path: "/",
                .name: name,
                .value: value
            ]) {
                httpCookies.append(cookie)
            }
        }
        configuration.httpCookieStorage?.setCookies(httpCookies, for: URL(string: "https://grok.com"), mainDocumentURL: nil)
        self.session = URLSession(configuration: configuration)
        // #endif
    }
}
