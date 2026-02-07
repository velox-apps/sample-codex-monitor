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
  codexArgs: String? = nil,
  state: AppState,
  eventManager: VeloxEventManager
) async throws -> WorkspaceInfo {
  let name = URL(fileURLWithPath: path).lastPathComponent
  var settings = WorkspaceSettings()
  if let args = codexArgs?.trimmingCharacters(in: .whitespacesAndNewlines), !args.isEmpty {
    settings.codexArgs = args
  }
  let entry = WorkspaceEntry(
    id: UUID().uuidString,
    name: name.isEmpty ? "Workspace" : name,
    path: path,
    codex_bin: codexBin,
    kind: .main,
    parentId: nil,
    worktree: nil,
    settings: settings
  )

  let appSettings = state.getAppSettings()
  let defaultBin = appSettings.codexBin
  let resolvedArgs = resolveWorkspaceCodexArgs(entry: entry, appSettings: appSettings)
  let session = try await CodexManager.spawnWorkspaceSession(
    entry: entry,
    defaultCodexBin: defaultBin,
    codexArgs: resolvedArgs,
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
  name: String? = nil,
  copyAgentsMd: Bool = true,
  state: AppState,
  eventManager: VeloxEventManager
) async throws -> WorkspaceInfo {
  let trimmed = branch.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else {
    throw CodexError(message: "Branch name is required.")
  }

  let displayName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
  let resolvedName = (displayName?.isEmpty ?? true) ? trimmed : displayName!

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

  if copyAgentsMd {
    copyAgentsMdFromParent(
      parentPath: URL(fileURLWithPath: parentEntry.path),
      worktreePath: worktreePath
    )
  }

  var worktreeSettings = WorkspaceSettings()
  if let setupScript = parentEntry.settings.worktreeSetupScript?.trimmingCharacters(in: .whitespacesAndNewlines),
     !setupScript.isEmpty {
    worktreeSettings.worktreeSetupScript = setupScript
  }

  let entry = WorkspaceEntry(
    id: UUID().uuidString,
    name: resolvedName,
    path: worktreePathString,
    codex_bin: parentEntry.codex_bin,
    kind: .worktree,
    parentId: parentEntry.id,
    worktree: WorktreeInfo(branch: trimmed),
    settings: worktreeSettings
  )

  let appSettings = state.getAppSettings()
  let defaultBin = appSettings.codexBin
  let resolvedArgs = resolveWorkspaceCodexArgs(entry: entry, parentEntry: parentEntry, appSettings: appSettings)
  let session = try await CodexManager.spawnWorkspaceSession(
    entry: entry,
    defaultCodexBin: defaultBin,
    codexArgs: resolvedArgs,
    eventManager: eventManager
  )

  state.setWorkspace(entry)
  state.setSession(id: entry.id, session: session)
  try Storage.writeWorkspaces(state.listWorkspaces(), to: state.storagePath)

  return workspaceInfo(from: entry, connected: true)
}

/// Copy AGENTS.md from parent repo root to worktree root.
/// Uses atomic copy (write to .tmp then rename). Non-fatal on failure.
private func copyAgentsMdFromParent(parentPath: URL, worktreePath: URL) {
  let source = parentPath.appendingPathComponent("AGENTS.md")
  guard FileManager.default.fileExists(atPath: source.path) else { return }

  let dest = worktreePath.appendingPathComponent("AGENTS.md")
  guard !FileManager.default.fileExists(atPath: dest.path) else { return }

  let tmp = worktreePath.appendingPathComponent("AGENTS.md.tmp")
  do {
    try FileManager.default.copyItem(at: source, to: tmp)
    try FileManager.default.moveItem(at: tmp, to: dest)
  } catch {
    try? FileManager.default.removeItem(at: tmp)
    AppLogger.log("add_worktree: optional AGENTS.md copy failed: \(error)", level: .warn)
  }
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
  let appSettings = state.getAppSettings()
  let defaultBin = appSettings.codexBin
  let parentEntry = entry.parentId.flatMap { state.getWorkspace(id: $0) }
  let resolvedArgs = resolveWorkspaceCodexArgs(entry: entry, parentEntry: parentEntry, appSettings: appSettings)
  let session = try await CodexManager.spawnWorkspaceSession(
    entry: entry,
    defaultCodexBin: defaultBin,
    codexArgs: resolvedArgs,
    eventManager: eventManager
  )
  state.setSession(id: entry.id, session: session)
}

func isWorkspacePathDir(path: String) -> Bool {
  var isDir: ObjCBool = false
  return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
}

func openWorkspaceIn(path: String, app: String?, command: String?, args: [String]) throws {
  if let appName = app, !appName.isEmpty {
    // Use NSWorkspace to open the app with the path
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    var openArgs = ["-a", appName, path]
    if !args.isEmpty {
      openArgs.append("--args")
      openArgs.append(contentsOf: args)
    }
    process.arguments = openArgs
    try process.run()
    process.waitUntilExit()
  } else if let cmd = command, !cmd.isEmpty {
    // Use command-line tool
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [cmd] + args + [path]
    var env = ProcessInfo.processInfo.environment
    var paths = env["PATH"]?.split(separator: ":").map(String.init) ?? []
    for extra in ["/opt/homebrew/bin", "/usr/local/bin"] where !paths.contains(extra) {
      paths.append(extra)
    }
    env["PATH"] = paths.joined(separator: ":")
    process.environment = env
    try process.run()
    process.waitUntilExit()
  } else {
    // Finder
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = [path]
    try process.run()
    process.waitUntilExit()
  }
}

func getOpenAppIcon(appName: String) -> String? {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
  process.arguments = ["kMDItemFSName == '\(appName).app' && kMDItemContentType == 'com.apple.application-bundle'"]
  let pipe = Pipe()
  process.standardOutput = pipe
  do {
    try process.run()
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let appPath = output.split(separator: "\n").first.map(String.init) ?? ""
    if appPath.isEmpty { return nil }

    let iconProcess = Process()
    iconProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    let iconScript = """
    python3 -c "
    import Cocoa, base64, io
    ws = Cocoa.NSWorkspace.sharedWorkspace()
    icon = ws.iconForFile_('\(appPath)')
    tiff = icon.TIFFRepresentation()
    rep = Cocoa.NSBitmapImageRep(data=tiff)
    png = rep.representationUsingType_properties_(Cocoa.NSBitmapImageFileTypePNG, None)
    import sys
    sys.stdout.buffer.write(base64.b64encode(bytes(png)))
    "
    """
    iconProcess.arguments = ["bash", "-c", iconScript]
    let iconPipe = Pipe()
    iconProcess.standardOutput = iconPipe
    try iconProcess.run()
    iconProcess.waitUntilExit()
    let iconData = iconPipe.fileHandleForReading.readDataToEndOfFile()
    let base64 = String(data: iconData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if base64.isEmpty { return nil }
    return "data:image/png;base64,\(base64)"
  } catch {
    return nil
  }
}

func addClone(
  sourceWorkspaceId: String,
  copiesFolder: String,
  copyName: String,
  state: AppState,
  eventManager: VeloxEventManager
) async throws -> WorkspaceInfo {
  guard let sourceEntry = state.getWorkspace(id: sourceWorkspaceId) else {
    throw CodexError(message: "source workspace not found")
  }

  // Create destination path
  let destDir = URL(fileURLWithPath: copiesFolder)
  try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
  let destPath = destDir.appendingPathComponent(copyName)

  guard !FileManager.default.fileExists(atPath: destPath.path) else {
    throw CodexError(message: "destination already exists: \(destPath.path)")
  }

  // Clone the repository
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  process.arguments = ["git", "clone", sourceEntry.path, destPath.path]
  let output = try await runProcess(process, timeout: 120)
  guard output.status == 0 else {
    let detail = output.stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
    throw CodexError(message: detail.isEmpty ? "git clone failed" : detail)
  }

  // Add the clone as a new workspace
  return try await addWorkspace(
    path: destPath.path,
    codexBin: sourceEntry.codex_bin,
    state: state,
    eventManager: eventManager
  )
}

func renameWorktree(
  id: String,
  branch: String,
  state: AppState
) async throws -> WorkspaceInfo {
  guard var entry = state.getWorkspace(id: id) else {
    throw CodexError(message: "workspace not found")
  }
  guard entry.kind.isWorktree() else {
    throw CodexError(message: "not a worktree workspace")
  }
  guard let oldBranch = entry.worktree?.branch else {
    throw CodexError(message: "worktree has no branch")
  }

  let repoPath = URL(fileURLWithPath: entry.path)
  _ = try await runGitCommand(repoPath: repoPath, args: ["branch", "-m", oldBranch, branch])

  entry.worktree = WorktreeInfo(branch: branch)
  state.setWorkspace(entry)
  try Storage.writeWorkspaces(state.listWorkspaces(), to: state.storagePath)

  let connected = state.isConnected(id: id)
  return workspaceInfo(from: entry, connected: connected)
}

func renameWorktreeUpstream(
  id: String,
  oldBranch: String,
  newBranch: String,
  state: AppState
) async throws {
  guard let entry = state.getWorkspace(id: id) else {
    throw CodexError(message: "workspace not found")
  }
  let repoPath = URL(fileURLWithPath: entry.path)
  // Delete old remote branch, push new
  _ = try? await runGitCommand(repoPath: repoPath, args: ["push", "origin", ":\(oldBranch)"])
  _ = try await runGitCommand(repoPath: repoPath, args: ["push", "-u", "origin", newBranch])
}

func applyWorktreeChanges(workspaceId: String, state: AppState) async throws {
  guard let entry = state.getWorkspace(id: workspaceId) else {
    throw CodexError(message: "workspace not found")
  }
  let repoPath = URL(fileURLWithPath: entry.path)
  // Pop stash if any, otherwise no-op
  let stashList = try await runGitCommand(repoPath: repoPath, args: ["stash", "list"])
  if !stashList.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    _ = try await runGitCommand(repoPath: repoPath, args: ["stash", "pop"])
  }
}

func worktreeSetupStatus(workspaceId: String, state: AppState) throws -> WorktreeSetupStatus {
  guard let entry = state.getWorkspace(id: workspaceId) else {
    throw CodexError(message: "workspace not found")
  }
  guard entry.kind.isWorktree() else {
    return WorktreeSetupStatus(shouldRun: false, script: nil)
  }

  // Check parent for worktreeSetupScript
  guard let parentId = entry.parentId, let parent = state.getWorkspace(id: parentId) else {
    return WorktreeSetupStatus(shouldRun: false, script: nil)
  }

  guard let script = parent.settings.worktreeSetupScript, !script.isEmpty else {
    return WorktreeSetupStatus(shouldRun: false, script: nil)
  }

  // Check marker file
  let markerDir = (entry.path as NSString).appendingPathComponent(".codex-worktree-setup")
  let markerFile = (markerDir as NSString).appendingPathComponent("ran")
  if FileManager.default.fileExists(atPath: markerFile) {
    return WorktreeSetupStatus(shouldRun: false, script: script)
  }
  return WorktreeSetupStatus(shouldRun: true, script: script)
}

func worktreeSetupMarkRan(workspaceId: String, state: AppState) throws {
  guard let entry = state.getWorkspace(id: workspaceId) else {
    throw CodexError(message: "workspace not found")
  }
  let markerDir = (entry.path as NSString).appendingPathComponent(".codex-worktree-setup")
  try FileManager.default.createDirectory(atPath: markerDir, withIntermediateDirectories: true)
  let markerFile = (markerDir as NSString).appendingPathComponent("ran")
  try "".write(toFile: markerFile, atomically: true, encoding: .utf8)
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
