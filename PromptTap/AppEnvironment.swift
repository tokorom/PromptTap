import Foundation

enum AppEnvironment: CustomStringConvertible {
    case development
    case production

    static let current: AppEnvironment = {
        #if DEBUG
        .development
        #else
        .production
        #endif
    }()

    var description: String {
        switch self {
        case .development:
            return "DEVELOPMENT"
        case .production:
            return "PRODUCTION"
        }
    }

    static func print() {
        Swift.print("AppEnvironment: \(String(describing: current))")
    }
}
