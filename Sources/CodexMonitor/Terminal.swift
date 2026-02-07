import Foundation
#if canImport(Darwin)
import Darwin
#endif
import VeloxRuntimeWry
import CTerminalHelpers

// MARK: - Terminal Events

struct TerminalOutputEvent: Codable, Sendable {
  let workspaceId: String
  let terminalId: String
  let data: String
}

struct TerminalExitEvent: Codable, Sendable {
  let workspaceId: String
  let terminalId: String
}

// MARK: - Terminal Commands

func terminalOpen(
  workspaceId: String,
  terminalId: String,
  cols: Int,
  rows: Int,
  state: AppState,
  eventManager: VeloxEventManager
) throws -> [String: String] {
  guard let entry = state.getWorkspace(id: workspaceId) else {
    throw CodexError(message: "workspace not found")
  }

  let key = "\(workspaceId):\(terminalId)"
  if state.getTerminal(id: key) != nil {
    return ["id": terminalId]
  }

  var ws = winsize()
  ws.ws_col = UInt16(cols)
  ws.ws_row = UInt16(rows)
  ws.ws_xpixel = 0
  ws.ws_ypixel = 0

  var masterFd: Int32 = -1

  // Create pseudo-terminal pair
  var childPid: pid_t = 0
  let result = withUnsafeMutablePointer(to: &ws) { wsPtr in
    forkpty(&masterFd, nil, nil, wsPtr)
  }

  if result < 0 {
    throw CodexError(message: "forkpty failed: \(String(cString: strerror(errno)))")
  }

  if result == 0 {
    // Child process
    let env = ProcessInfo.processInfo.environment
    let cwd = entry.path
    chdir(cwd)

    // Set locale and terminal type
    setenv("LC_ALL", "en_US.UTF-8", 1)
    setenv("LANG", "en_US.UTF-8", 1)
    setenv("TERM", "xterm-256color", 1)

    // Get shell
    let shell = env["SHELL"] ?? "/bin/zsh"

    // exec the shell
    let shellCStr = shell.withCString { strdup($0) }!
    let dashShell = "-\((shell as NSString).lastPathComponent)"
    let dashCStr = dashShell.withCString { strdup($0) }!
    var argv: [UnsafeMutablePointer<CChar>?] = [dashCStr, nil]
    execvp(shellCStr, &argv)
    // If exec fails:
    _exit(1)
  }

  // Parent process
  childPid = result

  let handle = TerminalSessionHandle(masterFd: masterFd, childPid: childPid)

  // Start reader
  let source = DispatchSource.makeReadSource(fileDescriptor: masterFd, queue: DispatchQueue(label: "terminal.read.\(key)"))
  handle.readerSource = source

  let wId = workspaceId
  let tId = terminalId

  source.setEventHandler { [weak handle] in
    guard let handle = handle else { return }
    var buffer = [UInt8](repeating: 0, count: 4096)
    let bytesRead = read(handle.masterFd, &buffer, buffer.count)
    if bytesRead > 0 {
      handle.pendingBytes.append(contentsOf: buffer[0..<bytesRead])

      // Find the last valid UTF-8 boundary
      let validEnd = utf8ValidPrefix(handle.pendingBytes)
      if validEnd > 0 {
        let validBytes = Array(handle.pendingBytes[0..<validEnd])
        handle.pendingBytes = Array(handle.pendingBytes[validEnd...])
        let text = String(decoding: validBytes, as: UTF8.self)
        if !text.isEmpty {
          let event = TerminalOutputEvent(workspaceId: wId, terminalId: tId, data: text)
          try? eventManager.emit("terminal-output", payload: event)
        }
      }
    } else if bytesRead <= 0 {
      // EOF or error — flush any remaining pending bytes
      if !handle.pendingBytes.isEmpty {
        let text = String(decoding: handle.pendingBytes, as: UTF8.self)
        handle.pendingBytes.removeAll()
        if !text.isEmpty {
          let event = TerminalOutputEvent(workspaceId: wId, terminalId: tId, data: text)
          try? eventManager.emit("terminal-output", payload: event)
        }
      }
      source.cancel()
      let exitEvent = TerminalExitEvent(workspaceId: wId, terminalId: tId)
      try? eventManager.emit("terminal-exit", payload: exitEvent)
    }
  }

  source.setCancelHandler {
    close(masterFd)
  }

  source.resume()

  state.setTerminal(id: key, handle: handle)

  return ["id": terminalId]
}

