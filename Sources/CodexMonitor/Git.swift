import Foundation

struct GitStatusResponse: Codable, Sendable {
  let branchName: String
  let files: [GitFileStatus]
  let stagedFiles: [GitFileStatus]
  let unstagedFiles: [GitFileStatus]
  let totalAdditions: Int
  let totalDeletions: Int
}

struct GitBranchesResponse: Codable, Sendable {
  let branches: [BranchInfo]
}

func getGitStatus(workspaceId: String, state: AppState) async throws -> GitStatusResponse {
  guard let entry = state.getWorkspace(id: workspaceId) else {
    throw CodexError(message: "workspace not found")
  }
  let repoPath = URL(fileURLWithPath: entry.path)

  let branchName = (try? await runGitCommand(repoPath: repoPath, args: ["rev-parse", "--abbrev-ref", "HEAD"])) ?? "unknown"

  let statusOutput = try await runGitRaw(repoPath: repoPath, args: ["status", "--porcelain=v1", "-z"])
  let records = statusOutput.split(separator: 0)

  let stagedStats = parseNumStat(try await runGitCommand(repoPath: repoPath, args: ["diff", "--cached", "--numstat"], allowedExitCodes: [0, 1]))
  let unstagedStats = parseNumStat(try await runGitCommand(repoPath: repoPath, args: ["diff", "--numstat"], allowedExitCodes: [0, 1]))

  var files: [GitFileStatus] = []
  var stagedFiles: [GitFileStatus] = []
  var unstagedFiles: [GitFileStatus] = []
  var totalAdditions = 0
  var totalDeletions = 0

  for record in records {
    if record.isEmpty { continue }
    let line = String(decoding: record, as: UTF8.self)
    if line.count < 3 { continue }
    let statusChars = Array(line.prefix(2))
    let statusX = statusChars[0]
    let statusY = statusChars[1]
    let startIndex = line.index(line.startIndex, offsetBy: 3, limitedBy: line.endIndex) ?? line.endIndex
    let pathPart = String(line[startIndex...])
    let path = normalizeGitPath(extractPath(from: pathPart))
    if path.isEmpty { continue }

    let status = mapGitStatus(x: statusX, y: statusY)
    var additions = 0
    var deletions = 0

    if statusX == "?" && statusY == "?" {
      let fullPath = repoPath.appendingPathComponent(path)
      additions = countFileLines(at: fullPath)
      unstagedFiles.append(GitFileStatus(path: path, status: "A", additions: additions, deletions: 0))
    } else {
      if let staged = stagedStats[path] {
        additions += staged.additions
        deletions += staged.deletions
      }
      if let unstaged = unstagedStats[path] {
        additions += unstaged.additions
        deletions += unstaged.deletions
      }
      // Staged: X is not ' ' and not '?'
      if statusX != " " && statusX != "?" {
        let sAdd = stagedStats[path]?.additions ?? 0
        let sDel = stagedStats[path]?.deletions ?? 0
        let sStatus = String(statusX) == "?" ? "A" : String(statusX)
        stagedFiles.append(GitFileStatus(path: path, status: sStatus, additions: sAdd, deletions: sDel))
      }
      // Unstaged: Y is not ' ' and not '?'
      if statusY != " " && statusY != "?" {
        let uAdd = unstagedStats[path]?.additions ?? 0
        let uDel = unstagedStats[path]?.deletions ?? 0
        unstagedFiles.append(GitFileStatus(path: path, status: String(statusY), additions: uAdd, deletions: uDel))
      }
    }

    totalAdditions += additions
    totalDeletions += deletions
    files.append(GitFileStatus(path: path, status: status, additions: additions, deletions: deletions))
  }

  return GitStatusResponse(
    branchName: branchName,
    files: files,
    stagedFiles: stagedFiles,
    unstagedFiles: unstagedFiles,
    totalAdditions: totalAdditions,
    totalDeletions: totalDeletions
  )
}

