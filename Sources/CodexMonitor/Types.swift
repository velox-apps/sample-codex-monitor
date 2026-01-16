import Foundation

struct GitFileStatus: Codable, Sendable {
  let path: String
  let status: String
  let additions: Int
  let deletions: Int
}

struct GitFileDiff: Codable, Sendable {
  let path: String
  let diff: String
}

struct GitLogEntry: Codable, Sendable {
  let sha: String
  let summary: String
  let author: String
  let timestamp: Int64
}

struct GitLogResponse: Codable, Sendable {
  let total: Int
  let entries: [GitLogEntry]
}

struct BranchInfo: Codable, Sendable {
  let name: String
  let last_commit: Int64
}

struct WorkspaceEntry: Codable, Sendable {
  let id: String
  let name: String
  let path: String
  var codex_bin: String?
  var kind: WorkspaceKind
  var parentId: String?
  var worktree: WorktreeInfo?
  var settings: WorkspaceSettings

  init(
    id: String,
    name: String,
    path: String,
    codex_bin: String?,
    kind: WorkspaceKind = .main,
    parentId: String? = nil,
    worktree: WorktreeInfo? = nil,
    settings: WorkspaceSettings = WorkspaceSettings()
  ) {
    self.id = id
    self.name = name
    self.path = path
    self.codex_bin = codex_bin
    self.kind = kind
    self.parentId = parentId
    self.worktree = worktree
    self.settings = settings
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    path = try container.decode(String.self, forKey: .path)
    codex_bin = try container.decodeIfPresent(String.self, forKey: .codex_bin)
    kind = try container.decodeIfPresent(WorkspaceKind.self, forKey: .kind) ?? .main
    parentId = try container.decodeIfPresent(String.self, forKey: .parentId)
    worktree = try container.decodeIfPresent(WorktreeInfo.self, forKey: .worktree)
    settings = try container.decodeIfPresent(WorkspaceSettings.self, forKey: .settings) ?? WorkspaceSettings()
  }
}

struct WorkspaceInfo: Codable, Sendable {
  let id: String
  let name: String
  let path: String
  let connected: Bool
  let codex_bin: String?
  let kind: WorkspaceKind
  let parentId: String?
  let worktree: WorktreeInfo?
  let settings: WorkspaceSettings
}

enum WorkspaceKind: String, Codable, Sendable {
  case main
  case worktree

  func isWorktree() -> Bool {
    self == .worktree
  }
}

struct WorktreeInfo: Codable, Sendable {
  let branch: String
}

struct WorkspaceSettings: Codable, Sendable {
  var sidebarCollapsed: Bool
  var sortOrder: Int?

  init(sidebarCollapsed: Bool = false, sortOrder: Int? = nil) {
    self.sidebarCollapsed = sidebarCollapsed
    self.sortOrder = sortOrder
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    sidebarCollapsed = try container.decodeIfPresent(Bool.self, forKey: .sidebarCollapsed) ?? false
    sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder)
  }
}

struct AppSettings: Codable, Sendable {
  var codexBin: String?
  var defaultAccessMode: String

  init(codexBin: String? = nil, defaultAccessMode: String = "current") {
    self.codexBin = codexBin
    self.defaultAccessMode = defaultAccessMode
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    codexBin = try container.decodeIfPresent(String.self, forKey: .codexBin)
    defaultAccessMode = try container.decodeIfPresent(String.self, forKey: .defaultAccessMode) ?? "current"
  }
}

struct CodexDoctorResult: Codable, Sendable {
  let ok: Bool
  let codexBin: String?
  let version: String?
  let appServerOk: Bool
  let details: String?
}
