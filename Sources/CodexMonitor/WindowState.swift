import Foundation
import VeloxRuntimeWry

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
    guard let window else {
      return false
    }
    return window.startDragging()
  }
}