func getGitDiffs(workspaceId: String, state: AppState) async throws -> [GitFileDiff] {
  guard let entry = state.getWorkspace(id: workspaceId) else {
    throw CodexError(message: "workspace not found")
  }
  let repoPath = URL(fileURLWithPath: entry.path)

  let statusOutput = try await runGitRaw(repoPath: repoPath, args: ["status", "--porcelain=v1", "-z"])
  let records = statusOutput.split(separator: 0)

  let hasHead = (try? await runGitCommand(repoPath: repoPath, args: ["rev-parse", "--verify", "HEAD"])) != nil

  var diffs: [GitFileDiff] = []
  for record in records {
    if record.isEmpty { continue }
    let line = String(decoding: record, as: UTF8.self)
    if line.count < 3 { continue }
    let statusChars = Array(line.prefix(2))
    let statusX = statusChars[0]
    let statusY = statusChars[1]
    let startIndex = line.index(line.startIndex, offsetBy: 3, limitedBy: line.endIndex) ?? line.endIndex
    let pathPart = String(line[startIndex...])
    let path = normalizeGitPath(extractPath(from: pathPart))
    if path.isEmpty { continue }

    let diff: String
    if !hasHead || (statusX == "?" && statusY == "?") {
      diff = try await runGitCommand(repoPath: repoPath, args: ["diff", "--no-index", "/dev/null", path], allowedExitCodes: [0, 1])
    } else {
      diff = try await runGitCommand(repoPath: repoPath, args: ["diff", "HEAD", "--", path], allowedExitCodes: [0, 1])
    }

    if diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      continue
    }
    diffs.append(GitFileDiff(path: path, diff: diff))
  }

  return diffs
}

