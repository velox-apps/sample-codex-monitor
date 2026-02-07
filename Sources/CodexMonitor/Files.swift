import Foundation

/// Resolves the default CODEX_HOME directory (~/.codex).
func resolveDefaultCodexHome() -> String? {
  if let home = ProcessInfo.processInfo.environment["HOME"] {
    return (home as NSString).appendingPathComponent(".codex")
  }
  return nil
}

/// Resolves the CODEX_HOME for a given workspace, considering its settings and parent.
func resolveWorkspaceCodexHome(entry: WorkspaceEntry, parent: WorkspaceEntry?, state: AppState) -> String {
  // Check workspace-level override
  if let codexHome = entry.settings.codexHome, !codexHome.isEmpty {
    return expandPath(codexHome, relativeTo: entry.path)
  }
  // For worktrees, check parent's override
  if let parent = parent, let codexHome = parent.settings.codexHome, !codexHome.isEmpty {
    return expandPath(codexHome, relativeTo: parent.path)
  }
  return resolveDefaultCodexHome() ?? "~/.codex"
}

/// Expands ~ and env vars in a path and resolves against a base if relative.
private func expandPath(_ path: String, relativeTo base: String) -> String {
  var expanded = path
  if expanded.hasPrefix("~") {
    if let home = ProcessInfo.processInfo.environment["HOME"] {
      expanded = home + expanded.dropFirst()
    }
  }
  if !expanded.hasPrefix("/") {
    expanded = (base as NSString).appendingPathComponent(expanded)
  }
  return (expanded as NSString).standardizingPath
}

/// Returns the path to the Codex config directory (~/.codex or workspace-specific).
func getCodexConfigPath() -> String {
  resolveDefaultCodexHome() ?? "~/.codex"
}

/// Read a scoped file (agents.md or config.toml).
func fileRead(scope: FileScope, kind: FileKind, workspaceId: String?, state: AppState) throws -> TextFileResponse {
  let filePath = try resolveFilePath(scope: scope, kind: kind, workspaceId: workspaceId, state: state)

  guard FileManager.default.fileExists(atPath: filePath) else {
    return TextFileResponse(exists: false, content: "", truncated: false)
  }

  let content = try String(contentsOfFile: filePath, encoding: .utf8)
  let maxLength = 512 * 1024 // 512 KB
  if content.count > maxLength {
    let truncated = String(content.prefix(maxLength))
    return TextFileResponse(exists: true, content: truncated, truncated: true)
  }

  return TextFileResponse(exists: true, content: content, truncated: false)
}

/// Write a scoped file (agents.md or config.toml).
func fileWrite(scope: FileScope, kind: FileKind, content: String, workspaceId: String?, state: AppState) throws {
  let filePath = try resolveFilePath(scope: scope, kind: kind, workspaceId: workspaceId, state: state)

  let dir = (filePath as NSString).deletingLastPathComponent
  try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
  try content.write(toFile: filePath, atomically: true, encoding: .utf8)
}

/// Resolves the file path for a given scope and kind.
private func resolveFilePath(scope: FileScope, kind: FileKind, workspaceId: String?, state: AppState) throws -> String {
  let fileName: String
  switch kind {
  case .agents:
    fileName = "agents.md"
  case .config:
    fileName = "config.toml"
  }

  switch scope {
  case .global:
    guard let codexHome = resolveDefaultCodexHome() else {
      throw CodexError(message: "Unable to resolve CODEX_HOME")
    }
    return (codexHome as NSString).appendingPathComponent(fileName)

  case .workspace:
    guard let workspaceId = workspaceId else {
      throw CodexError(message: "workspaceId required for workspace scope")
    }
    guard let entry = state.getWorkspace(id: workspaceId) else {
      throw CodexError(message: "workspace not found")
    }
    let parent = entry.parentId.flatMap { state.getWorkspace(id: $0) }
    let codexHome = resolveWorkspaceCodexHome(entry: entry, parent: parent, state: state)
    return (codexHome as NSString).appendingPathComponent(fileName)
  }
}

/// Read an arbitrary file relative to a workspace directory.
func readWorkspaceFile(workspaceId: String, path: String, state: AppState) throws -> WorkspaceFileResponse {
  guard let entry = state.getWorkspace(id: workspaceId) else {
    throw CodexError(message: "workspace not found")
  }
  let fullPath = (entry.path as NSString).appendingPathComponent(path)

  // Security check: ensure the resolved path is within the workspace
  let resolvedFull = (fullPath as NSString).standardizingPath
  let resolvedBase = (entry.path as NSString).standardizingPath
  guard resolvedFull.hasPrefix(resolvedBase) else {
    throw CodexError(message: "path escapes workspace directory")
  }

  guard FileManager.default.fileExists(atPath: resolvedFull) else {
    throw CodexError(message: "file not found: \(path)")
  }

  let content = try String(contentsOfFile: resolvedFull, encoding: .utf8)
  let maxLength = 512 * 1024
  if content.count > maxLength {
    return WorkspaceFileResponse(content: String(content.prefix(maxLength)), truncated: true)
  }
  return WorkspaceFileResponse(content: content, truncated: false)
}
