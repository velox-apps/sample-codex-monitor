import Foundation
import VeloxRuntime
import VeloxRuntimeWry

func createCommandHandlerWithFallback(
  registry: CommandRegistry,
  stateContainer: StateContainer = StateContainer(),
  eventManager: VeloxEventManager? = nil,
  permissionManager: PermissionManager? = nil
) -> VeloxRuntimeWry.CustomProtocol.Handler {
  return { request in
    guard let url = URL(string: request.url) else {
      return errorResponse(code: "InvalidURL", message: "Invalid request URL")
    }

    let command = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

    let webviewHandle = eventManager?.getWebviewHandle(request.webviewIdentifier)
      ?? eventManager?.getWebviewHandle("main")
    if webviewHandle == nil {
      AppLogger.log("IPC missing webview handle: \(request.webviewIdentifier)", level: .warn)
    }

    if let webviewHandle {
      let script = VeloxEventBridge.initScript + "\n" + VeloxInvokeBridge.initScript + "\n" + TauriCompat.shimScript
      _ = webviewHandle.evaluate(script: script)
    }

    let webviewLabel = eventManager?.resolveLabel(request.webviewIdentifier) ?? request.webviewIdentifier

    let context = CommandContext(
      command: command,
      rawBody: request.body,
      headers: request.headers,
      webviewId: webviewLabel,
      stateContainer: stateContainer,
      webview: webviewHandle
    )

    AppLogger.log("IPC invoke \(command) from \(request.webviewIdentifier)", level: .debug)
    let result = registry.invoke(command, context: context, permissionManager: permissionManager)
    if case .error(let error) = result {
      AppLogger.log("IPC error \(command): \(error.message)", level: .error)
    }
    let response = result.encodeToResponse()

    var headers = response.headers
    headers["Access-Control-Allow-Origin"] = "*"

    return VeloxRuntimeWry.CustomProtocol.Response(
      status: response.status,
      headers: headers,
      mimeType: headers["Content-Type"],
      body: response.body
    )
  }
}

private func errorResponse(code: String, message: String) -> VeloxRuntimeWry.CustomProtocol.Response {
  let error: [String: Any] = ["error": code, "message": message]
  let data = (try? JSONSerialization.data(withJSONObject: error)) ?? Data()
  return VeloxRuntimeWry.CustomProtocol.Response(
    status: 400,
    headers: [
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*"
    ],
    mimeType: "application/json",
    body: data
  )
}
