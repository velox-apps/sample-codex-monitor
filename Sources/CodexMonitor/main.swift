import Foundation
import VeloxRuntime
import VeloxRuntimeWry
import VeloxPlugins

struct DevServerProxy {
  let baseURL: URL

  init?(devUrl: String) {
    guard let url = URL(string: devUrl) else { return nil }
    self.baseURL = url
  }

  func fetch(path: String) -> (data: Data, mimeType: String, status: Int)? {
    var normalizedPath = path
    if !normalizedPath.hasPrefix("/") {
      normalizedPath = "/" + normalizedPath
    }

    let parts = normalizedPath.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
    let pathPart = String(parts.first ?? "")
    let queryPart = parts.count > 1 ? "?\(parts[1])" : ""

    if pathPart == "/" {
      normalizedPath = "/index.html" + queryPart
    } else {
      normalizedPath = pathPart + queryPart
    }

    guard let requestURL = URL(string: normalizedPath, relativeTo: baseURL) else {
      return nil
    }

    var request = URLRequest(url: requestURL)
    request.timeoutInterval = 5

    let semaphore = DispatchSemaphore(value: 0)
    var result: (data: Data, mimeType: String, status: Int)?

    let task = URLSession.shared.dataTask(with: request) { data, response, error in
      defer { semaphore.signal() }
      guard error == nil,
            let data = data,
            let httpResponse = response as? HTTPURLResponse else {
        return
      }

      let header = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream"
      let mimeType = header.components(separatedBy: ";").first ?? header
      result = (data, mimeType, httpResponse.statusCode)
    }
    task.resume()
    semaphore.wait()

    return result
  }
}

struct AssetBundle {
  let basePath: String

  init(projectDir: URL, frontendDist: String?) {
    let configured = frontendDist ?? "assets"
    let executablePath = CommandLine.arguments.first ?? ""
    let executableDir = (executablePath as NSString).deletingLastPathComponent

    let candidatePaths: [String] = [
      projectDir.appendingPathComponent(configured).path,
      (executableDir as NSString).appendingPathComponent(configured),
      (executableDir as NSString).appendingPathComponent("../\(configured)"),
      Bundle.main.resourcePath.map { ($0 as NSString).appendingPathComponent(configured) } ?? ""
    ]

    for path in candidatePaths {
      let expanded = (path as NSString).standardizingPath
      if FileManager.default.fileExists(atPath: expanded) {
        basePath = expanded
        return
      }
    }

    basePath = projectDir.appendingPathComponent(configured).path
  }

  func loadAsset(path: String) -> (data: Data, mimeType: String)? {
    var cleanPath = path
    if cleanPath.hasPrefix("/") {
      cleanPath = String(cleanPath.dropFirst())
    }
    if cleanPath.isEmpty {
      cleanPath = "index.html"
    }

    let fullPath = (basePath as NSString).appendingPathComponent(cleanPath)
    guard let data = FileManager.default.contents(atPath: fullPath) else {
      return nil
    }

    return (data, mimeType(for: cleanPath))
  }

  private func mimeType(for path: String) -> String {
    let ext = (path as NSString).pathExtension.lowercased()
    switch ext {
    case "html", "htm": return "text/html"
    case "css": return "text/css"
    case "js": return "application/javascript"
    case "json": return "application/json"
    case "png": return "image/png"
    case "jpg", "jpeg": return "image/jpeg"
    case "gif": return "image/gif"
    case "svg": return "image/svg+xml"
    case "ico": return "image/x-icon"
    case "woff": return "font/woff"
    case "woff2": return "font/woff2"
    case "ttf": return "font/ttf"
    default: return "application/octet-stream"
    }
  }
}