func getGitLog(workspaceId: String, limit: Int?, state: AppState) async throws -> GitLogResponse {
  guard let entry = state.getWorkspace(id: workspaceId) else {
    throw CodexError(message: "workspace not found")
  }
  let repoPath = URL(fileURLWithPath: entry.path)
  let maxItems = limit ?? 40

  let totalString = (try? await runGitCommand(repoPath: repoPath, args: ["rev-list", "--count", "HEAD"])) ?? "0"
  let total = Int(totalString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0

  let format = "%H%x1f%an%x1f%at%x1f%s%x1e"
  let logOutput = try await runGitCommand(
    repoPath: repoPath,
    args: ["log", "--max-count=\(maxItems)", "--pretty=format:\(format)"]
  )

  var entries: [GitLogEntry] = []
  for record in logOutput.split(separator: "\u{1e}") {
    let fields = record.split(separator: "\u{1f}", omittingEmptySubsequences: false)
    if fields.count < 3 { continue }
    let sha = String(fields[0])
    let author = String(fields[1])
    let timestamp = Int64(fields[2]) ?? 0
    let summary = fields.count > 3 ? String(fields[3]) : ""
    entries.append(GitLogEntry(sha: sha, summary: summary, author: author, timestamp: timestamp))
  }

  return GitLogResponse(total: total, entries: entries)
}

func getGitRemote(workspaceId: String, state: AppState) async throws -> String? {
  guard let entry = state.getWorkspace(id: workspaceId) else {
    throw CodexError(message: "workspace not found")
  }
  let repoPath = URL(fileURLWithPath: entry.path)

  let remotesString = try await runGitCommand(repoPath: repoPath, args: ["remote"])
  let remotes = remotesString.split(separator: "\n").map { String($0) }.filter { !$0.isEmpty }
  guard !remotes.isEmpty else {
    return nil
  }

  let name = remotes.contains("origin") ? "origin" : remotes[0]
  let url = try await runGitCommand(repoPath: repoPath, args: ["remote", "get-url", name])
  let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
  return trimmed.isEmpty ? nil : trimmed
}

func listGitBranches(workspaceId: String, state: AppState) async throws -> GitBranchesResponse {
  guard let entry = state.getWorkspace(id: workspaceId) else {
    throw CodexError(message: "workspace not found")
  }
  let repoPath = URL(fileURLWithPath: entry.path)

  let output = try await runGitCommand(
    repoPath: repoPath,
    args: ["for-each-ref", "--format=%(refname:short)%09%(committerdate:unix)", "refs/heads"]
  )
  var branches: [BranchInfo] = []
  for line in output.split(separator: "\n") {
    let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
    if parts.count < 2 { continue }
    let name = String(parts[0])
    let timestamp = Int64(parts[1]) ?? 0
    if name.isEmpty { continue }
    branches.append(BranchInfo(name: name, last_commit: timestamp))
  }
  branches.sort { $0.last_commit > $1.last_commit }
  return GitBranchesResponse(branches: branches)
}

func checkoutGitBranch(workspaceId: String, name: String, state: AppState) async throws {
  guard let entry = state.getWorkspace(id: workspaceId) else {
    throw CodexError(message: "workspace not found")
  }
  let repoPath = URL(fileURLWithPath: entry.path)
  _ = try await runGitCommand(repoPath: repoPath, args: ["checkout", name])
}

func createGitBranch(workspaceId: String, name: String, state: AppState) async throws {
  guard let entry = state.getWorkspace(id: workspaceId) else {
    throw CodexError(message: "workspace not found")
  }
  let repoPath = URL(fileURLWithPath: entry.path)
  _ = try await runGitCommand(repoPath: repoPath, args: ["checkout", "-b", name])
}

private func extractPath(from pathPart: String) -> String {
  if let range = pathPart.range(of: " -> ") {
    return String(pathPart[range.upperBound...])
  }
  if let range = pathPart.range(of: " => ") {
    return String(pathPart[range.upperBound...])
  }
  return pathPart
}

private func mapGitStatus(x: Character, y: Character) -> String {
  if x == "?" || y == "?" || x == "A" || y == "A" {
    return "A"
  }
  if x == "M" || y == "M" {
    return "M"
  }
  if x == "D" || y == "D" {
    return "D"
  }
  if x == "R" || y == "R" {
    return "R"
  }
  if x == "T" || y == "T" {
    return "T"
  }
  return "--"
}

private func parseNumStat(_ output: String) -> [String: (additions: Int, deletions: Int)] {
  var stats: [String: (additions: Int, deletions: Int)] = [:]
  for line in output.split(separator: "\n") {
    let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
    if parts.count < 3 { continue }
    let additions = Int(parts[0]) ?? 0
    let deletions = Int(parts[1]) ?? 0
    let pathPart = String(parts[2])
    let path = normalizeGitPath(extractPath(from: pathPart))
    stats[path] = (additions, deletions)
  }
  return stats
}

// MARK: - Staging & Commit Commands

func stageGitFile(workspaceId: String, path: String, state: AppState) async throws {
  guard let entry = state.getWorkspace(id: workspaceId) else {
    throw CodexError(message: "workspace not found")
  }
  let repoPath = URL(fileURLWithPath: entry.path)
  _ = try await runGitCommand(repoPath: repoPath, args: ["add", "-A", "--", path])
}

func stageGitAll(workspaceId: String, state: AppState) async throws {
  guard let entry = state.getWorkspace(id: workspaceId) else {
    throw CodexError(message: "workspace not found")
  }
  let repoPath = URL(fileURLWithPath: entry.path)
  _ = try await runGitCommand(repoPath: repoPath, args: ["add", "-A"])
}

func unstageGitFile(workspaceId: String, path: String, state: AppState) async throws {
  guard let entry = state.getWorkspace(id: workspaceId) else {
    throw CodexError(message: "workspace not found")
  }
  let repoPath = URL(fileURLWithPath: entry.path)
  _ = try await runGitCommand(repoPath: repoPath, args: ["restore", "--staged", "--", path])
}

func revertGitFile(workspaceId: String, path: String, state: AppState) async throws {
  guard let entry = state.getWorkspace(id: workspaceId) else {
    throw CodexError(message: "workspace not found")
  }
  let repoPath = URL(fileURLWithPath: entry.path)
  _ = try? await runGitCommand(repoPath: repoPath, args: ["restore", "--staged", "--worktree", "--", path])
  _ = try? await runGitCommand(repoPath: repoPath, args: ["clean", "-f", "--", path])
}

func revertGitAll(workspaceId: String, state: AppState) async throws {
  guard let entry = state.getWorkspace(id: workspaceId) else {
    throw CodexError(message: "workspace not found")
  }
  let repoPath = URL(fileURLWithPath: entry.path)
  _ = try? await runGitCommand(repoPath: repoPath, args: ["restore", "--staged", "--worktree", "--", "."])
  _ = try? await runGitCommand(repoPath: repoPath, args: ["clean", "-f", "-d"])
}

func commitGit(workspaceId: String, message: String, state: AppState) async throws {
  guard let entry = state.getWorkspace(id: workspaceId) else {
    throw CodexError(message: "workspace not found")
  }
  let repoPath = URL(fileURLWithPath: entry.path)
  _ = try await runGitCommand(repoPath: repoPath, args: ["commit", "-m", message])
}

func pushGit(workspaceId: String, state: AppState) async throws {
  guard let entry = state.getWorkspace(id: workspaceId) else {
    throw CodexError(message: "workspace not found")
  }
  let repoPath = URL(fileURLWithPath: entry.path)
  // Check for upstream
  let hasUpstream = (try? await runGitCommand(repoPath: repoPath, args: ["rev-parse", "--abbrev-ref", "@{upstream}"])) != nil
  if hasUpstream {
    _ = try await runGitCommand(repoPath: repoPath, args: ["push"])
  } else {
    let branch = try await runGitCommand(repoPath: repoPath, args: ["rev-parse", "--abbrev-ref", "HEAD"])
    _ = try await runGitCommand(repoPath: repoPath, args: ["push", "-u", "origin", branch])
  }
}

func pullGit(workspaceId: String, state: AppState) async throws {
  guard let entry = state.getWorkspace(id: workspaceId) else {
    throw CodexError(message: "workspace not found")
  }
  let repoPath = URL(fileURLWithPath: entry.path)
  _ = try await runGitCommand(repoPath: repoPath, args: ["pull", "--autostash"])
}

func fetchGit(workspaceId: String, state: AppState) async throws {
  guard let entry = state.getWorkspace(id: workspaceId) else {
    throw CodexError(message: "workspace not found")
  }
  let repoPath = URL(fileURLWithPath: entry.path)
  _ = try await runGitCommand(repoPath: repoPath, args: ["fetch", "--prune"])
}

func syncGit(workspaceId: String, state: AppState) async throws {
  try await pullGit(workspaceId: workspaceId, state: state)
  try await pushGit(workspaceId: workspaceId, state: state)
}

// MARK: - Rich Data Commands

func listGitRoots(workspaceId: String, depth: Int, state: AppState) async throws -> [String] {
  guard let entry = state.getWorkspace(id: workspaceId) else {
    throw CodexError(message: "workspace not found")
  }
  let basePath = entry.path
  var roots: [String] = []
  let baseURL = URL(fileURLWithPath: basePath)

  func scan(dir: URL, currentDepth: Int) {
    let gitDir = dir.appendingPathComponent(".git")
    if FileManager.default.fileExists(atPath: gitDir.path) {
      roots.append(dir.path)
    }
    guard currentDepth < depth else { return }
    guard let entries = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
      return
    }
    for entry in entries {
      let name = entry.lastPathComponent
      if shouldSkipDir(name) { continue }
      if (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
        scan(dir: entry, currentDepth: currentDepth + 1)
      }
    }
  }

  scan(dir: baseURL, currentDepth: 0)
  return roots
}

