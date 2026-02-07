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

  var ws = winsize()
  ws.ws_col = UInt16(cols)
  ws.ws_row = UInt16(rows)
  ws.ws_xpixel = 0
  ws.ws_ypixel = 0

  var masterFd: Int32 = -1
  var slaveFd: Int32 = -1

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

    // Set locale
    setenv("LC_ALL", "en_US.UTF-8", 1)
    setenv("LANG", "en_US.UTF-8", 1)

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
  let key = "\(workspaceId):\(terminalId)"
  let source = DispatchSource.makeReadSource(fileDescriptor: masterFd, queue: DispatchQueue(label: "terminal.read.\(key)"))
  handle.readerSource = source

  let wId = workspaceId
  let tId = terminalId

  source.setEventHandler { [weak handle] in
    guard let handle = handle else { return }
    var buffer = [UInt8](repeating: 0, count: 4096)
    let bytesRead = read(handle.masterFd, &buffer, buffer.count)
    if bytesRead > 0 {
      let data = Data(buffer[0..<bytesRead])
      let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
      if !text.isEmpty {
        let event = TerminalOutputEvent(workspaceId: wId, terminalId: tId, data: text)
        try? eventManager.emit("terminal-output", payload: event)
      }
    } else if bytesRead <= 0 {
      // EOF or error — terminal closed
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
  bytes.withUnsafeBytes { ptr in
    _ = Darwin.write(handle.masterFd, ptr.baseAddress, ptr.count)
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
  guard let handle = state.removeTerminal(id: key) else { return }
  handle.readerSource?.cancel()
  handle.readerSource = nil
  kill(handle.childPid, SIGHUP)
  close(handle.masterFd)
}