func main() {
  AppLogger.log("CodexMonitor starting", level: .info)
  guard Thread.isMainThread else {
    fatalError("CodexMonitor must run on the main thread")
  }

  let projectDir = URL(fileURLWithPath: #file)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

  let appBuilder: VeloxAppBuilder
  do {
    let config = try VeloxConfig.load(from: projectDir)
    appBuilder = VeloxAppBuilder(config: config)
  } catch {
    fatalError("Failed to load velox.json: \(error)")
  }

  let appState = AppState.load(config: appBuilder.config)
  appBuilder.manage(appState)

  let devUrl = ProcessInfo.processInfo.environment["VELOX_DEV_URL"]
    ?? appBuilder.config.build?.devUrl
  let devProxy = devUrl.flatMap { DevServerProxy(devUrl: $0) }
  if let devUrl {
    AppLogger.log("Dev server proxy enabled: \(devUrl)", level: .info)
  }

  let windowState = WindowState()
  appBuilder.onWindowCreated("main") { window, webview in
    windowState.setWindow(window)
    if let webview {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        let script = VeloxEventBridge.initScript + "\n" + VeloxInvokeBridge.initScript
        _ = webview.evaluate(script: script)
      }
    }
  }

  appBuilder.plugins {
    DialogPlugin()
    OpenerPlugin()
    ProcessPlugin()
  }

  registerCommands(
    registry: appBuilder.commandRegistry,
    state: appState,
    eventManager: appBuilder.eventManager,
    windowState: windowState,
    appVersion: appBuilder.config.version
  )

  let assets = AssetBundle(projectDir: projectDir, frontendDist: appBuilder.config.build?.frontendDist)

  let commandHandler = createCommandHandlerWithFallback(
    registry: appBuilder.commandRegistry,
    stateContainer: appBuilder.stateContainer,
    eventManager: appBuilder.eventManager,
    permissionManager: appBuilder.permissionManager
  )
  let eventHandler = createEventIPCHandler(manager: appBuilder.eventManager)

  do {
    try appBuilder
      .registerProtocol("ipc") { request in
        AppLogger.log("IPC request \(request.method) \(request.url)", level: .debug)
        let method = request.method.uppercased()
        if method == "OPTIONS" {
          return VeloxRuntimeWry.CustomProtocol.Response(
            status: 204,
            headers: [
              "Access-Control-Allow-Origin": "*",
              "Access-Control-Allow-Methods": "POST, OPTIONS",
              "Access-Control-Allow-Headers": "Content-Type"
            ],
            body: Data()
          )
        }

        if var response = eventHandler(request) {
          response.headers["Access-Control-Allow-Origin"] = "*"
          return response
        }

        return commandHandler(request)
      }
      .registerProtocol("app") { request in
        guard let url = URL(string: request.url) else {
          return VeloxRuntimeWry.CustomProtocol.Response(
            status: 400,
            headers: ["Content-Type": "text/plain"],
            body: Data("Invalid URL".utf8)
          )
        }

        if let proxy = devProxy {
          let pathWithQuery = url.path + (url.query.map { "?\($0)" } ?? "")
          if let result = proxy.fetch(path: pathWithQuery) {
            return VeloxRuntimeWry.CustomProtocol.Response(
              status: result.status,
              headers: ["Content-Type": result.mimeType, "Access-Control-Allow-Origin": "*"],
              mimeType: result.mimeType,
              body: result.data
            )
          }
        }

        if let asset = assets.loadAsset(path: url.path) {
          return VeloxRuntimeWry.CustomProtocol.Response(
            status: 200,
            headers: ["Content-Type": asset.mimeType],
            mimeType: asset.mimeType,
            body: asset.data
          )
        }

        return VeloxRuntimeWry.CustomProtocol.Response(
          status: 404,
          headers: ["Content-Type": "text/html"],
          body: Data("""
            <!doctype html>
            <html>
              <head><meta charset="utf-8"><title>CodexMonitor</title></head>
              <body style="font-family: -apple-system, BlinkMacSystemFont, sans-serif; padding: 24px;">
                <h2>Frontend not found</h2>
                <p>Missing asset: <code>\(url.path)</code></p>
                <p>If you are in dev mode, ensure the dev server is running on <code>\(devUrl ?? "http://localhost:1420")</code>.</p>
              </body>
            </html>
            """.utf8)
        )
      }
      .run { event in
        switch event {
        case .windowCloseRequested, .userExit:
          return .exit
        default:
          return .wait
        }
      }
  } catch {
    fatalError("CodexMonitor failed to start: \(error)")
  }
}

main()