func getGitCommitDiff(workspaceId: String, sha: String, state: AppState) async throws -> [GitCommitDiff] {
  guard let entry = state.getWorkspace(id: workspaceId) else {
    throw CodexError(message: "workspace not found")
  }
  let repoPath = URL(fileURLWithPath: entry.path)

  // Get list of changed files with numstat
  let numstatOutput = try await runGitCommand(
    repoPath: repoPath,
    args: ["diff-tree", "-r", "--numstat", sha]
  )
  let stats = parseNumStat(numstatOutput)

  // Get the full diff for the commit
  let fullDiff = try await runGitCommand(
    repoPath: repoPath,
    args: ["show", "--format=", sha],
    allowedExitCodes: [0, 1]
  )

  // Parse individual file diffs
  var diffs: [GitCommitDiff] = []
  let fileDiffs = splitDiffByFile(fullDiff)

  for (path, diff) in fileDiffs {
    let stat = stats[path]
    let status = detectFileStatus(diff: diff, additions: stat?.additions ?? 0, deletions: stat?.deletions ?? 0)
    diffs.append(GitCommitDiff(
      path: path,
      status: status,
      diff: diff
    ))
  }

  return diffs
}

// MARK: - GitHub Commands

func getGitHubIssues(workspaceId: String, state: AppState) async throws -> GitHubIssuesResponse {
  guard let entry = state.getWorkspace(id: workspaceId) else {
    throw CodexError(message: "workspace not found")
  }
  let repoPath = URL(fileURLWithPath: entry.path)
  let output = try await runGhCommand(
    repoPath: repoPath,
    args: ["issue", "list", "--json", "number,title,url,updatedAt", "--limit", "100"]
  )
  guard let data = output.data(using: .utf8) else {
    return GitHubIssuesResponse(total: 0, issues: [])
  }
  let issues = try JSONDecoder().decode([GitHubIssue].self, from: data)
  return GitHubIssuesResponse(total: issues.count, issues: issues)
}