func terminalWrite(
  workspaceId: String,
  terminalId: String,
  data: String,
  state: AppState
) throws {
  let key = "\(workspaceId):\(terminalId)"
  guard let handle = state.getTerminal(id: key) else {
    throw CodexError(message: "terminal session not found")
  }
  guard let bytes = data.data(using: .utf8) else { return }
  let written = bytes.withUnsafeBytes { ptr -> Int in
    Darwin.write(handle.masterFd, ptr.baseAddress, ptr.count)
  }
  if written < 0 {
    let err = errno
    if err == EPIPE || err == EIO || err == EBADF {
      state.removeTerminal(id: key)?.cleanup()
    }
    throw CodexError(message: "terminal write failed: \(String(cString: strerror(err)))")
  }
}

func terminalResize(
  workspaceId: String,
  terminalId: String,
  cols: Int,
  rows: Int,
  state: AppState
) throws {
  let key = "\(workspaceId):\(terminalId)"
  guard let handle = state.getTerminal(id: key) else {
    throw CodexError(message: "terminal session not found")
  }
  var ws = winsize()
  ws.ws_col = UInt16(cols)
  ws.ws_row = UInt16(rows)
  ws.ws_xpixel = 0
  ws.ws_ypixel = 0
  _ = withUnsafePointer(to: &ws) { wsPtr in
    terminal_set_winsize(handle.masterFd, wsPtr)
  }
}

func terminalClose(
  workspaceId: String,
  terminalId: String,
  state: AppState
) {
  let key = "\(workspaceId):\(terminalId)"
  state.removeTerminal(id: key)?.cleanup()
}

// MARK: - UTF-8 Helpers

/// Returns the number of bytes from the start of `bytes` that form complete UTF-8 sequences.
/// Any trailing incomplete multi-byte sequence is excluded so it can be held for the next read.
private func utf8ValidPrefix(_ bytes: [UInt8]) -> Int {
  let count = bytes.count
  if count == 0 { return 0 }

  // Scan backwards to find a potential incomplete trailing sequence.
  // A UTF-8 leading byte has bit patterns:
  //   0xxxxxxx (1-byte, 0x00..0x7F) — always complete
  //   110xxxxx (2-byte, 0xC0..0xDF) — needs 1 continuation
  //   1110xxxx (3-byte, 0xE0..0xEF) — needs 2 continuations
  //   11110xxx (4-byte, 0xF0..0xF7) — needs 3 continuations
  // Continuation bytes: 10xxxxxx (0x80..0xBF)

  // Walk backwards over continuation bytes (max 3)
  var i = count - 1
  var continuations = 0
  while i >= 0 && continuations < 3 && (bytes[i] & 0xC0) == 0x80 {
    i -= 1
    continuations += 1
  }

  // If we walked past the beginning, all bytes are continuations — no valid prefix
  if i < 0 { return 0 }

  let leadByte = bytes[i]
  let expectedLen: Int
  if leadByte < 0x80 {
    expectedLen = 1
  } else if leadByte & 0xE0 == 0xC0 {
    expectedLen = 2
  } else if leadByte & 0xF0 == 0xE0 {
    expectedLen = 3
  } else if leadByte & 0xF8 == 0xF0 {
    expectedLen = 4
  } else {
    // Invalid leading byte — include everything up to it and let the decoder handle it
    return count
  }

  let available = continuations + 1 // lead byte + continuations found
  if available < expectedLen {
    // Incomplete sequence at the end — exclude it
    return i
  }

  // The trailing sequence is complete
  return count
}
