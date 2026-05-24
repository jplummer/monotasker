import Foundation

/// Central place for display name and default Reminders list title. Change `CFBundleDisplayName` in Info.plist to rename.
enum AppConfig {
  static var appName: String {
    if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
       !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return name
    }
    return "Monotasker"
  }

  static var defaultListName: String { appName }

  static let telemetryDeckAppID = "42A77D2A-370F-4941-9D01-EC105B518BCE"

  /// VoiceOver reads "Monotasker" as a single phonetic token and mispronounces it.
  /// Two words with a space produces the correct "Mono Tasker" cadence.
  static let appNamePronunciation = "Mono Tasker"

  /// Returns `name` with any occurrence of `appName` replaced by `appNamePronunciation`,
  /// for use in `.accessibilityLabel` modifiers.
  static func voiceOverName(_ name: String) -> String {
    name.replacingOccurrences(of: appName, with: appNamePronunciation)
  }
}
