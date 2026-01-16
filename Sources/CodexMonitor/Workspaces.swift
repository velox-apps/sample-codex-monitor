import Foundation
import VeloxRuntimeWry

func workspaceInfo(from entry: WorkspaceEntry, connected: Bool) -> WorkspaceInfo {
  WorkspaceInfo(
    id: entry.id,
    name: entry.name,
    path: entry.path,
    connected: connected,
    codex_bin: entry.codex_bin,
    kind: entry.kind,
    parentId: entry.parentId,
    worktree: entry.worktree,
    settings: entry.settings
  )
}

func sortWorkspaces(_ list: inout [WorkspaceInfo]) {
  list.sort { lhs, rhs in
    let leftOrder = lhs.settings.sortOrder ?? Int.max
    let rightOrder = rhs.settings.sortOrder ?? Int.max
    if leftOrder != rightOrder {
      return leftOrder < rightOrder
    }
    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
  }
}

func listWorkspaces(state: AppState) -> [WorkspaceInfo] {
  let entries = state.listWorkspaces()
  let sessions = state.listSessions()
  var result = entries.map { entry in
    workspaceInfo(from: entry, connected: sessions[entry.id] != nil)
  }
  sortWorkspaces(&result)
  return result
}

func addWorkspace(
  path: String,
  codexBin: String?,
  state: AppState,
  eventManager: VeloxEventManager
) async throws -> WorkspaceInfo {
  let name = URL(fileURLWithPath: path).lastPathComponent
  let entry = WorkspaceEntry(
    id: UUID().uuidString,
    name: name.isEmpty ? "Workspace" : name,
    path: path,
    codex_bin: codexBin,
    kind: .main,
    parentId: nil,
    worktree: nil,
    settings: WorkspaceSettings()
  )

  let defaultBin = state.getAppSettings().codexBin
  let session = try await CodexManager.spawnWorkspaceSession(
    entry: entry,
    defaultCodexBin: defaultBin,
    eventManager: eventManager
  )

  state.setWorkspace(entry)
  state.setSession(id: entry.id, session: session)
  try Storage.writeWorkspaces(state.listWorkspaces(), to: state.storagePath)

  return workspaceInfo(from: entry, connected: true)
}

func addWorktree(
  parentId: String,
  branch: String,
  state: AppState,
  eventManager: VeloxEventManager
) async throws -> WorkspaceInfo {
  let trimmed = branch.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else {
    throw CodexError(message: "Branch name is required.")
  }

  guard let parentEntry = state.getWorkspace(id: parentId) else {
    throw CodexError(message: "parent workspace not found")
  }

  if parentEntry.kind.isWorktree() {
    throw CodexError(message: "Cannot create a worktree from another worktree.")
  }

  let worktreeRoot = URL(fileURLWithPath: parentEntry.path).appendingPathComponent(".codex-worktrees")
  try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
  try ensureWorktreeIgnored(repoPath: URL(fileURLWithPath: parentEntry.path))

  let safeName = sanitizeWorktreeName(trimmed)
  let worktreePath = uniqueWorktreePath(baseDir: worktreeRoot, name: safeName)
  let worktreePathString = worktreePath.path

  let branchExists = try await gitBranchExists(repoPath: URL(fileURLWithPath: parentEntry.path), branch: trimmed)
  if branchExists {
    _ = try await runGitCommand(repoPath: URL(fileURLWithPath: parentEntry.path), args: ["worktree", "add", worktreePathString, trimmed])
  } else {
    _ = try await runGitCommand(repoPath: URL(fileURLWithPath: parentEntry.path), args: ["worktree", "add", "-b", trimmed, worktreePathString])
  }

  let entry = WorkspaceEntry(
    id: UUID().uuidString,
    name: trimmed,
    path: worktreePathString,
    codex_bin: parentEntry.codex_bin,
    kind: .worktree,
    parentId: parentEntry.id,
    worktree: WorktreeInfo(branch: trimmed),
    settings: WorkspaceSettings()
  )

  let defaultBin = state.getAppSettings().codexBin
  let session = try await CodexManager.spawnWorkspaceSession(
    entry: entry,
    defaultCodexBin: defaultBin,
    eventManager: eventManager
  )

  state.setWorkspace(entry)
  state.setSession(id: entry.id, session: session)
  try Storage.writeWorkspaces(state.listWorkspaces(), to: state.storagePath)

  return workspaceInfo(from: entry, connected: true)
}

