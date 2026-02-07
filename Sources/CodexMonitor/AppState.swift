import Foundation
import VeloxRuntime

final class AppState: @unchecked Sendable {
  private let lock = NSLock()
  private var workspaces: [String: WorkspaceEntry]
  private var sessions: [String: WorkspaceSession]
  private var appSettings: AppSettings
  private var loginCancels: [String: LoginCancelState] = [:]
  private var terminalSessions: [String: TerminalSessionHandle] = [:]
  let storagePath: URL
  let settingsPath: URL

  init(
    workspaces: [String: WorkspaceEntry],
    sessions: [String: WorkspaceSession] = [:],
    appSettings: AppSettings,
    storagePath: URL,
    settingsPath: URL
  ) {
    self.workspaces = workspaces
    self.sessions = sessions
    self.appSettings = appSettings
    self.storagePath = storagePath
    self.settingsPath = settingsPath
  }

  static func load(config: VeloxConfig) -> AppState {
    let baseDir: URL
    if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
      baseDir = appSupport.appendingPathComponent(config.identifier)
    } else {
      baseDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
    let storagePath = baseDir.appendingPathComponent("workspaces.json")
    let settingsPath = baseDir.appendingPathComponent("settings.json")
    let workspaces = (try? Storage.readWorkspaces(from: storagePath)) ?? [:]
    let appSettings = (try? Storage.readSettings(from: settingsPath)) ?? AppSettings()
    return AppState(
      workspaces: workspaces,
      appSettings: appSettings,
      storagePath: storagePath,
      settingsPath: settingsPath
    )
  }

  func listWorkspaces() -> [WorkspaceEntry] {
    lock.lock()
    defer { lock.unlock() }
    return Array(workspaces.values)
  }

  func getWorkspace(id: String) -> WorkspaceEntry? {
    lock.lock()
    defer { lock.unlock() }
    return workspaces[id]
  }

  func setWorkspace(_ entry: WorkspaceEntry) {
    lock.lock()
    defer { lock.unlock() }
    workspaces[entry.id] = entry
  }

  func removeWorkspace(id: String) {
    lock.lock()
    defer { lock.unlock() }
    workspaces.removeValue(forKey: id)
  }

  func setWorkspaces(_ entries: [WorkspaceEntry]) {
    lock.lock()
    defer { lock.unlock() }
    var updated: [String: WorkspaceEntry] = [:]
    for entry in entries {
      updated[entry.id] = entry
    }
    workspaces = updated
  }

  func listSessions() -> [String: WorkspaceSession] {
    lock.lock()
    defer { lock.unlock() }
    return sessions
  }

  func getSession(id: String) -> WorkspaceSession? {
    lock.lock()
    defer { lock.unlock() }
    return sessions[id]
  }

  func setSession(id: String, session: WorkspaceSession) {
    lock.lock()
    defer { lock.unlock() }
    sessions[id] = session
  }

  func removeSession(id: String) -> WorkspaceSession? {
    lock.lock()
    defer { lock.unlock() }
    return sessions.removeValue(forKey: id)
  }

  func isConnected(id: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return sessions[id] != nil
  }

  func getAppSettings() -> AppSettings {
    lock.lock()
    defer { lock.unlock() }
    return appSettings
  }

  func setAppSettings(_ settings: AppSettings) {
    lock.lock()
    defer { lock.unlock() }
    appSettings = settings
  }

  // MARK: - Login Cancels

  func getLoginCancel(workspaceId: String) -> LoginCancelState? {
    lock.lock()
    defer { lock.unlock() }
    return loginCancels[workspaceId]
  }

  func setLoginCancel(workspaceId: String, state: LoginCancelState) {
    lock.lock()
    defer { lock.unlock() }
    loginCancels[workspaceId] = state
  }

  func removeLoginCancel(workspaceId: String) -> LoginCancelState? {
    lock.lock()
    defer { lock.unlock() }
    return loginCancels.removeValue(forKey: workspaceId)
  }

  // MARK: - Terminal Sessions

  func getTerminal(id: String) -> TerminalSessionHandle? {
    lock.lock()
    defer { lock.unlock() }
    return terminalSessions[id]
  }

  func setTerminal(id: String, handle: TerminalSessionHandle) {
    lock.lock()
    defer { lock.unlock() }
    terminalSessions[id] = handle
  }

  func removeTerminal(id: String) -> TerminalSessionHandle? {
    lock.lock()
    defer { lock.unlock() }
    return terminalSessions.removeValue(forKey: id)
  }
}

// MARK: - Login Cancel State

enum LoginCancelState: @unchecked Sendable {
  case pendingStart((() -> Void))
  case loginId(String)
}

// MARK: - Terminal Session Handle

final class TerminalSessionHandle: @unchecked Sendable {
  let masterFd: Int32
  let childPid: pid_t
  var readerSource: DispatchSourceRead?

  init(masterFd: Int32, childPid: pid_t) {
    self.masterFd = masterFd
    self.childPid = childPid
  }
}
