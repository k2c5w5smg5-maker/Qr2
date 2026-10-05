import Foundation

/// What kind of thing the QR code points at.
enum QRKind: String, CaseIterable, Identifiable, Codable {
    case website
    case photo
    case youtube
    case meta

    var id: String { rawValue }

    var title: String {
        switch self {
        case .website: return "Website"
        case .photo: return "Photo"
        case .youtube: return "YouTube"
        case .meta: return "Meta"
        }
    }

    var symbol: String {
        switch self {
        case .website: return "globe"
        case .photo: return "photo"
        case .youtube: return "play.rectangle.fill"
        case .meta: return "person.2.fill"
        }
    }

    var placeholder: String {
        switch self {
        case .website: return "example.com"
        case .photo: return "Paste a photo link"
        case .youtube: return "YouTube link, video ID or @channel"
        case .meta: return ""
        }
    }

    var help: String {
        switch self {
        case .website:
            return "Any web address. We add https:// for you if it is missing."
        case .photo:
            return "Paste a share link from Photos (iCloud link), Google Photos, Dropbox, or any image address."
        case .youtube:
            return "Paste a video, Shorts, playlist or channel link. Video links are shortened to youtu.be."
        case .meta:
            return "Link a Facebook, Instagram, WhatsApp, Threads or Messenger profile."
        }
    }
}

/// Meta-owned platforms supported by the Meta target.
enum MetaPlatform: String, CaseIterable, Identifiable, Codable {
    case facebook
    case instagram
    case whatsapp
    case threads
    case messenger

    var id: String { rawValue }

    var title: String {
        switch self {
        case .facebook: return "Facebook"
        case .instagram: return "Instagram"
        case .whatsapp: return "WhatsApp"
        case .threads: return "Threads"
        case .messenger: return "Messenger"
        }
    }

    var placeholder: String {
        switch self {
        case .facebook: return "Page name or facebook.com link"
        case .instagram: return "@username or instagram.com link"
        case .whatsapp: return "Phone number with country code"
        case .threads: return "@username or threads.net link"
        case .messenger: return "Username or m.me link"
        }
    }

    /// Domains that are accepted when the user pastes a full link.
    var domains: [String] {
        switch self {
        case .facebook: return ["facebook.com", "fb.com", "fb.me"]
        case .instagram: return ["instagram.com", "instagr.am"]
        case .whatsapp: return ["wa.me", "whatsapp.com"]
        case .threads: return ["threads.net", "threads.com"]
        case .messenger: return ["m.me", "messenger.com"]
        }
    }
}

/// Everything the user typed to describe the destination of a code.
struct QRTarget: Codable, Equatable, Hashable {
    var kind: QRKind = .website
    var input: String = ""
    var metaPlatform: MetaPlatform = .instagram

    /// The URL the QR code will encode, or nil when the input is not usable yet.
    var resolvedURL: URL? { TargetResolver.resolve(self) }

    /// A short label used when the code is saved to the library.
    var suggestedTitle: String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .meta:
            return "\(metaPlatform.title) · \(trimmed)"
        default:
            if let host = resolvedURL?.host, kind != .youtube {
                return "\(kind.title) · \(host)"
            }
            return "\(kind.title) · \(trimmed)"
        }
    }
}

/// Turns user input into a canonical URL for each target kind.
enum TargetResolver {
    static func resolve(_ target: QRTarget) -> URL? {
        switch target.kind {
        case .website: return website(target.input)
        case .photo: return website(target.input)
        case .youtube: return youtube(target.input)
        case .meta: return meta(target.metaPlatform, target.input)
        }
    }

    /// Accepts "example.com", "www.example.com/page" or a full URL.
    static func website(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        let lower = text.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            text = "https://" + text
        }
        guard let url = URL(string: text),
              let host = url.host, host.contains("."),
              !host.hasPrefix("."), !host.hasSuffix(".") else { return nil }
        return url
    }

    /// Accepts a video ID, a youtu.be / youtube.com link, or an @handle.
    static func youtube(_ raw: String) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if isVideoID(text) {
            return URL(string: "https://youtu.be/\(text)")
        }
        if text.hasPrefix("@"), text.count > 1, !text.contains("/") {
            return URL(string: "https://www.youtube.com/\(text)")
        }

        guard let url = website(text), let host = url.host?.lowercased() else { return nil }
        let allowed = ["youtube.com", "youtu.be", "youtube-nocookie.com"]
        guard allowed.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { return nil }

        let parts = Array(url.pathComponents.dropFirst())
        var videoID: String?
        if host.hasSuffix("youtu.be") {
            videoID = parts.first
        } else if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                  let value = items.first(where: { $0.name == "v" })?.value {
            videoID = value
        } else if parts.count >= 2, ["shorts", "live", "embed", "v"].contains(parts[0]) {
            videoID = parts[1]
        }

        if let videoID, isVideoID(videoID) {
            return URL(string: "https://youtu.be/\(videoID)")
        }
        return url
    }

    /// Accepts a handle, a phone number (WhatsApp) or a full link on the platform's domains.
    static func meta(_ platform: MetaPlatform, _ raw: String) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let lower = text.lowercased()

        let looksLikeLink = lower.hasPrefix("http://") || lower.hasPrefix("https://")
            || lower.hasPrefix("www.") || platform.domains.contains(where: { lower.contains($0) })
        if looksLikeLink {
            guard let url = website(text), let host = url.host?.lowercased(),
                  platform.domains.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { return nil }
            return url
        }

        if platform == .whatsapp {
            let digits = text.filter(\.isNumber)
            guard digits.count >= 7, digits.count <= 15 else { return nil }
            return URL(string: "https://wa.me/\(digits)")
        }

        let handle = text.hasPrefix("@") ? String(text.dropFirst()) : text
        guard !handle.isEmpty, isHandle(handle) else { return nil }
        switch platform {
        case .facebook: return URL(string: "https://www.facebook.com/\(handle)")
        case .instagram: return URL(string: "https://www.instagram.com/\(handle)/")
        case .threads: return URL(string: "https://www.threads.net/@\(handle)")
        case .messenger: return URL(string: "https://m.me/\(handle)")
        case .whatsapp: return nil
        }
    }

    private static func isVideoID(_ text: String) -> Bool {
        text.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil
    }

    private static func isHandle(_ text: String) -> Bool {
        text.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-" }
    }
}
