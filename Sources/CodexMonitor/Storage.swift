import Foundation

enum StorageError: Error {
  case readFailed(String)
  case writeFailed(String)
}

struct Storage {
  static func readWorkspaces(from path: URL) throws -> [String: WorkspaceEntry] {
    guard FileManager.default.fileExists(atPath: path.path) else {
      return [:]
    }
    let data = try Data(contentsOf: path)
    let list = try JSONDecoder().decode([WorkspaceEntry].self, from: data)
    var result: [String: WorkspaceEntry] = [:]
    for entry in list {
      result[entry.id] = entry
    }
    return result
  }

  static func writeWorkspaces(_ entries: [WorkspaceEntry], to path: URL) throws {
    if let parent = path.deletingLastPathComponent() as URL? {
      try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    }
    let data = try JSONEncoder().encode(entries)
    try data.write(to: path, options: [.atomic])
  }

  static func readSettings(from path: URL) throws -> AppSettings {
    guard FileManager.default.fileExists(atPath: path.path) else {
      return AppSettings()
    }
    let data = try Data(contentsOf: path)
    return try JSONDecoder().decode(AppSettings.self, from: data)
  }

  static func writeSettings(_ settings: AppSettings, to path: URL) throws {
    if let parent = path.deletingLastPathComponent() as URL? {
      try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    }
    let data = try JSONEncoder().encode(settings)
    try data.write(to: path, options: [.atomic])
  }
}
