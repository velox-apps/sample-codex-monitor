import Foundation
import VeloxRuntimeWry

// MARK: - Window State

/// Manages the window reference for hide/show/drag operations.
/// Geometry persistence is handled by `WindowStatePlugin`.
final class WindowState: @unchecked Sendable {
  private let lock = NSLock()
  private var window: VeloxRuntimeWry.Window?

  func setWindow(_ window: VeloxRuntimeWry.Window) {
    lock.lock()
    defer { lock.unlock() }
    self.window = window
  }

  func startDragging() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard let window else { return false }
    return window.startDragging()
  }

  func hide() {
    lock.lock()
    defer { lock.unlock() }
    window?.setVisible(false)
  }

  func show() {
    lock.lock()
    defer { lock.unlock() }
    window?.setVisible(true)
    _ = window?.focus()
  }
}
