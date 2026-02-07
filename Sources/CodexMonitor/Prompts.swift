import Foundation

// MARK: - Prompts Module

/// Lists all custom prompts from workspace and global scopes.
func promptsList(workspaceId: String, state: AppState) throws -> [PromptEntry] {
  guard let entry = state.getWorkspace(id: workspaceId) else {
    throw CodexError(message: "workspace not found")
  }
  let parent = entry.parentId.flatMap { state.getWorkspace(id: $0) }
  let codexHome = resolveWorkspaceCodexHome(entry: entry, parent: parent, state: state)
  let globalHome = resolveDefaultCodexHome() ?? "~/.codex"

  var prompts: [PromptEntry] = []

  // Workspace prompts
  let workspacePromptsDir = (codexHome as NSString).appendingPathComponent("prompts")
  prompts.append(contentsOf: scanPromptsDir(workspacePromptsDir, scope: "workspace"))

  // Global prompts (avoid duplicates if same dir)
  let globalPromptsDir = (globalHome as NSString).appendingPathComponent("prompts")
  if globalPromptsDir != workspacePromptsDir {
    prompts.append(contentsOf: scanPromptsDir(globalPromptsDir, scope: "global"))
  }

  return prompts
}

/// Creates a new prompt file.
func promptsCreate(
  workspaceId: String,
  scope: String,
  name: String,
  description: String?,
  argumentHint: String?,
  content: String,
  state: AppState
) throws -> PromptEntry {
  let dir = try resolvePromptsDir(workspaceId: workspaceId, scope: scope, state: state)
  try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

  let fileName = sanitizePromptFileName(name)
  let filePath = (dir as NSString).appendingPathComponent(fileName + ".md")

  guard !FileManager.default.fileExists(atPath: filePath) else {
    throw CodexError(message: "A prompt with this name already exists")
  }

  let fileContent = buildPromptFileContent(description: description, argumentHint: argumentHint, content: content)
  try fileContent.write(toFile: filePath, atomically: true, encoding: .utf8)

  return PromptEntry(
    name: name,
    path: filePath,
    scope: scope,
    description: description,
    argumentHint: argumentHint,
    content: content
  )
}

/// Updates an existing prompt file.
func promptsUpdate(
  workspaceId: String,
  path: String,
  name: String,
  description: String?,
  argumentHint: String?,
  content: String,
  state: AppState
) throws -> PromptEntry {
  guard FileManager.default.fileExists(atPath: path) else {
    throw CodexError(message: "prompt file not found")
  }

  let dir = (path as NSString).deletingLastPathComponent
  let newFileName = sanitizePromptFileName(name) + ".md"
  let newPath = (dir as NSString).appendingPathComponent(newFileName)

  let fileContent = buildPromptFileContent(description: description, argumentHint: argumentHint, content: content)

  // If name changed, rename the file
  if newPath != path {
    guard !FileManager.default.fileExists(atPath: newPath) else {
      throw CodexError(message: "A prompt with this name already exists")
    }
    try FileManager.default.removeItem(atPath: path)
  }

  try fileContent.write(toFile: newPath, atomically: true, encoding: .utf8)

  let scope = detectScope(path: newPath, workspaceId: workspaceId, state: state)
  return PromptEntry(
    name: name,
    path: newPath,
    scope: scope,
    description: description,
    argumentHint: argumentHint,
    content: content
  )
}

/// Deletes a prompt file.
func promptsDelete(workspaceId: String, path: String, state: AppState) throws {
  guard FileManager.default.fileExists(atPath: path) else {
    throw CodexError(message: "prompt file not found")
  }
  try FileManager.default.removeItem(atPath: path)
}

/// Moves a prompt between workspace and global scopes.
func promptsMove(workspaceId: String, path: String, scope: String, state: AppState) throws -> PromptEntry {
  guard FileManager.default.fileExists(atPath: path) else {
    throw CodexError(message: "prompt file not found")
  }

  let targetDir = try resolvePromptsDir(workspaceId: workspaceId, scope: scope, state: state)
  try FileManager.default.createDirectory(atPath: targetDir, withIntermediateDirectories: true)

  let fileName = (path as NSString).lastPathComponent
  let targetPath = (targetDir as NSString).appendingPathComponent(fileName)

  guard !FileManager.default.fileExists(atPath: targetPath) else {
    throw CodexError(message: "A prompt with this name already exists in the target scope")
  }

  // Read, write to new location, delete old
  let content = try String(contentsOfFile: path, encoding: .utf8)
  try content.write(toFile: targetPath, atomically: true, encoding: .utf8)
  try FileManager.default.removeItem(atPath: path)

  let parsed = parsePromptFile(targetPath, scope: scope)
  return parsed
}

