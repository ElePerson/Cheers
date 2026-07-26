import Foundation

struct ServerIdentity: Equatable {
    enum Kind: Equatable {
        case production
        case custom
        case invalid
    }

    let kind: Kind
    let title: String
    let detail: String

    var isProduction: Bool { kind == .production }

    static func resolve(_ rawValue: String) -> ServerIdentity {
        guard let url = APIClient.normalizeBaseURL(rawValue),
              let host = url.host?.lowercased(), !host.isEmpty else {
            return ServerIdentity(
                kind: .invalid,
                title: String(localized: "Invalid server address"),
                detail: String(localized: "Open Advanced server settings to correct it.")
            )
        }

        if host == "www.tocheers.com" || host == "tocheers.com" {
            return ServerIdentity(
                kind: .production,
                title: String(localized: "Cheers Cloud"),
                detail: String(localized: "Official production workspace")
            )
        }

        return ServerIdentity(
            kind: .custom,
            title: String(localized: "Custom workspace"),
            detail: host
        )
    }
}
