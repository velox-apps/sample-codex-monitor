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

// MARK: - Auth.json Fallback

struct AuthAccount {
  let email: String?
  let planType: String?
}

/// Reads `auth.json` from the given codex home directory and extracts
/// account information (email, planType) from the JWT id_token.
func readAuthAccount(codexHome: String?) -> AuthAccount? {
  guard let codexHome = codexHome else { return nil }
  let authPath = (codexHome as NSString).appendingPathComponent("auth.json")
  guard let data = FileManager.default.contents(atPath: authPath) else { return nil }
  guard let authValue = try? JSONDecoder().decode(JSONValue.self, from: data) else { return nil }
  guard let tokens = authValue["tokens"] else { return nil }
  let idToken = tokens["idToken"]?.stringValue ?? tokens["id_token"]?.stringValue
  guard let idToken = idToken else { return nil }
  guard let payload = decodeJwtPayload(idToken) else { return nil }

  let authDict = payload["https://api.openai.com/auth"]?.objectValue
  let profileDict = payload["https://api.openai.com/profile"]?.objectValue

  let plan = normalizeAuthString(
    authDict?["chatgpt_plan_type"]?.stringValue
      ?? payload["chatgpt_plan_type"]?.stringValue
  )
  let email = normalizeAuthString(
    payload["email"]?.stringValue
      ?? profileDict?["email"]?.stringValue
  )

  guard email != nil || plan != nil else { return nil }
  return AuthAccount(email: email, planType: plan)
}

/// Decodes the payload segment of a JWT token (base64url → JSON).
private func decodeJwtPayload(_ token: String) -> JSONValue? {
  let parts = token.split(separator: ".")
  guard parts.count >= 2 else { return nil }
  let payloadSegment = String(parts[1])

  // Base64url → Base64: replace URL-safe chars and pad
  var base64 = payloadSegment
    .replacingOccurrences(of: "-", with: "+")
    .replacingOccurrences(of: "_", with: "/")
  let remainder = base64.count % 4
  if remainder > 0 {
    base64 += String(repeating: "=", count: 4 - remainder)
  }

  guard let decoded = Data(base64Encoded: base64) else { return nil }
  return try? JSONDecoder().decode(JSONValue.self, from: decoded)
}

/// Trims and filters empty strings for auth field normalization.
private func normalizeAuthString(_ value: String?) -> String? {
  guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
        !trimmed.isEmpty else { return nil }
  return trimmed
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
