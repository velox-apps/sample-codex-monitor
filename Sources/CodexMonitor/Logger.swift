import Foundation

enum AppLogLevel: Int, Comparable {
  case debug = 0
  case info = 1
  case warn = 2
  case error = 3
  case off = 4

  static func < (lhs: AppLogLevel, rhs: AppLogLevel) -> Bool {
    lhs.rawValue < rhs.rawValue
  }

  static func fromEnv() -> AppLogLevel {
    let raw = ProcessInfo.processInfo.environment["CODEXMONITOR_LOG_LEVEL"]?.lowercased()
    switch raw {
    case "debug":
      return .debug
    case "info":
      return .info
    case "warn", "warning":
      return .warn
    case "error":
      return .error
    case "off", "none", "silent":
      return .off
    default:
      return .info
    }
  }

  var label: String {
    switch self {
    case .debug:
      return "DEBUG"
    case .info:
      return "INFO"
    case .warn:
      return "WARN"
    case .error:
      return "ERROR"
    case .off:
      return "OFF"
    }
  }
}

enum AppLogger {
  private static let fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("CodexMonitor.log")
  private static let minimumLevel = AppLogLevel.fromEnv()

  static func log(_ message: String, level: AppLogLevel = .debug) {
    guard level >= minimumLevel else {
      return
    }

    let stamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(stamp)] [\(level.label)] \(message)\n"
    guard let data = line.data(using: .utf8) else {
      return
    }

    FileHandle.standardError.write(data)

    if !FileManager.default.fileExists(atPath: fileURL.path) {
      FileManager.default.createFile(atPath: fileURL.path, contents: nil)
    }
    if let handle = try? FileHandle(forWritingTo: fileURL) {
      do {
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
      } catch {
        // Ignore file logging failures.
      }
      try? handle.close()
    }
  }
}