func removeWorkspace(id: String, state: AppState) async throws {
  guard let entry = state.getWorkspace(id: id) else {
    throw CodexError(message: "workspace not found")
  }

  if entry.kind.isWorktree() {
    throw CodexError(message: "Use remove_worktree for worktree agents.")
  }

  let children = state.listWorkspaces().filter { $0.parentId == id }
  let parentPath = URL(fileURLWithPath: entry.path)

  for child in children {
    if let session = state.removeSession(id: child.id) {
      await session.terminate()
    }
    let childPath = URL(fileURLWithPath: child.path)
    if FileManager.default.fileExists(atPath: childPath.path) {
      _ = try await runGitCommand(repoPath: parentPath, args: ["worktree", "remove", "--force", child.path])
    }
  }
  _ = try? await runGitCommand(repoPath: parentPath, args: ["worktree", "prune", "--expire", "now"])

  if let session = state.removeSession(id: id) {
    await session.terminate()
  }

  state.removeWorkspace(id: id)
  for child in children {
    state.removeWorkspace(id: child.id)
  }
  try Storage.writeWorkspaces(state.listWorkspaces(), to: state.storagePath)
}

func removeWorktree(id: String, state: AppState) async throws {
  guard let entry = state.getWorkspace(id: id) else {
    throw CodexError(message: "workspace not found")
  }

  guard entry.kind.isWorktree() else {
    throw CodexError(message: "Not a worktree workspace.")
  }

  guard let parentId = entry.parentId, let parent = state.getWorkspace(id: parentId) else {
    throw CodexError(message: "worktree parent not found")
  }

  if let session = state.removeSession(id: entry.id) {
    await session.terminate()
  }

  let parentPath = URL(fileURLWithPath: parent.path)
  let entryPath = URL(fileURLWithPath: entry.path)
  if FileManager.default.fileExists(atPath: entryPath.path) {
    _ = try await runGitCommand(repoPath: parentPath, args: ["worktree", "remove", "--force", entry.path])
  }
  _ = try? await runGitCommand(repoPath: parentPath, args: ["worktree", "prune", "--expire", "now"])

  state.removeWorkspace(id: entry.id)
  try Storage.writeWorkspaces(state.listWorkspaces(), to: state.storagePath)
}

func updateWorkspaceSettings(
  id: String,
  settings: WorkspaceSettings,
  state: AppState
) throws -> WorkspaceInfo {
  guard var entry = state.getWorkspace(id: id) else {
    throw CodexError(message: "workspace not found")
  }
  entry.settings = settings
  state.setWorkspace(entry)
  try Storage.writeWorkspaces(state.listWorkspaces(), to: state.storagePath)
  let connected = state.isConnected(id: id)
  return workspaceInfo(from: entry, connected: connected)
}

func updateWorkspaceCodexBin(
  id: String,
  codexBin: String?,
  state: AppState
) throws -> WorkspaceInfo {
  guard var entry = state.getWorkspace(id: id) else {
    throw CodexError(message: "workspace not found")
  }
  entry.codex_bin = codexBin
  state.setWorkspace(entry)
  try Storage.writeWorkspaces(state.listWorkspaces(), to: state.storagePath)
  let connected = state.isConnected(id: id)
  return workspaceInfo(from: entry, connected: connected)
}

func connectWorkspace(id: String, state: AppState, eventManager: VeloxEventManager) async throws {
  if state.isConnected(id: id) {
    AppLogger.log("Workspace already connected: \(id)", level: .debug)
    return
  }
  guard let entry = state.getWorkspace(id: id) else {
    throw CodexError(message: "workspace not found")
  }
  let defaultBin = state.getAppSettings().codexBin
  let session = try await CodexManager.spawnWorkspaceSession(
    entry: entry,
    defaultCodexBin: defaultBin,
    eventManager: eventManager
  )
  state.setSession(id: entry.id, session: session)
}

func listWorkspaceFiles(workspaceId: String, state: AppState) throws -> [String] {
  guard let entry = state.getWorkspace(id: workspaceId) else {
    throw CodexError(message: "workspace not found")
  }
  return listWorkspaceFiles(root: URL(fileURLWithPath: entry.path), maxFiles: 20000)
}

func runGitCommand(repoPath: URL, args: [String], allowedExitCodes: Set<Int32> = [0]) async throws -> String {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  process.arguments = ["git"] + args
  process.currentDirectoryURL = repoPath
  let output = try await runProcess(process)
  if allowedExitCodes.contains(output.status) {
    return output.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
  }
  let detail = output.stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
  let fallback = output.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
  if detail.isEmpty {
    throw CodexError(message: fallback.isEmpty ? "Git command failed." : fallback)
  }
  throw CodexError(message: detail)
}

func gitBranchExists(repoPath: URL, branch: String) async throws -> Bool {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  process.arguments = ["git", "show-ref", "--verify", "refs/heads/\(branch)"]
  process.currentDirectoryURL = repoPath
  let output = try await runProcess(process)
  return output.status == 0
}
