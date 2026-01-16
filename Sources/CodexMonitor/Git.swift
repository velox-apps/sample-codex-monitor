import Foundation

struct GitStatusResponse: Codable, Sendable {
  let branchName: String
  let files: [GitFileStatus]
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
    } else {
      if let staged = stagedStats[path] {
        additions += staged.additions
        deletions += staged.deletions
      }
      if let unstaged = unstagedStats[path] {
        additions += unstaged.additions
        deletions += unstaged.deletions
      }
    }

    totalAdditions += additions
    totalDeletions += deletions
    files.append(GitFileStatus(path: path, status: status, additions: additions, deletions: deletions))
  }

  return GitStatusResponse(
    branchName: branchName,
    files: files,
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