func getGitHubPullRequests(workspaceId: String, state: AppState) async throws -> GitHubPullRequestsResponse {
  guard let entry = state.getWorkspace(id: workspaceId) else {
    throw CodexError(message: "workspace not found")
  }
  let repoPath = URL(fileURLWithPath: entry.path)
  let output = try await runGhCommand(
    repoPath: repoPath,
    args: ["pr", "list", "--json", "number,title,url,updatedAt,createdAt,body,headRefName,baseRefName,isDraft,author", "--limit", "100"]
  )
  guard let data = output.data(using: .utf8) else {
    return GitHubPullRequestsResponse(total: 0, pullRequests: [])
  }
  let prs = try JSONDecoder().decode([GitHubPullRequest].self, from: data)
  return GitHubPullRequestsResponse(total: prs.count, pullRequests: prs)
}

func getGitHubPullRequestDiff(workspaceId: String, prNumber: Int, state: AppState) async throws -> [GitHubPullRequestDiff] {
  guard let entry = state.getWorkspace(id: workspaceId) else {
    throw CodexError(message: "workspace not found")
  }
  let repoPath = URL(fileURLWithPath: entry.path)
  let diff = try await runGhCommand(
    repoPath: repoPath,
    args: ["pr", "diff", "\(prNumber)"]
  )
  return parsePrDiff(diff)
}

func getGitHubPullRequestComments(workspaceId: String, prNumber: Int, state: AppState) async throws -> [GitHubPullRequestComment] {
  guard let entry = state.getWorkspace(id: workspaceId) else {
    throw CodexError(message: "workspace not found")
  }
  let repoPath = URL(fileURLWithPath: entry.path)

  // Get the repo owner/name from the remote
  let remoteUrl = try await runGitCommand(repoPath: repoPath, args: ["remote", "get-url", "origin"])
  let nwo = extractRepoNwo(from: remoteUrl)
  guard !nwo.isEmpty else {
    throw CodexError(message: "Could not determine repository from remote URL")
  }

  let output = try await runGhCommand(
    repoPath: repoPath,
    args: ["api", "repos/\(nwo)/issues/\(prNumber)/comments", "--paginate"]
  )
  guard let data = output.data(using: .utf8) else { return [] }
  return try JSONDecoder().decode([GitHubPullRequestComment].self, from: data)
}

