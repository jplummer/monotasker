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
}