/// Returns the workspace prompts directory path.
func promptsWorkspaceDir(workspaceId: String, state: AppState) throws -> String {
  try resolvePromptsDir(workspaceId: workspaceId, scope: "workspace", state: state)
}

/// Returns the global prompts directory path.
func promptsGlobalDir(workspaceId: String, state: AppState) throws -> String {
  try resolvePromptsDir(workspaceId: workspaceId, scope: "global", state: state)
}

// MARK: - Private Helpers

private func resolvePromptsDir(workspaceId: String, scope: String, state: AppState) throws -> String {
  if scope == "global" {
    guard let codexHome = resolveDefaultCodexHome() else {
      throw CodexError(message: "Unable to resolve CODEX_HOME")
    }
    return (codexHome as NSString).appendingPathComponent("prompts")
  }

  guard let entry = state.getWorkspace(id: workspaceId) else {
    throw CodexError(message: "workspace not found")
  }
  let parent = entry.parentId.flatMap { state.getWorkspace(id: $0) }
  let codexHome = resolveWorkspaceCodexHome(entry: entry, parent: parent, state: state)
  return (codexHome as NSString).appendingPathComponent("prompts")
}

private func scanPromptsDir(_ dir: String, scope: String) -> [PromptEntry] {
  guard FileManager.default.fileExists(atPath: dir) else {
    return []
  }
  guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else {
    return []
  }
  return files
    .filter { $0.hasSuffix(".md") }
    .compactMap { fileName -> PromptEntry? in
      let filePath = (dir as NSString).appendingPathComponent(fileName)
      return parsePromptFile(filePath, scope: scope)
    }
    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
}

private func parsePromptFile(_ path: String, scope: String) -> PromptEntry {
  let rawContent = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
  let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension

  var description: String?
  var argumentHint: String?
  var content = rawContent

  // Parse YAML frontmatter
  if rawContent.hasPrefix("---\n") || rawContent.hasPrefix("---\r\n") {
    let lines = rawContent.components(separatedBy: "\n")
    var endIndex: Int?
    for i in 1..<lines.count {
      if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
        endIndex = i
        break
      }
    }
    if let end = endIndex {
      let frontmatterLines = Array(lines[1..<end])
      for line in frontmatterLines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("description:") {
          description = trimmed.dropFirst("description:".count)
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        } else if trimmed.hasPrefix("argument-hint:") {
          argumentHint = trimmed.dropFirst("argument-hint:".count)
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
      }
      content = lines[(end + 1)...].joined(separator: "\n")
      if content.hasPrefix("\n") {
        content = String(content.dropFirst())
      }
    }
  }

  return PromptEntry(
    name: name,
    path: path,
    scope: scope,
    description: description,
    argumentHint: argumentHint,
    content: content
  )
}

private func buildPromptFileContent(description: String?, argumentHint: String?, content: String) -> String {
  let hasFrontmatter = (description != nil && !description!.isEmpty) || (argumentHint != nil && !argumentHint!.isEmpty)
  guard hasFrontmatter else { return content }

  var lines = ["---"]
  if let desc = description, !desc.isEmpty {
    lines.append("description: \"\(desc)\"")
  }
  if let hint = argumentHint, !hint.isEmpty {
    lines.append("argument-hint: \"\(hint)\"")
  }
  lines.append("---")
  lines.append("")
  lines.append(content)
  return lines.joined(separator: "\n")
}

private func sanitizePromptFileName(_ name: String) -> String {
  var result = ""
  for ch in name {
    if ch.isASCII && (ch.isLetter || ch.isNumber || ch == "-" || ch == "_" || ch == " " || ch == ".") {
      result.append(ch)
    }
  }
  let trimmed = result.trimmingCharacters(in: .whitespaces)
  return trimmed.isEmpty ? "untitled" : trimmed
}

private func detectScope(path: String, workspaceId: String, state: AppState) -> String {
  guard let globalHome = resolveDefaultCodexHome() else { return "workspace" }
  let globalDir = (globalHome as NSString).appendingPathComponent("prompts")
  if path.hasPrefix(globalDir) { return "global" }
  return "workspace"
}
