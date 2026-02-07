import Foundation
import VeloxRuntimeWry

// MARK: - Menu Accelerator Types

struct MenuAcceleratorUpdate: Codable, Sendable {
  let id: String
  let accelerator: String?
}

struct MenuSetAcceleratorsArgs: Codable, Sendable {
  let updates: [MenuAcceleratorUpdate]
}

// MARK: - Menu Events

/// All menu event names that the frontend listens for.
enum MenuEvent {
  static let newAgent = "menu-new-agent"
  static let newWorktreeAgent = "menu-new-worktree-agent"
  static let newCloneAgent = "menu-new-clone-agent"
  static let addWorkspace = "menu-add-workspace"
  static let openSettings = "menu-open-settings"
  static let toggleProjectsSidebar = "menu-toggle-projects-sidebar"
  static let toggleGitSidebar = "menu-toggle-git-sidebar"
  static let toggleDebugPanel = "menu-toggle-debug-panel"
  static let toggleTerminal = "menu-toggle-terminal"
  static let nextAgent = "menu-next-agent"
  static let prevAgent = "menu-prev-agent"
  static let nextWorkspace = "menu-next-workspace"
  static let prevWorkspace = "menu-prev-workspace"
  static let cycleModel = "menu-cycle-model"
  static let cycleAccess = "menu-cycle-access"
  static let cycleReasoning = "menu-cycle-reasoning"
  static let cycleCollaboration = "menu-cycle-collaboration"
  static let composerCycleModel = "menu-composer-cycle-model"
  static let composerCycleAccess = "menu-composer-cycle-access"
  static let composerCycleReasoning = "menu-composer-cycle-reasoning"
  static let composerCycleCollaboration = "menu-composer-cycle-collaboration"
  static let updaterCheck = "updater-check"
}

// MARK: - Menu Set Accelerators

/// Updates keyboard shortcuts. In this Swift/Velox port we don't have native
/// menu items to update (no NSMenu), so this is a no-op that succeeds silently.
/// The frontend handles shortcuts via JS key listeners.
func menuSetAccelerators(updates: [MenuAcceleratorUpdate]) {
  // No-op: native menu not yet implemented in Velox.
  // The frontend uses keyboard event listeners driven by AppSettings shortcuts.
}

// MARK: - Notification Commands

/// Returns whether this is a debug (unsigned) build.
func isMacosDebugBuild() -> Bool {
  // Check for code signature
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
  process.arguments = ["-v", "--deep", Bundle.main.bundlePath]
  let pipe = Pipe()
  process.standardOutput = pipe
  process.standardError = pipe
  do {
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus != 0
  } catch {
    return true
  }
}

/// Sends a notification using osascript as a fallback (for unsigned/debug builds).
func sendNotificationFallback(title: String, body: String) throws {
  let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
  let escapedBody = body.replacingOccurrences(of: "\"", with: "\\\"")
  let script = "display notification \"\(escapedBody)\" with title \"\(escapedTitle)\""
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
  process.arguments = ["-e", script]
  try process.run()
  process.waitUntilExit()
}
