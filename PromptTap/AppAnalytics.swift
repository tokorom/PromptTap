import Mixpanel

final class AppAnalytics {
    static private let mixpanel: MixpanelInstance = {
        let token: String =
            switch AppEnvironment.current {
            case .development:
                "ef60d9f2fcc9fd51fdee374af4bc6c7e"
            case .production:
                "f5570d2b6705e7db39f4e00ae8b8b528"
            }
        Mixpanel.initialize(token: token, trackAutomaticEvents: false)

        return Mixpanel.mainInstance()
    }()

    static func setup() {
        mixpanel.loggingEnabled = (AppEnvironment.current == .development)
    }

    static func track(event: Event, properties: [String: MixpanelType]? = nil) {
        mixpanel.track(event: event.name, properties: properties)
    }
}

// MARK: - Event

extension AppAnalytics {
    struct Event {
        let name: String
        let properties: [String: Any]?

        init(name: String, properties: [String: Any]? = nil) {
            self.name = name
            self.properties = properties
        }

        static func firstLaunch() -> Event { .init(name: "first_launch") }
        static func becomeActive() -> Event { .init(name: "become_active") }
        static func hotkeyTriggered() -> Event { .init(name: "hotkey_triggered") }
    }
}
