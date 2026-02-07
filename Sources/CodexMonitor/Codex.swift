import Foundation
import VeloxRuntimeWry

struct AppServerEvent: Codable, Sendable {
  let workspace_id: String
  let message: JSONValue
}

struct CodexError: Error {
  let message: String
}

extension CodexError: LocalizedError {
  var errorDescription: String? {
    message
  }
}

actor WorkspaceSession {
  nonisolated let entry: WorkspaceEntry
  private let process: Process
  private let stdin: FileHandle
  private var pending: [UInt64: CheckedContinuation<JSONValue, Error>] = [:]
  private var nextId: UInt64 = 1

  init(entry: WorkspaceEntry, process: Process, stdin: FileHandle) {
    self.entry = entry
    self.process = process
    self.stdin = stdin
  }

  func terminate() {
    process.terminate()
  }

  func sendRequest(method: String, params: JSONValue) async throws -> JSONValue {
    let id = nextId
    nextId += 1
    return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<JSONValue, Error>) in
      pending[id] = cont
      do {
        var msg: [String: JSONValue] = [
          "id": .number(Double(id)),
          "method": .string(method)
        ]
        // Omit params when null; send empty object for .null to satisfy
        // app-server deserializers that require the field to be present.
        switch params {
        case .null:
          msg["params"] = .object([:])
        default:
          msg["params"] = params
        }
        try writeMessage(.object(msg))
      } catch {
        pending.removeValue(forKey: id)
        cont.resume(throwing: error)
      }
    }
  }

  func sendNotification(method: String, params: JSONValue?) throws {
    if let params {
      try writeMessage(JSONValue.object([
        "method": .string(method),
        "params": params
      ]))
    } else {
      try writeMessage(JSONValue.object([
        "method": .string(method)
      ]))
    }
  }

  func sendResponse(id: UInt64, result: JSONValue) throws {
    try writeMessage(JSONValue.object([
      "id": .number(Double(id)),
      "result": result
    ]))
  }

  func handleIncoming(_ value: JSONValue, eventManager: VeloxEventManager, workspaceId: String) {
    let id = value["id"]?.asUInt64()
    let hasMethod = value["method"] != nil
    let hasResultOrError = value["result"] != nil || value["error"] != nil

    if let id, hasResultOrError {
      if let continuation = pending.removeValue(forKey: id) {
        continuation.resume(returning: value)
      }
      return
    }

    if let _ = id, hasMethod {
      emitEvent(eventManager: eventManager, workspaceId: workspaceId, message: value)
      return
    }

    if let id {
      if let continuation = pending.removeValue(forKey: id) {
        continuation.resume(returning: value)
      }
      return
    }

    if hasMethod {
      emitEvent(eventManager: eventManager, workspaceId: workspaceId, message: value)
    }
  }

  private func writeMessage(_ value: JSONValue) throws {
    let data = try JSONEncoder().encode(value)
    var payload = data
    payload.append(0x0a)
    try stdin.write(contentsOf: payload)
  }

  private func emitEvent(eventManager: VeloxEventManager, workspaceId: String, message: JSONValue) {
    let method = message["method"]?.stringValue ?? "unknown"
    if method.contains("account") || method.contains("login") {
      if let data = try? JSONEncoder().encode(message), let json = String(data: data, encoding: .utf8) {
        AppLogger.log("EMIT app-server-event method=\(method) message=\(json)", level: .info)
      } else {
        AppLogger.log("EMIT app-server-event method=\(method)", level: .info)
      }
    }
    let payload = AppServerEvent(workspace_id: workspaceId, message: message)
    do {
      try eventManager.emit("app-server-event", payload: payload)
    } catch {
      AppLogger.log("EMIT ERROR: \(error)", level: .error)
    }
  }
}