// MARK: - Private Helpers

private func runGhCommand(repoPath: URL, args: [String]) async throws -> String {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  process.arguments = ["gh"] + args
  process.currentDirectoryURL = repoPath
  var env = ProcessInfo.processInfo.environment
  var paths = env["PATH"]?.split(separator: ":").map(String.init) ?? []
  for extra in ["/opt/homebrew/bin", "/usr/local/bin"] where !paths.contains(extra) {
    paths.append(extra)
  }
  env["PATH"] = paths.joined(separator: ":")
  process.environment = env
  let output = try await runProcess(process, timeout: 30)
  if output.status == 0 {
    return output.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
  }
  let detail = output.stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
  throw CodexError(message: detail.isEmpty ? "gh command failed" : detail)
}

private func splitDiffByFile(_ diff: String) -> [(String, String)] {
  var results: [(String, String)] = []
  let lines = diff.split(separator: "\n", omittingEmptySubsequences: false)
  var currentPath: String?
  var currentLines: [String] = []

  for line in lines {
    if line.hasPrefix("diff --git ") {
      if let path = currentPath {
        results.append((path, currentLines.joined(separator: "\n")))
      }
      currentLines = [String(line)]
      // Extract path from "diff --git a/path b/path"
      let parts = line.split(separator: " ", maxSplits: 4)
      if parts.count >= 4 {
        let bPath = String(parts[3])
        currentPath = bPath.hasPrefix("b/") ? String(bPath.dropFirst(2)) : bPath
      } else {
        currentPath = nil
      }
    } else {
      currentLines.append(String(line))
    }
  }

  if let path = currentPath {
    results.append((path, currentLines.joined(separator: "\n")))
  }

  return results
}

private func detectFileStatus(diff: String, additions: Int, deletions: Int) -> String {
  if diff.contains("new file mode") { return "A" }
  if diff.contains("deleted file mode") { return "D" }
  if diff.contains("rename from") { return "R" }
  return "M"
}

private func parsePrDiff(_ diff: String) -> [GitHubPullRequestDiff] {
  let fileDiffs = splitDiffByFile(diff)
  return fileDiffs.map { (path, diffContent) in
    let status = detectFileStatus(diff: diffContent, additions: 0, deletions: 0)
    return GitHubPullRequestDiff(path: path, status: status, diff: diffContent)
  }
}

private func extractRepoNwo(from remoteUrl: String) -> String {
  let url = remoteUrl.trimmingCharacters(in: .whitespacesAndNewlines)
  // Handle SSH: git@github.com:owner/repo.git
  if url.contains("@") && url.contains(":") {
    let afterColon = url.split(separator: ":").last ?? ""
    let path = afterColon.replacingOccurrences(of: ".git", with: "")
    return String(path)
  }
  // Handle HTTPS: https://github.com/owner/repo.git
  if let parsed = URL(string: url) {
    let path = parsed.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      .replacingOccurrences(of: ".git", with: "")
    return path
  }
  return ""
}

private func runGitRaw(repoPath: URL, args: [String]) async throws -> Data {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  process.arguments = ["git"] + args
  process.currentDirectoryURL = repoPath
  let output = try await runProcess(process)
  if output.status == 0 {
    return output.stdout
  }
  let detail = output.stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
  let fallback = output.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
  if detail.isEmpty {
    throw CodexError(message: fallback.isEmpty ? "Git command failed." : fallback)
  }
  throw CodexError(message: detail)
}
