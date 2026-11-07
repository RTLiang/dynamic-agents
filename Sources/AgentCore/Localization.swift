import Foundation

public enum L10n {
    private static var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        if let url = Bundle.main.url(forResource: "DynamicAgents_AgentCore", withExtension: "bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return .module
        #else
        return .main
        #endif
    }

    public static var preferredLanguage: String { resourceBundle.preferredLocalizations.first ?? "en" }

    private static func bundle(for locale: Locale?) -> Bundle {
        guard let locale,
              let language = Bundle.preferredLocalizations(from: resourceBundle.localizations, forPreferences: [locale.identifier]).first,
              let path = resourceBundle.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return resourceBundle }
        return bundle
    }

    public static func text(_ key: String, locale: Locale? = nil) -> String {
        bundle(for: locale).localizedString(forKey: key, value: key, table: nil)
    }

    public static func format(_ key: String, _ arguments: CVarArg..., locale: Locale? = nil) -> String {
        let bundle = bundle(for: locale)
        let language = locale ?? Locale(identifier: resourceBundle.preferredLocalizations.first ?? "en")
        return String(format: bundle.localizedString(forKey: key, value: key, table: nil), locale: language, arguments: arguments)
    }
}