enum CodexManager {
  static func spawnWorkspaceSession(
    entry: WorkspaceEntry,
    defaultCodexBin: String?,
    eventManager: VeloxEventManager
  ) async throws -> WorkspaceSession {
    AppLogger.log("Spawning Codex session for \(entry.id) at \(entry.path)", level: .info)
    let codexBin = entry.codex_bin?.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedBin = (codexBin?.isEmpty ?? true) ? defaultCodexBin : codexBin
    _ = try await checkCodexInstallation(codexBin: resolvedBin)

    let process = try buildCodexProcess(codexBin: resolvedBin, args: ["app-server"])
    let stdinPipe = Pipe()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardInput = stdinPipe
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()
    AppLogger.log("Codex process started for \(entry.id)", level: .info)

    let session = WorkspaceSession(entry: entry, process: process, stdin: stdinPipe.fileHandleForWriting)
    let workspaceId = entry.id

    startStdoutListener(handle: stdoutPipe.fileHandleForReading, session: session, eventManager: eventManager, workspaceId: workspaceId)
    startStderrListener(handle: stderrPipe.fileHandleForReading, eventManager: eventManager, workspaceId: workspaceId)

    let initParams = JSONValue.object([
      "clientInfo": JSONValue.object([
        "name": .string("codex_monitor"),
        "title": .string("CodexMonitor"),
        "version": .string("0.1.0")
      ])
    ])

    do {
      AppLogger.log("Codex initialize for \(entry.id)", level: .debug)
      _ = try await withTimeout(seconds: 15) {
        try await session.sendRequest(method: "initialize", params: initParams)
      }
    } catch {
      AppLogger.log("Codex initialize failed for \(entry.id): \(error)", level: .error)
      await session.terminate()
      throw CodexError(message: "Codex app-server did not respond to initialize. Check that `codex app-server` works in Terminal.")
    }

    try await session.sendNotification(method: "initialized", params: nil)
    AppLogger.log("Codex initialized for \(entry.id)", level: .info)

    let connectedPayload = JSONValue.object([
      "method": .string("codex/connected"),
      "params": JSONValue.object([
        "workspaceId": .string(entry.id)
      ])
    ])
    let event = AppServerEvent(workspace_id: entry.id, message: connectedPayload)
    do {
      try eventManager.emit("app-server-event", payload: event)
    } catch {
      // Ignore emit errors.
    }

    return session
  }

  static func checkCodexInstallation(codexBin: String?) async throws -> String? {
    let process = try buildCodexProcess(codexBin: codexBin, args: ["--version"])
    let output: ProcessOutput
    do {
      output = try await runProcess(process, timeout: 5)
    } catch is ProcessTimeoutError {
      throw CodexError(message: "Timed out while checking Codex CLI. Make sure `codex --version` runs in Terminal.")
    } catch {
      if (error as NSError).domain == NSCocoaErrorDomain {
        throw CodexError(message: "Codex CLI not found. Install Codex and ensure `codex` is on your PATH.")
      }
      throw CodexError(message: error.localizedDescription)
    }

    guard output.status == 0 else {
      let detail = output.stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
      let fallback = output.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
      let message = detail.isEmpty ? fallback : detail
      if message.isEmpty {
        throw CodexError(message: "Codex CLI failed to start. Try running `codex --version` in Terminal.")
      }
      throw CodexError(message: "Codex CLI failed to start: \(message). Try running `codex --version` in Terminal.")
    }

    let version = output.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
    return version.isEmpty ? nil : version
  }

