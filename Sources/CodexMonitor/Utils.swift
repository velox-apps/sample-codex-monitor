import Foundation

struct ProcessOutput {
  let status: Int32
  let stdout: Data
  let stderr: Data

  var stdoutText: String {
    String(data: stdout, encoding: .utf8) ?? String(decoding: stdout, as: UTF8.self)
  }

  var stderrText: String {
    String(data: stderr, encoding: .utf8) ?? String(decoding: stderr, as: UTF8.self)
  }
}

struct ProcessTimeoutError: Error {
  let seconds: TimeInterval
}

func runProcess(_ process: Process, timeout: TimeInterval? = nil) async throws -> ProcessOutput {
  let stdoutPipe = Pipe()
  let stderrPipe = Pipe()
  process.standardOutput = stdoutPipe
  process.standardError = stderrPipe

  return try await withThrowingTaskGroup(of: ProcessOutput.self) { group in
    group.addTask {
      try process.run()
      process.waitUntilExit()
      let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
      let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
      return ProcessOutput(status: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    if let timeout {
      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        process.terminate()
        throw ProcessTimeoutError(seconds: timeout)
      }
    }

    guard let result = try await group.next() else {
      throw ProcessTimeoutError(seconds: timeout ?? 0)
    }
    group.cancelAll()
    return result
  }
}

func normalizeGitPath(_ path: String) -> String {
  path.replacingOccurrences(of: "\\", with: "/")
}

func sanitizeWorktreeName(_ branch: String) -> String {
  var result = ""
  for ch in branch {
    if ch.isASCII && (ch.isLetter || ch.isNumber || ch == "-" || ch == "_" || ch == ".") {
      result.append(ch)
    } else {
      result.append("-")
    }
  }
  let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
  return trimmed.isEmpty ? "worktree" : trimmed
}

func shouldSkipDir(_ name: String) -> Bool {
  return name == ".git" || name == "node_modules" || name == "dist" || name == "target" || name == "release-artifacts"
}

func uniqueWorktreePath(baseDir: URL, name: String) -> URL {
  var candidate = baseDir.appendingPathComponent(name)
  if !FileManager.default.fileExists(atPath: candidate.path) {
    return candidate
  }
  for index in 2..<1000 {
    let next = baseDir.appendingPathComponent("\(name)-\(index)")
    if !FileManager.default.fileExists(atPath: next.path) {
      candidate = next
      break
    }
  }
  return candidate
}

func ensureWorktreeIgnored(repoPath: URL) throws {
  let ignorePath = repoPath.appendingPathComponent(".gitignore")
  let entry = ".codex-worktrees/"
  let existing = (try? String(contentsOf: ignorePath, encoding: .utf8)) ?? ""
  if existing.split(separator: "\n").contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == entry }) {
    return
  }
  var toAppend = entry + "\n"
  if !existing.isEmpty && !existing.hasSuffix("\n") {
    toAppend = "\n" + toAppend
  }
  if let data = toAppend.data(using: .utf8) {
    if FileManager.default.fileExists(atPath: ignorePath.path) {
      let handle = try FileHandle(forWritingTo: ignorePath)
      try handle.seekToEnd()
      try handle.write(contentsOf: data)
      try handle.close()
    } else {
      try data.write(to: ignorePath, options: [.atomic])
    }
  }
}

func listWorkspaceFiles(root: URL, maxFiles: Int) -> [String] {
  var results: [String] = []
  var stack: [URL] = [root]

  while let dir = stack.popLast() {
    guard let entries = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
      continue
    }
    for entry in entries {
      let name = entry.lastPathComponent
      if shouldSkipDir(name) {
        continue
      }
      if (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
        stack.append(entry)
        continue
      }
      let relative = entry.path.replacingOccurrences(of: root.path + "/", with: "")
      let normalized = normalizeGitPath(relative)
      if !normalized.isEmpty {
        results.append(normalized)
      }
      if results.count >= maxFiles {
        results.sort()
        return results
      }
    }
  }

  results.sort()
  return results
}

func countFileLines(at path: URL) -> Int {
  guard let data = try? Data(contentsOf: path), !data.isEmpty else {
    return 0
  }
  var count = 0
  for byte in data {
    if byte == 10 {
      count += 1
    }
  }
  if data.last != 10 {
    count += 1
  }
  return count
}
