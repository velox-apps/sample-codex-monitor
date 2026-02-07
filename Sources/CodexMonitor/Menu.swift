import Foundation
import VeloxRuntime
import VeloxRuntimeWry

// MARK: - Menu Accelerator Types

struct MenuAcceleratorUpdate: Codable, Sendable {
  let id: String
  let accelerator: String?
}

struct MenuSetAcceleratorsArgs: Codable, Sendable {
  let updates: [MenuAcceleratorUpdate]
}

// MARK: - Menu Event Names

/// All menu event names that the frontend listens for.
enum MenuEventName {
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

// MARK: - Menu Item Registry

/// Keeps references to menu items for dynamic accelerator updates.
final class MenuItemRegistry: @unchecked Sendable {
  private let lock = NSLock()
  private var items: [String: VeloxRuntimeWry.MenuItem] = [:]

  func register(_ id: String, item: VeloxRuntimeWry.MenuItem) {
    lock.lock()
    defer { lock.unlock() }
    items[id] = item
  }

  func setAccelerator(_ id: String, accelerator: String?) {
    lock.lock()
    let item = items[id]
    lock.unlock()
    item?.setAccelerator(accelerator)
  }
}

/// Shared registry for accelerator updates from the frontend.
let menuItemRegistry = MenuItemRegistry()

// MARK: - Menu Set Accelerators

func menuSetAccelerators(updates: [MenuAcceleratorUpdate]) {
  for update in updates {
    menuItemRegistry.setAccelerator(update.id, accelerator: update.accelerator)
  }
}

// MARK: - Menu Builder

/// Map from menu item identifier → frontend event name.
private let menuIdToEvent: [String: String] = [
  "file_new_agent": MenuEventName.newAgent,
  "file_new_worktree_agent": MenuEventName.newWorktreeAgent,
  "file_new_clone_agent": MenuEventName.newCloneAgent,
  "file_add_workspace": MenuEventName.addWorkspace,
  "file_open_settings": MenuEventName.openSettings,
  "view_toggle_projects_sidebar": MenuEventName.toggleProjectsSidebar,
  "view_toggle_git_sidebar": MenuEventName.toggleGitSidebar,
  "view_toggle_debug_panel": MenuEventName.toggleDebugPanel,
  "view_toggle_terminal": MenuEventName.toggleTerminal,
  "view_next_agent": MenuEventName.nextAgent,
  "view_prev_agent": MenuEventName.prevAgent,
  "view_next_workspace": MenuEventName.nextWorkspace,
  "view_prev_workspace": MenuEventName.prevWorkspace,
  "composer_cycle_model": MenuEventName.composerCycleModel,
  "composer_cycle_access": MenuEventName.composerCycleAccess,
  "composer_cycle_reasoning": MenuEventName.composerCycleReasoning,
  "composer_cycle_collaboration": MenuEventName.composerCycleCollaboration,
  "check_for_updates": MenuEventName.updaterCheck,
]

/// Builds the native macOS menu bar and installs it. Must be called on the main thread.
/// Returns the MenuBar to keep it alive for the duration of the app.
@discardableResult
func buildNativeMenuBar(eventManager: VeloxEventManager, windowState: WindowState) -> VeloxRuntimeWry.MenuBar? {
  guard Thread.isMainThread else { return nil }
  guard let menuBar = VeloxRuntimeWry.MenuBar() else { return nil }

  // -- App menu --
  if let appMenu = VeloxRuntimeWry.Submenu(title: "CodexMonitor") {
    if let about = VeloxRuntimeWry.PredefinedMenuItem(item: .about, aboutMetadata: .init(name: "CodexMonitor")) {
      appMenu.append(about)
    }
    if let sep = VeloxRuntimeWry.MenuSeparator() { appMenu.append(sep) }
    if let settings = VeloxRuntimeWry.MenuItem(identifier: "file_open_settings", title: "Settings...", accelerator: "CmdOrCtrl+,") {
      menuItemRegistry.register("file_open_settings", item: settings)
      appMenu.append(settings)
    }
    if let sep = VeloxRuntimeWry.MenuSeparator() { appMenu.append(sep) }
    if let hide = VeloxRuntimeWry.PredefinedMenuItem(item: .hide) { appMenu.append(hide) }
    if let hideOthers = VeloxRuntimeWry.PredefinedMenuItem(item: .hideOthers) { appMenu.append(hideOthers) }
    if let sep = VeloxRuntimeWry.MenuSeparator() { appMenu.append(sep) }
    if let quit = VeloxRuntimeWry.PredefinedMenuItem(item: .quit) { appMenu.append(quit) }
    menuBar.append(appMenu)
  }

  // -- File menu --
  if let fileMenu = VeloxRuntimeWry.Submenu(title: "File") {
    let fileItems: [(String, String, String?)] = [
      ("file_new_agent", "New Agent", nil),
      ("file_new_worktree_agent", "New Worktree Agent", nil),
      ("file_new_clone_agent", "New Clone Agent", nil),
    ]
    for (id, title, accel) in fileItems {
      if let item = VeloxRuntimeWry.MenuItem(identifier: id, title: title, accelerator: accel) {
        menuItemRegistry.register(id, item: item)
        fileMenu.append(item)
      }
    }
    if let sep = VeloxRuntimeWry.MenuSeparator() { fileMenu.append(sep) }
    if let addWs = VeloxRuntimeWry.MenuItem(identifier: "file_add_workspace", title: "Add Workspace...") {
      menuItemRegistry.register("file_add_workspace", item: addWs)
      fileMenu.append(addWs)
    }
    if let sep = VeloxRuntimeWry.MenuSeparator() { fileMenu.append(sep) }
    if let closeWin = VeloxRuntimeWry.PredefinedMenuItem(item: .closeWindow) { fileMenu.append(closeWin) }
    menuBar.append(fileMenu)
  }

  // -- Edit menu --
  if let editMenu = VeloxRuntimeWry.Submenu(title: "Edit") {
    if let undo = VeloxRuntimeWry.PredefinedMenuItem(item: .undo) { editMenu.append(undo) }
    if let redo = VeloxRuntimeWry.PredefinedMenuItem(item: .redo) { editMenu.append(redo) }
    if let sep = VeloxRuntimeWry.MenuSeparator() { editMenu.append(sep) }
    if let cut = VeloxRuntimeWry.PredefinedMenuItem(item: .cut) { editMenu.append(cut) }
    if let copy = VeloxRuntimeWry.PredefinedMenuItem(item: .copy) { editMenu.append(copy) }
    if let paste = VeloxRuntimeWry.PredefinedMenuItem(item: .paste) { editMenu.append(paste) }
    if let selectAll = VeloxRuntimeWry.PredefinedMenuItem(item: .selectAll) { editMenu.append(selectAll) }
    menuBar.append(editMenu)
  }

  // -- Composer menu --
  if let composerMenu = VeloxRuntimeWry.Submenu(title: "Composer") {
    let composerItems: [(String, String, String?)] = [
      ("composer_cycle_model", "Cycle Model", "CmdOrCtrl+Shift+M"),
      ("composer_cycle_access", "Cycle Access Mode", "CmdOrCtrl+Shift+A"),
      ("composer_cycle_reasoning", "Cycle Reasoning Mode", "CmdOrCtrl+Shift+R"),
      ("composer_cycle_collaboration", "Cycle Collaboration Mode", "Shift+Tab"),
    ]
    for (id, title, accel) in composerItems {
      if let item = VeloxRuntimeWry.MenuItem(identifier: id, title: title, accelerator: accel) {
        menuItemRegistry.register(id, item: item)
        composerMenu.append(item)
      }
    }
    menuBar.append(composerMenu)
  }

  // -- View menu --
  if let viewMenu = VeloxRuntimeWry.Submenu(title: "View") {
    let viewItems: [(String, String, String?)] = [
      ("view_toggle_projects_sidebar", "Toggle Projects Sidebar", nil),
      ("view_toggle_git_sidebar", "Toggle Git Sidebar", nil),
    ]
    for (id, title, accel) in viewItems {
      if let item = VeloxRuntimeWry.MenuItem(identifier: id, title: title, accelerator: accel) {
        menuItemRegistry.register(id, item: item)
        viewMenu.append(item)
      }
    }
    if let sep = VeloxRuntimeWry.MenuSeparator() { viewMenu.append(sep) }
    let viewItems2: [(String, String, String?)] = [
      ("view_toggle_debug_panel", "Toggle Debug Panel", "CmdOrCtrl+Shift+D"),
      ("view_toggle_terminal", "Toggle Terminal", "CmdOrCtrl+Shift+T"),
    ]
    for (id, title, accel) in viewItems2 {
      if let item = VeloxRuntimeWry.MenuItem(identifier: id, title: title, accelerator: accel) {
        menuItemRegistry.register(id, item: item)
        viewMenu.append(item)
      }
    }
    if let sep = VeloxRuntimeWry.MenuSeparator() { viewMenu.append(sep) }
    let navItems: [(String, String, String?)] = [
      ("view_next_agent", "Next Agent", nil),
      ("view_prev_agent", "Previous Agent", nil),
      ("view_next_workspace", "Next Workspace", nil),
      ("view_prev_workspace", "Previous Workspace", nil),
    ]
    for (id, title, accel) in navItems {
      if let item = VeloxRuntimeWry.MenuItem(identifier: id, title: title, accelerator: accel) {
        menuItemRegistry.register(id, item: item)
        viewMenu.append(item)
      }
    }
    if let sep = VeloxRuntimeWry.MenuSeparator() { viewMenu.append(sep) }
    if let fs = VeloxRuntimeWry.PredefinedMenuItem(item: .fullscreen) { viewMenu.append(fs) }
    menuBar.append(viewMenu)
  }

  // -- Window menu --
  if let windowMenu = VeloxRuntimeWry.Submenu(title: "Window") {
    if let min = VeloxRuntimeWry.PredefinedMenuItem(item: .minimize) { windowMenu.append(min) }
    if let max = VeloxRuntimeWry.PredefinedMenuItem(item: .maximize) { windowMenu.append(max) }
    if let sep = VeloxRuntimeWry.MenuSeparator() { windowMenu.append(sep) }
    if let close = VeloxRuntimeWry.PredefinedMenuItem(item: .closeWindow) { windowMenu.append(close) }
    windowMenu.setAsWindowsMenuForNSApp()
    menuBar.append(windowMenu)
  }

  // -- Help menu --
  if let helpMenu = VeloxRuntimeWry.Submenu(title: "Help") {
    helpMenu.setAsHelpMenuForNSApp()
    menuBar.append(helpMenu)
  }

  menuBar.setAsApplicationMenu()

  // Register menu event handler to forward clicks to the frontend.
  _ = MenuEventMonitor.shared.addHandler { menuId in
    if let eventName = menuIdToEvent[menuId] {
      windowState.show()
      do {
        try eventManager.emit(eventName, payload: JSONValue.null)
      } catch {
        AppLogger.log("Menu event emit error: \(error)", level: .warn)
      }
    }
  }

  AppLogger.log("Native menu bar installed", level: .info)
  return menuBar
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