  static func buildCodexProcess(codexBin: String?, args: [String]) throws -> Process {
    let trimmed = codexBin?.trimmingCharacters(in: .whitespacesAndNewlines)
    let useDefault = trimmed == nil || trimmed?.isEmpty == true
    let bin = useDefault ? "codex" : trimmed!

    let process = Process()
    if bin.contains("/") {
      process.executableURL = URL(fileURLWithPath: bin)
      process.arguments = args
    } else {
      process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
      process.arguments = [bin] + args
    }

    var env = ProcessInfo.processInfo.environment
    if useDefault {
      var paths = env["PATH"]?.split(separator: ":").map(String.init) ?? []
      var extras = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin"
      ]
      if let home = env["HOME"] {
        extras.append("\(home)/.local/bin")
        extras.append("\(home)/.cargo/bin")
      }
      for extra in extras where !paths.contains(extra) {
        paths.append(extra)
      }
      env["PATH"] = paths.joined(separator: ":")
    }
    process.environment = env

    return process
  }

  private static func startStdoutListener(
    handle: FileHandle,
    session: WorkspaceSession,
    eventManager: VeloxEventManager,
    workspaceId: String
  ) {
    let queue = DispatchQueue(label: "codex.stdout.\(workspaceId)")
    var buffer = Data()
    handle.readabilityHandler = { fileHandle in
      let data = fileHandle.availableData
      if data.isEmpty {
        return
      }
      queue.async {
        buffer.append(data)
        while let range = buffer.range(of: Data([0x0a])) {
          let lineData = buffer.subdata(in: 0..<range.lowerBound)
          buffer.removeSubrange(0...range.lowerBound)
          if lineData.isEmpty {
            continue
          }
          let line = String(data: lineData, encoding: .utf8) ?? ""
          let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
          if trimmed.isEmpty {
            continue
          }
          AppLogger.log("codex stdout: \(trimmed)", level: .debug)
          guard let jsonData = trimmed.data(using: .utf8) else {
            continue
          }
          do {
            let value = try JSONDecoder().decode(JSONValue.self, from: jsonData)
            Task {
              await session.handleIncoming(value, eventManager: eventManager, workspaceId: workspaceId)
            }
          } catch {
            AppLogger.log("codex stdout parse error: \(error)", level: .warn)
            let payload = JSONValue.object([
              "method": .string("codex/parseError"),
              "params": JSONValue.object([
                "error": .string(error.localizedDescription),
                "raw": .string(trimmed)
              ])
            ])
            let event = AppServerEvent(workspace_id: workspaceId, message: payload)
            do {
              try eventManager.emit("app-server-event", payload: event)
            } catch {
              // Ignore emit errors.
            }
          }
        }
      }
    }
  }

  private static func startStderrListener(
    handle: FileHandle,
    eventManager: VeloxEventManager,
    workspaceId: String
  ) {
    let queue = DispatchQueue(label: "codex.stderr.\(workspaceId)")
    var buffer = Data()
    handle.readabilityHandler = { fileHandle in
      let data = fileHandle.availableData
      if data.isEmpty {
        return
      }
      queue.async {
        buffer.append(data)
        while let range = buffer.range(of: Data([0x0a])) {
          let lineData = buffer.subdata(in: 0..<range.lowerBound)
          buffer.removeSubrange(0...range.lowerBound)
          if lineData.isEmpty {
            continue
          }
          let line = String(data: lineData, encoding: .utf8) ?? ""
          let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
          if trimmed.isEmpty {
            continue
          }
          AppLogger.log("codex stderr: \(trimmed)", level: .debug)
          let payload = JSONValue.object([
            "method": .string("codex/stderr"),
            "params": JSONValue.object([
              "message": .string(trimmed)
            ])
          ])
          let event = AppServerEvent(workspace_id: workspaceId, message: payload)
          do {
            try eventManager.emit("app-server-event", payload: event)
          } catch {
            // Ignore emit errors.
          }
        }
      }
    }
  }
}

func withTimeout<T>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
  try await withThrowingTaskGroup(of: T.self) { group in
    group.addTask {
      try await operation()
    }
    group.addTask {
      try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
      throw ProcessTimeoutError(seconds: seconds)
    }
    guard let result = try await group.next() else {
      throw ProcessTimeoutError(seconds: seconds)
    }
    group.cancelAll()
    return result
  }
}
