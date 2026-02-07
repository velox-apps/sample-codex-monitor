import Foundation
import VeloxRuntime
import VeloxRuntimeWry

private func unwrapCodexResponse(_ response: JSONValue) -> JSONValue {
  if let result = response["result"] {
    return result
  }
  return response
}

/// Matches the Rust `build_account_response` logic:
/// Extracts the account map from various response shapes, applies the
/// auth.json JWT fallback when the account is empty or type is chatgpt/unknown,
/// and wraps as `{"account": {...}, "requiresOpenaiAuth": bool}`.
private func buildAccountResponse(_ response: JSONValue?, fallback: AuthAccount? = nil) -> JSONValue {
  let unwrapped = response.map { unwrapCodexResponse($0) }

  // Try to find the account object from various locations.
  var account: [String: JSONValue] = [:]
  if let unwrapped {
    if let obj = unwrapped["account"]?.objectValue {
      account = obj
    } else if let resultObj = unwrapped["result"]?.objectValue, let obj = resultObj["account"]?.objectValue {
      account = obj
    } else if let root = unwrapped.objectValue {
      if root["email"] != nil || root["planType"] != nil || root["type"] != nil {
        account = root
      }
    }
  }

  // Apply fallback from auth.json JWT when allowed.
  if let fallback {
    let accountType = account["type"]?.stringValue?.lowercased()
    let allowFallback = account.isEmpty
      || accountType == nil || accountType == "chatgpt" || accountType == "unknown"
    if allowFallback {
      if account["email"] == nil, let email = fallback.email {
        account["email"] = .string(email)
      }
      if account["planType"] == nil, let plan = fallback.planType {
        account["planType"] = .string(plan)
      }
      if account["type"] == nil {
        account["type"] = .string("chatgpt")
      }
    }
  }

  // Extract requiresOpenaiAuth from various locations.
  let requiresAuth: Bool? = {
    guard let unwrapped else { return nil }
    return unwrapped["requiresOpenaiAuth"]?.boolValue
      ?? unwrapped["requires_openai_auth"]?.boolValue
      ?? unwrapped["result"]?["requiresOpenaiAuth"]?.boolValue
      ?? unwrapped["result"]?["requires_openai_auth"]?.boolValue
  }()

  var result: [String: JSONValue] = [:]
  result["account"] = account.isEmpty ? .null : .object(account)
  if let requiresAuth {
    result["requiresOpenaiAuth"] = .bool(requiresAuth)
  }
  return .object(result)
}

struct WorkspaceIdArgs: Codable, Sendable {
  let workspaceId: String
}

struct ThreadArgs: Codable, Sendable {
  let workspaceId: String
  let threadId: String
}

struct ListThreadsArgs: Codable, Sendable {
  let workspaceId: String
  let cursor: String?
  let limit: Int?
  let sortKey: String?
}

struct AddWorkspaceArgs: Codable, Sendable {
  let path: String
  let codex_bin: String?
}

struct AddWorktreeArgs: Codable, Sendable {
  let parentId: String
  let branch: String
}

struct IdArgs: Codable, Sendable {
  let id: String
}

struct UpdateWorkspaceSettingsArgs: Codable, Sendable {
  let id: String
  let settings: WorkspaceSettings
}

struct UpdateWorkspaceCodexBinArgs: Codable, Sendable {
  let id: String
  let codex_bin: String?
}

struct SendUserMessageArgs: Codable, Sendable {
  let workspaceId: String
  let threadId: String
  let text: String
  let model: String?
  let effort: String?
  let accessMode: String?
  let images: [String]?
  let collaborationMode: JSONValue?
}

struct TurnInterruptArgs: Codable, Sendable {
  let workspaceId: String
  let threadId: String
  let turnId: String
}

struct StartReviewArgs: Codable, Sendable {
  let workspaceId: String
  let threadId: String
  let target: JSONValue
  let delivery: String?
}

struct RespondToServerRequestArgs: Codable, Sendable {
  let workspaceId: String
  let requestId: UInt64
  let result: JSONValue
}

struct CodexDoctorArgs: Codable, Sendable {
  let codexBin: String?
  let codexArgs: String?
}

struct GitLogArgs: Codable, Sendable {
  let workspaceId: String
  let limit: Int?
}

struct GitBranchArgs: Codable, Sendable {
  let workspaceId: String
  let name: String
}

struct UpdateAppSettingsArgs: Codable, Sendable {
  let settings: AppSettings
}

struct GitFileArgs: Codable, Sendable {
  let workspaceId: String
  let path: String
}

struct CommitGitArgs: Codable, Sendable {
  let workspaceId: String
  let message: String
}

struct GitCommitDiffArgs: Codable, Sendable {
  let workspaceId: String
  let sha: String
}

struct GitRootsArgs: Codable, Sendable {
  let workspaceId: String
  let depth: Int
}

struct GitHubPrArgs: Codable, Sendable {
  let workspaceId: String
  let prNumber: Int
}

struct FileReadArgs: Codable, Sendable {
  let scope: FileScope
  let kind: FileKind
  let workspaceId: String?
}

struct FileWriteArgs: Codable, Sendable {
  let scope: FileScope
  let kind: FileKind
  let content: String
  let workspaceId: String?
}

struct ReadWorkspaceFileArgs: Codable, Sendable {
  let workspaceId: String
  let path: String
}

struct OpenWorkspaceInArgs: Codable, Sendable {
  let path: String
  let app: String?
  let command: String?
  let args: [String]
}

struct GetOpenAppIconArgs: Codable, Sendable {
  let appName: String
}

struct AddCloneArgs: Codable, Sendable {
  let sourceWorkspaceId: String
  let copiesFolder: String
  let copyName: String
}

struct RenameWorktreeArgs: Codable, Sendable {
  let id: String
  let branch: String
}

struct RenameWorktreeUpstreamArgs: Codable, Sendable {
  let id: String
  let oldBranch: String
  let newBranch: String
}

struct SetThreadNameArgs: Codable, Sendable {
  let workspaceId: String
  let threadId: String
  let name: String
}

struct McpServerStatusArgs: Codable, Sendable {
  let workspaceId: String
  let cursor: String?
  let limit: Int?
}

struct AppsListArgs: Codable, Sendable {
  let workspaceId: String
  let cursor: String?
  let limit: Int?
}

struct RememberApprovalRuleArgs: Codable, Sendable {
  let workspaceId: String
  let command: [String]
}

struct GenerateRunMetadataArgs: Codable, Sendable {
  let workspaceId: String
  let prompt: String
}

struct PromptsScopeArgs: Codable, Sendable {
  let workspaceId: String
  let scope: String
  let name: String
  let description: String?
  let argumentHint: String?
  let content: String
}

struct PromptsUpdateArgs: Codable, Sendable {
  let workspaceId: String
  let path: String
  let name: String
  let description: String?
  let argumentHint: String?
  let content: String
}

struct PromptsDeleteArgs: Codable, Sendable {
  let workspaceId: String
  let path: String
}

struct PromptsMoveArgs: Codable, Sendable {
  let workspaceId: String
  let path: String
  let scope: String
}

struct TerminalOpenArgs: Codable, Sendable {
  let workspaceId: String
  let terminalId: String
  let cols: Int
  let rows: Int
}

struct TerminalWriteArgs: Codable, Sendable {
  let workspaceId: String
  let terminalId: String
  let data: String
}

struct TerminalResizeArgs: Codable, Sendable {
  let workspaceId: String
  let terminalId: String
  let cols: Int
  let rows: Int
}

struct TerminalCloseArgs: Codable, Sendable {
  let workspaceId: String
  let terminalId: String
}

struct SendNotificationFallbackArgs: Codable, Sendable {
  let title: String
  let body: String
}

struct PathArgs: Codable, Sendable {
  let path: String
}

// (Full args merged into main arg structs above)

struct DictationModelIdArgs: Codable, Sendable {
  let modelId: String?
}

struct DictationModelStatusResponse: Codable, Sendable {
  let state: String
  let modelId: String
  let progress: JSONValue?
  let error: String?
  let path: String?
}

struct DictationStartArgs: Codable, Sendable {
  let preferredLanguage: String?
}

struct WebviewZoomArgs: Codable, Sendable {
  let label: String
  let value: Double
}

struct WindowSetEffectsArgs: Codable, Sendable {
  let label: String
  let value: JSONValue?
}

func registerCommands(
  registry: CommandRegistry,
  state: AppState,
  eventManager: VeloxEventManager,
  windowState: WindowState,
  appVersion: String?
) {
  registry.register("app_version", returning: String.self) { _ in
    appVersion ?? "0.0.0"
  }

  registry.register("window_start_dragging", returning: Bool.self) { _ in
    windowState.startDragging()
  }

  registry.register("get_app_settings", returning: AppSettings.self) { _ in
    state.getAppSettings()
  }

  registry.register("update_app_settings", args: UpdateAppSettingsArgs.self, returning: AppSettings.self) { args, _ in
    do {
      try Storage.writeSettings(args.settings, to: state.settingsPath)
      state.setAppSettings(args.settings)
      return args.settings
    } catch {
      throw CommandError(code: "Error", message: error.localizedDescription)
    }
  }

  registry.register("list_workspaces", returning: [WorkspaceInfo].self) { _ in
    listWorkspaces(state: state)
  }

  registry.register("add_workspace", args: AddWorkspaceArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        let info = try await addWorkspace(
          path: args.path,
          codexBin: args.codex_bin,
          state: state,
          eventManager: eventManager
        )
        deferred.responder.resolve(info)
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("add_worktree", args: AddWorktreeArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        let info = try await addWorktree(
          parentId: args.parentId,
          branch: args.branch,
          state: state,
          eventManager: eventManager
        )
        deferred.responder.resolve(info)
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("remove_workspace", args: IdArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        try await removeWorkspace(id: args.id, state: state)
        deferred.responder.resolve()
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("remove_worktree", args: IdArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        try await removeWorktree(id: args.id, state: state)
        deferred.responder.resolve()
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("update_workspace_settings", args: UpdateWorkspaceSettingsArgs.self, returning: WorkspaceInfo.self) { args, _ in
    do {
      return try updateWorkspaceSettings(id: args.id, settings: args.settings, state: state)
    } catch {
      throw CommandError(code: "Error", message: errorMessage(error))
    }
  }

  registry.register("update_workspace_codex_bin", args: UpdateWorkspaceCodexBinArgs.self, returning: WorkspaceInfo.self) { args, _ in
    do {
      return try updateWorkspaceCodexBin(id: args.id, codexBin: args.codex_bin, state: state)
    } catch {
      throw CommandError(code: "Error", message: errorMessage(error))
    }
  }

  registry.register("connect_workspace", args: IdArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        try await connectWorkspace(id: args.id, state: state, eventManager: eventManager)
        AppLogger.log("connect_workspace ok: \(args.id)", level: .info)
        deferred.responder.resolve()
      } catch {
        AppLogger.log("connect_workspace failed: \(args.id) \(error)", level: .error)
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("list_workspace_files", args: WorkspaceIdArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        let files = try listWorkspaceFiles(workspaceId: args.workspaceId, state: state)
        deferred.responder.resolve(files)
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("codex_doctor", args: CodexDoctorArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        let defaultBin = state.getAppSettings().codexBin
        let trimmed = args.codexBin?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = (trimmed?.isEmpty == false) ? trimmed : defaultBin
        let version = try await CodexManager.checkCodexInstallation(codexBin: resolved)
        var doctorArgs = ["app-server", "--help"]
        if let extra = args.codexArgs?.trimmingCharacters(in: .whitespacesAndNewlines), !extra.isEmpty {
          doctorArgs = extra.split(separator: " ").map(String.init) + doctorArgs
        }
        let process = try CodexManager.buildCodexProcess(codexBin: resolved, args: doctorArgs)
        let output = try await runProcess(process, timeout: 5)
        let appServerOk = output.status == 0
        let details = appServerOk ? nil : "Failed to run `codex app-server --help`."
        let result = CodexDoctorResult(
          ok: version != nil && appServerOk,
          codexBin: resolved,
          version: version,
          appServerOk: appServerOk,
          details: details
        )
        deferred.responder.resolve(result)
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("start_thread", args: WorkspaceIdArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        guard let session = state.getSession(id: args.workspaceId) else {
          throw CodexError(message: "workspace not connected")
        }
        let params = JSONValue.object([
          "cwd": .string(session.entry.path),
          "approvalPolicy": .string("on-request")
        ])
        let response = try await session.sendRequest(method: "thread/start", params: params)
        deferred.responder.resolve(unwrapCodexResponse(response))
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("resume_thread", args: ThreadArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        guard let session = state.getSession(id: args.workspaceId) else {
          throw CodexError(message: "workspace not connected")
        }
        let params = JSONValue.object([
          "threadId": .string(args.threadId)
        ])
        let response = try await session.sendRequest(method: "thread/resume", params: params)
        deferred.responder.resolve(unwrapCodexResponse(response))
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("list_threads", args: ListThreadsArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        guard let session = state.getSession(id: args.workspaceId) else {
          throw CodexError(message: "workspace not connected")
        }
        var listParams: [String: JSONValue] = [
          "cursor": args.cursor.map { .string($0) } ?? .null,
          "limit": args.limit.map { .number(Double($0)) } ?? .null
        ]
        if let sortKey = args.sortKey {
          listParams["sortKey"] = .string(sortKey)
        }
        let response = try await session.sendRequest(method: "thread/list", params: .object(listParams))
        deferred.responder.resolve(unwrapCodexResponse(response))
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("archive_thread", args: ThreadArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        guard let session = state.getSession(id: args.workspaceId) else {
          throw CodexError(message: "workspace not connected")
        }
        let params = JSONValue.object([
          "threadId": .string(args.threadId)
        ])
        let response = try await session.sendRequest(method: "thread/archive", params: params)
        deferred.responder.resolve(unwrapCodexResponse(response))
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("send_user_message", args: SendUserMessageArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        guard let session = state.getSession(id: args.workspaceId) else {
          throw CodexError(message: "workspace not connected")
        }
        let accessMode = args.accessMode ?? "current"
        let sandboxPolicy: JSONValue
        let approvalPolicy: String
        switch accessMode {
        case "full-access":
          sandboxPolicy = JSONValue.object([
            "type": .string("dangerFullAccess")
          ])
          approvalPolicy = "never"
        case "read-only":
          sandboxPolicy = JSONValue.object([
            "type": .string("readOnly")
          ])
          approvalPolicy = "on-request"
        default:
          sandboxPolicy = JSONValue.object([
            "type": .string("workspaceWrite"),
            "writableRoots": JSONValue.array([.string(session.entry.path)]),
            "networkAccess": .bool(true)
          ])
          approvalPolicy = "on-request"
        }

        // Build input array with text and optional images
        var inputItems: [JSONValue] = [
          JSONValue.object([
            "type": .string("text"),
            "text": .string(args.text)
          ])
        ]
        if let images = args.images {
          for imageData in images {
            inputItems.append(JSONValue.object([
              "type": .string("image"),
              "source": JSONValue.object([
                "type": .string("base64"),
                "media_type": .string("image/png"),
                "data": .string(imageData)
              ])
            ]))
          }
        }

        var msgParams: [String: JSONValue] = [
          "threadId": .string(args.threadId),
          "input": JSONValue.array(inputItems),
          "cwd": .string(session.entry.path),
          "approvalPolicy": .string(approvalPolicy),
          "sandboxPolicy": sandboxPolicy,
          "model": args.model.map { .string($0) } ?? .null,
          "effort": args.effort.map { .string($0) } ?? .null
        ]
        if let collab = args.collaborationMode {
          msgParams["collaborationMode"] = collab
        }
        let params = JSONValue.object(msgParams)
        let response = try await session.sendRequest(method: "turn/start", params: params)
        deferred.responder.resolve(unwrapCodexResponse(response))
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("turn_interrupt", args: TurnInterruptArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        guard let session = state.getSession(id: args.workspaceId) else {
          throw CodexError(message: "workspace not connected")
        }
        let params = JSONValue.object([
          "threadId": .string(args.threadId),
          "turnId": .string(args.turnId)
        ])
        let response = try await session.sendRequest(method: "turn/interrupt", params: params)
        deferred.responder.resolve(unwrapCodexResponse(response))
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("start_review", args: StartReviewArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        guard let session = state.getSession(id: args.workspaceId) else {
          throw CodexError(message: "workspace not connected")
        }
        var params: [String: JSONValue] = [
          "threadId": .string(args.threadId),
          "target": args.target
        ]
        if let delivery = args.delivery {
          params["delivery"] = .string(delivery)
        }
        let response = try await session.sendRequest(method: "review/start", params: JSONValue.object(params))
        deferred.responder.resolve(unwrapCodexResponse(response))
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("respond_to_server_request", args: RespondToServerRequestArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        guard let session = state.getSession(id: args.workspaceId) else {
          throw CodexError(message: "workspace not connected")
        }
        try await session.sendResponse(id: args.requestId, result: args.result)
        deferred.responder.resolve()
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("model_list", args: WorkspaceIdArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        guard let session = state.getSession(id: args.workspaceId) else {
          throw CodexError(message: "workspace not connected")
        }
        let response = try await session.sendRequest(method: "model/list", params: JSONValue.object([:]))
        deferred.responder.resolve(unwrapCodexResponse(response))
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("account_rate_limits", args: WorkspaceIdArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        guard let session = state.getSession(id: args.workspaceId) else {
          throw CodexError(message: "workspace not connected")
        }
        let response = try await session.sendRequest(method: "account/rateLimits/read", params: .null)
        deferred.responder.resolve(unwrapCodexResponse(response))
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("skills_list", args: WorkspaceIdArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        guard let session = state.getSession(id: args.workspaceId) else {
          throw CodexError(message: "workspace not connected")
        }
        let params = JSONValue.object([
          "cwd": .string(session.entry.path)
        ])
        let response = try await session.sendRequest(method: "skills/list", params: params)
        deferred.responder.resolve(unwrapCodexResponse(response))
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("get_git_status", args: WorkspaceIdArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        let status = try await getGitStatus(workspaceId: args.workspaceId, state: state)
        deferred.responder.resolve(status)
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("get_git_diffs", args: WorkspaceIdArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        let diffs = try await getGitDiffs(workspaceId: args.workspaceId, state: state)
        deferred.responder.resolve(diffs)
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("get_git_log", args: GitLogArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        let log = try await getGitLog(workspaceId: args.workspaceId, limit: args.limit, state: state)
        deferred.responder.resolve(log)
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("get_git_remote", args: WorkspaceIdArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        let remote = try await getGitRemote(workspaceId: args.workspaceId, state: state)
        deferred.responder.resolve(remote)
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("list_git_branches", args: WorkspaceIdArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        let branches = try await listGitBranches(workspaceId: args.workspaceId, state: state)
        deferred.responder.resolve(branches)
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("checkout_git_branch", args: GitBranchArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        try await checkoutGitBranch(workspaceId: args.workspaceId, name: args.name, state: state)
        deferred.responder.resolve()
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("create_git_branch", args: GitBranchArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        try await createGitBranch(workspaceId: args.workspaceId, name: args.name, state: state)
        deferred.responder.resolve()
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  // MARK: - Phase 1.1: Settings

  registry.register("get_codex_config_path", returning: String.self) { _ in
    getCodexConfigPath()
  }

  // MARK: - Phase 1.2: Files

  registry.register("file_read", args: FileReadArgs.self, returning: TextFileResponse.self) { args, _ in
    do {
      return try fileRead(scope: args.scope, kind: args.kind, workspaceId: args.workspaceId, state: state)
    } catch {
      throw CommandError(code: "Error", message: errorMessage(error))
    }
  }

  registry.register("file_write", args: FileWriteArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        try fileWrite(scope: args.scope, kind: args.kind, content: args.content, workspaceId: args.workspaceId, state: state)
        deferred.responder.resolve()
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  // MARK: - Phase 1.3: Workspace Commands

  registry.register("is_workspace_path_dir", args: PathArgs.self, returning: Bool.self) { args, _ in
    isWorkspacePathDir(path: args.path)
  }

  registry.register("read_workspace_file", args: ReadWorkspaceFileArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        let response = try readWorkspaceFile(workspaceId: args.workspaceId, path: args.path, state: state)
        deferred.responder.resolve(response)
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("open_workspace_in", args: OpenWorkspaceInArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        try openWorkspaceIn(path: args.path, app: args.app, command: args.command, args: args.args)
        deferred.responder.resolve()
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("get_open_app_icon", args: GetOpenAppIconArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      let icon = getOpenAppIcon(appName: args.appName)
      deferred.responder.resolve(icon)
    }
    return deferred.pending
  }

  registry.register("add_clone", args: AddCloneArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        let info = try await addClone(
          sourceWorkspaceId: args.sourceWorkspaceId,
          copiesFolder: args.copiesFolder,
          copyName: args.copyName,
          state: state,
          eventManager: eventManager
        )
        deferred.responder.resolve(info)
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("rename_worktree", args: RenameWorktreeArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        let info = try await renameWorktree(id: args.id, branch: args.branch, state: state)
        deferred.responder.resolve(info)
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("rename_worktree_upstream", args: RenameWorktreeUpstreamArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        try await renameWorktreeUpstream(id: args.id, oldBranch: args.oldBranch, newBranch: args.newBranch, state: state)
        deferred.responder.resolve()
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("apply_worktree_changes", args: WorkspaceIdArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        try await applyWorktreeChanges(workspaceId: args.workspaceId, state: state)
        deferred.responder.resolve()
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("worktree_setup_status", args: WorkspaceIdArgs.self, returning: WorktreeSetupStatus.self) { args, _ in
    do {
      return try worktreeSetupStatus(workspaceId: args.workspaceId, state: state)
    } catch {
      throw CommandError(code: "Error", message: errorMessage(error))
    }
  }

  registry.register("worktree_setup_mark_ran", args: WorkspaceIdArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        try worktreeSetupMarkRan(workspaceId: args.workspaceId, state: state)
        deferred.responder.resolve()
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  // MARK: - Phase 1.4: Git Commands

  registry.register("stage_git_file", args: GitFileArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        try await stageGitFile(workspaceId: args.workspaceId, path: args.path, state: state)
        deferred.responder.resolve()
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("stage_git_all", args: WorkspaceIdArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        try await stageGitAll(workspaceId: args.workspaceId, state: state)
        deferred.responder.resolve()
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("unstage_git_file", args: GitFileArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        try await unstageGitFile(workspaceId: args.workspaceId, path: args.path, state: state)
        deferred.responder.resolve()
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("revert_git_file", args: GitFileArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        try await revertGitFile(workspaceId: args.workspaceId, path: args.path, state: state)
        deferred.responder.resolve()
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("revert_git_all", args: WorkspaceIdArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        try await revertGitAll(workspaceId: args.workspaceId, state: state)
        deferred.responder.resolve()
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("commit_git", args: CommitGitArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        try await commitGit(workspaceId: args.workspaceId, message: args.message, state: state)
        deferred.responder.resolve()
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("push_git", args: WorkspaceIdArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        try await pushGit(workspaceId: args.workspaceId, state: state)
        deferred.responder.resolve()
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("pull_git", args: WorkspaceIdArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        try await pullGit(workspaceId: args.workspaceId, state: state)
        deferred.responder.resolve()
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("fetch_git", args: WorkspaceIdArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        try await fetchGit(workspaceId: args.workspaceId, state: state)
        deferred.responder.resolve()
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("sync_git", args: WorkspaceIdArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        try await syncGit(workspaceId: args.workspaceId, state: state)
        deferred.responder.resolve()
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("list_git_roots", args: GitRootsArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        let roots = try await listGitRoots(workspaceId: args.workspaceId, depth: args.depth, state: state)
        deferred.responder.resolve(roots)
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("get_git_commit_diff", args: GitCommitDiffArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        let diffs = try await getGitCommitDiff(workspaceId: args.workspaceId, sha: args.sha, state: state)
        deferred.responder.resolve(diffs)
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("get_github_issues", args: WorkspaceIdArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        let response = try await getGitHubIssues(workspaceId: args.workspaceId, state: state)
        deferred.responder.resolve(response)
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("get_github_pull_requests", args: WorkspaceIdArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        let response = try await getGitHubPullRequests(workspaceId: args.workspaceId, state: state)
        deferred.responder.resolve(response)
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("get_github_pull_request_diff", args: GitHubPrArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        let diffs = try await getGitHubPullRequestDiff(workspaceId: args.workspaceId, prNumber: args.prNumber, state: state)
        deferred.responder.resolve(diffs)
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("get_github_pull_request_comments", args: GitHubPrArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        let comments = try await getGitHubPullRequestComments(workspaceId: args.workspaceId, prNumber: args.prNumber, state: state)
        deferred.responder.resolve(comments)
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  // MARK: - Phase 1.5: Codex Commands

  registry.register("fork_thread", args: ThreadArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        guard let session = state.getSession(id: args.workspaceId) else {
          throw CodexError(message: "workspace not connected")
        }
        let params = JSONValue.object([
          "threadId": .string(args.threadId)
        ])
        let response = try await session.sendRequest(method: "thread/fork", params: params)
        deferred.responder.resolve(unwrapCodexResponse(response))
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("compact_thread", args: ThreadArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        guard let session = state.getSession(id: args.workspaceId) else {
          throw CodexError(message: "workspace not connected")
        }
        let params = JSONValue.object([
          "threadId": .string(args.threadId)
        ])
        let response = try await session.sendRequest(method: "thread/compact/start", params: params)
        deferred.responder.resolve(unwrapCodexResponse(response))
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("set_thread_name", args: SetThreadNameArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        guard let session = state.getSession(id: args.workspaceId) else {
          throw CodexError(message: "workspace not connected")
        }
        let params = JSONValue.object([
          "threadId": .string(args.threadId),
          "name": .string(args.name)
        ])
        let response = try await session.sendRequest(method: "thread/name/set", params: params)
        deferred.responder.resolve(unwrapCodexResponse(response))
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("list_mcp_server_status", args: McpServerStatusArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        guard let session = state.getSession(id: args.workspaceId) else {
          throw CodexError(message: "workspace not connected")
        }
        let params = JSONValue.object([
          "cursor": args.cursor.map { .string($0) } ?? .null,
          "limit": args.limit.map { .number(Double($0)) } ?? .null
        ])
        let response = try await session.sendRequest(method: "mcpServerStatus/list", params: params)
        deferred.responder.resolve(unwrapCodexResponse(response))
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("collaboration_mode_list", args: WorkspaceIdArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        guard let session = state.getSession(id: args.workspaceId) else {
          throw CodexError(message: "workspace not connected")
        }
        let response = try await session.sendRequest(method: "collaborationMode/list", params: JSONValue.object([:]))
        deferred.responder.resolve(unwrapCodexResponse(response))
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("account_read", args: WorkspaceIdArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      // Try to get account from app-server (tolerate failure).
      let session = state.getSession(id: args.workspaceId)
      let response: JSONValue? = try? await session?.sendRequest(method: "account/read", params: .null)

      // Read auth.json JWT as fallback.
      let entry = state.getWorkspace(id: args.workspaceId)
      let codexHome: String? = {
        guard let entry else { return resolveDefaultCodexHome() }
        let parent = entry.parentId.flatMap { state.getWorkspace(id: $0) }
        return resolveWorkspaceCodexHome(entry: entry, parent: parent, state: state)
      }()
      let fallback = readAuthAccount(codexHome: codexHome)

      deferred.responder.resolve(buildAccountResponse(response, fallback: fallback))
    }
    return deferred.pending
  }

  registry.register("apps_list", args: AppsListArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        guard let session = state.getSession(id: args.workspaceId) else {
          throw CodexError(message: "workspace not connected")
        }
        let params = JSONValue.object([
          "cursor": args.cursor.map { .string($0) } ?? .null,
          "limit": args.limit.map { .number(Double($0)) } ?? .null
        ])
        let response = try await session.sendRequest(method: "app/list", params: params)
        deferred.responder.resolve(unwrapCodexResponse(response))
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("remember_approval_rule", args: RememberApprovalRuleArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        let filtered = args.command.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !filtered.isEmpty else {
          throw CodexError(message: "empty command")
        }
        guard let entry = state.getWorkspace(id: args.workspaceId) else {
          throw CodexError(message: "workspace not found")
        }
        let parent = entry.parentId.flatMap { state.getWorkspace(id: $0) }
        let codexHome = resolveWorkspaceCodexHome(entry: entry, parent: parent, state: state)
        let rulesPath = (codexHome as NSString).appendingPathComponent("rules")
        try FileManager.default.createDirectory(atPath: rulesPath, withIntermediateDirectories: true)
        let rulesFile = (rulesPath as NSString).appendingPathComponent("approval-rules.txt")
        let line = filtered.joined(separator: " ") + "\n"
        if FileManager.default.fileExists(atPath: rulesFile) {
          let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: rulesFile))
          try handle.seekToEnd()
          try handle.write(contentsOf: line.data(using: .utf8)!)
          try handle.close()
        } else {
          try line.write(toFile: rulesFile, atomically: true, encoding: .utf8)
        }
        let result: [String: Any] = ["ok": true, "rulesPath": rulesFile]
        let data = try JSONSerialization.data(withJSONObject: result)
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        deferred.responder.resolve(json)
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("get_config_model", args: WorkspaceIdArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        guard let entry = state.getWorkspace(id: args.workspaceId) else {
          throw CodexError(message: "workspace not found")
        }
        let parent = entry.parentId.flatMap { state.getWorkspace(id: $0) }
        let codexHome = resolveWorkspaceCodexHome(entry: entry, parent: parent, state: state)
        let configPath = (codexHome as NSString).appendingPathComponent("config.toml")
        var model: String? = nil
        if FileManager.default.fileExists(atPath: configPath),
           let content = try? String(contentsOfFile: configPath, encoding: .utf8) {
          for line in content.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("model") && trimmed.contains("=") {
              let value = trimmed.split(separator: "=", maxSplits: 1).last?
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) ?? ""
              if !value.isEmpty {
                model = value
              }
            }
          }
        }
        let result = JSONValue.object(["model": model.map { .string($0) } ?? .null])
        deferred.responder.resolve(result)
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("get_commit_message_prompt", args: WorkspaceIdArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        guard state.getWorkspace(id: args.workspaceId) != nil else {
          throw CodexError(message: "workspace not found")
        }
        let prompt = "Generate a concise conventional commit message for the following git diff. Return ONLY the commit message, no explanation."
        deferred.responder.resolve(JSONValue.string(prompt))
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("generate_commit_message", args: WorkspaceIdArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        guard let session = state.getSession(id: args.workspaceId) else {
          throw CodexError(message: "workspace not connected")
        }
        // Get the diff
        let diffs = try await getGitDiffs(workspaceId: args.workspaceId, state: state)
        let diffText = diffs.map { $0.diff }.joined(separator: "\n\n")
        guard !diffText.isEmpty else {
          throw CodexError(message: "No changes to commit")
        }

        let prompt = """
        Generate a concise conventional commit message for the following diff. \
        Return ONLY the commit message text, nothing else.

        \(String(diffText.prefix(8000)))
        """

        // Start a temp thread
        let startParams = JSONValue.object([
          "cwd": .string(session.entry.path),
          "approvalPolicy": .string("never"),
          "hidden": .bool(true)
        ])
        let threadResponse = try await withTimeout(seconds: 60) {
          try await session.sendRequest(method: "thread/start", params: startParams)
        }
        let threadResult = unwrapCodexResponse(threadResponse)
        guard let threadId = threadResult["threadId"]?.stringValue ?? threadResult["thread_id"]?.stringValue else {
          throw CodexError(message: "failed to start temp thread for commit message")
        }

        // Send the prompt
        let turnParams = JSONValue.object([
          "threadId": .string(threadId),
          "input": JSONValue.array([
            JSONValue.object([
              "type": .string("text"),
              "text": .string(prompt)
            ])
          ]),
          "cwd": .string(session.entry.path),
          "approvalPolicy": .string("never"),
          "sandboxPolicy": JSONValue.object(["type": .string("readOnly")])
        ])
        let turnResponse = try await withTimeout(seconds: 60) {
          try await session.sendRequest(method: "turn/start", params: turnParams)
        }
        let turnResult = unwrapCodexResponse(turnResponse)

        // Extract the message from the response
        var commitMessage = ""
        if let text = turnResult["text"]?.stringValue {
          commitMessage = text
        } else if let items = turnResult["items"]?.arrayValue {
          for item in items {
            if let text = item["text"]?.stringValue {
              commitMessage += text
            }
          }
        }

        // Archive the temp thread
        let archiveParams = JSONValue.object(["threadId": .string(threadId)])
        _ = try? await session.sendRequest(method: "thread/archive", params: archiveParams)

        let trimmedMessage = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        deferred.responder.resolve(JSONValue.string(trimmedMessage.isEmpty ? "update" : trimmedMessage))
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("generate_run_metadata", args: GenerateRunMetadataArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        guard let session = state.getSession(id: args.workspaceId) else {
          throw CodexError(message: "workspace not connected")
        }
        let prompt = """
        Given this task description, generate a short title (max 50 chars) and a kebab-case \
        worktree name (max 30 chars) suitable for a git branch. Return JSON: {"title":"...","worktreeName":"..."}

        Task: \(args.prompt)
        """

        let startParams = JSONValue.object([
          "cwd": .string(session.entry.path),
          "approvalPolicy": .string("never"),
          "hidden": .bool(true)
        ])
        let threadResponse = try await withTimeout(seconds: 60) {
          try await session.sendRequest(method: "thread/start", params: startParams)
        }
        let threadResult = unwrapCodexResponse(threadResponse)
        guard let threadId = threadResult["threadId"]?.stringValue ?? threadResult["thread_id"]?.stringValue else {
          throw CodexError(message: "failed to start temp thread")
        }

        let turnParams = JSONValue.object([
          "threadId": .string(threadId),
          "input": JSONValue.array([
            JSONValue.object(["type": .string("text"), "text": .string(prompt)])
          ]),
          "cwd": .string(session.entry.path),
          "approvalPolicy": .string("never"),
          "sandboxPolicy": JSONValue.object(["type": .string("readOnly")])
        ])
        let turnResponse = try await withTimeout(seconds: 60) {
          try await session.sendRequest(method: "turn/start", params: turnParams)
        }
        let turnResult = unwrapCodexResponse(turnResponse)

        var responseText = ""
        if let text = turnResult["text"]?.stringValue {
          responseText = text
        } else if let items = turnResult["items"]?.arrayValue {
          for item in items {
            if let text = item["text"]?.stringValue { responseText += text }
          }
        }

        // Archive temp thread
        let archiveParams = JSONValue.object(["threadId": .string(threadId)])
        _ = try? await session.sendRequest(method: "thread/archive", params: archiveParams)

        // Parse JSON from response
        var title = "New Agent"
        var worktreeName = "agent"
        if let jsonStart = responseText.firstIndex(of: "{"),
           let jsonEnd = responseText.lastIndex(of: "}"),
           let jsonData = String(responseText[jsonStart...jsonEnd]).data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
          if let t = parsed["title"] as? String { title = t }
          if let w = parsed["worktreeName"] as? String { worktreeName = w }
        }

        let result = JSONValue.object([
          "title": .string(title),
          "worktreeName": .string(worktreeName)
        ])
        deferred.responder.resolve(result)
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("codex_login", args: WorkspaceIdArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        guard let session = state.getSession(id: args.workspaceId) else {
          throw CodexError(message: "workspace not connected")
        }
        // Cancel any existing login
        if let existing = state.removeLoginCancel(workspaceId: args.workspaceId) {
          if case .pendingStart(let cancel) = existing {
            cancel()
          }
        }

        let response = try await withTimeout(seconds: 30) {
          try await session.sendRequest(method: "account/login/start", params: JSONValue.object(["type": .string("chatgpt")]))
        }
        let payload = unwrapCodexResponse(response)
        guard let loginId = payload["loginId"]?.stringValue ?? payload["login_id"]?.stringValue else {
          throw CodexError(message: "missing loginId in login response")
        }
        guard let authUrl = payload["authUrl"]?.stringValue ?? payload["auth_url"]?.stringValue else {
          throw CodexError(message: "missing authUrl in login response")
        }
        state.setLoginCancel(workspaceId: args.workspaceId, state: .loginId(loginId))

        let result = JSONValue.object([
          "loginId": .string(loginId),
          "authUrl": .string(authUrl),
          "raw": response
        ])
        deferred.responder.resolve(result)
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("codex_login_cancel", args: WorkspaceIdArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        guard let cancelState = state.removeLoginCancel(workspaceId: args.workspaceId) else {
          deferred.responder.resolve(JSONValue.object(["canceled": .bool(false)]))
          return
        }
        switch cancelState {
        case .pendingStart(let cancel):
          cancel()
          deferred.responder.resolve(JSONValue.object([
            "canceled": .bool(true),
            "status": .string("canceled")
          ]))
        case .loginId(let loginId):
          guard let session = state.getSession(id: args.workspaceId) else {
            deferred.responder.resolve(JSONValue.object(["canceled": .bool(true)]))
            return
          }
          let response = try await session.sendRequest(
            method: "account/login/cancel",
            params: JSONValue.object(["loginId": .string(loginId)])
          )
          let payload = unwrapCodexResponse(response)
          let status = payload["status"]?.stringValue ?? ""
          let canceled = status.lowercased() == "canceled"
          deferred.responder.resolve(JSONValue.object([
            "canceled": .bool(canceled),
            "status": .string(status),
            "raw": response
          ]))
        }
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  // MARK: - Phase 1.6: Prompts

  registry.register("prompts_list", args: WorkspaceIdArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        let prompts = try promptsList(workspaceId: args.workspaceId, state: state)
        deferred.responder.resolve(prompts)
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("prompts_create", args: PromptsScopeArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        let prompt = try promptsCreate(
          workspaceId: args.workspaceId,
          scope: args.scope,
          name: args.name,
          description: args.description,
          argumentHint: args.argumentHint,
          content: args.content,
          state: state
        )
        deferred.responder.resolve(prompt)
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("prompts_update", args: PromptsUpdateArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        let prompt = try promptsUpdate(
          workspaceId: args.workspaceId,
          path: args.path,
          name: args.name,
          description: args.description,
          argumentHint: args.argumentHint,
          content: args.content,
          state: state
        )
        deferred.responder.resolve(prompt)
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("prompts_delete", args: PromptsDeleteArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        try promptsDelete(workspaceId: args.workspaceId, path: args.path, state: state)
        deferred.responder.resolve()
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("prompts_move", args: PromptsMoveArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        let prompt = try promptsMove(workspaceId: args.workspaceId, path: args.path, scope: args.scope, state: state)
        deferred.responder.resolve(prompt)
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("prompts_workspace_dir", args: WorkspaceIdArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        let dir = try promptsWorkspaceDir(workspaceId: args.workspaceId, state: state)
        deferred.responder.resolve(JSONValue.string(dir))
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("prompts_global_dir", args: WorkspaceIdArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        let dir = try promptsGlobalDir(workspaceId: args.workspaceId, state: state)
        deferred.responder.resolve(JSONValue.string(dir))
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  // MARK: - Phase 2.1: Terminal

  registry.register("terminal_open", args: TerminalOpenArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        let result = try terminalOpen(
          workspaceId: args.workspaceId,
          terminalId: args.terminalId,
          cols: args.cols,
          rows: args.rows,
          state: state,
          eventManager: eventManager
        )
        let data = try JSONSerialization.data(withJSONObject: result)
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        deferred.responder.resolve(json)
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("terminal_write", args: TerminalWriteArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        try terminalWrite(workspaceId: args.workspaceId, terminalId: args.terminalId, data: args.data, state: state)
        deferred.responder.resolve()
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("terminal_resize", args: TerminalResizeArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        try terminalResize(workspaceId: args.workspaceId, terminalId: args.terminalId, cols: args.cols, rows: args.rows, state: state)
        deferred.responder.resolve()
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("terminal_close", args: TerminalCloseArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      terminalClose(workspaceId: args.workspaceId, terminalId: args.terminalId, state: state)
      deferred.responder.resolve()
    }
    return deferred.pending
  }

  // MARK: - Phase 2.2: Menu & Notifications

  registry.register("menu_set_accelerators", args: MenuSetAcceleratorsArgs.self, returning: Bool.self) { args, _ in
    menuSetAccelerators(updates: args.updates)
    return true
  }

  registry.register("is_macos_debug_build", returning: Bool.self) { _ in
    isMacosDebugBuild()
  }

  registry.register("send_notification_fallback", args: SendNotificationFallbackArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        try sendNotificationFallback(title: args.title, body: args.body)
        deferred.responder.resolve()
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  // MARK: - Phase 3.1: Local Usage

  registry.register("local_usage_snapshot", args: LocalUsageSnapshotArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        let snapshot = try localUsageSnapshot(days: args.days, workspacePath: args.workspacePath, state: state)
        deferred.responder.resolve(snapshot)
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  // MARK: - Dictation

  registry.register("dictation_model_status", args: DictationModelIdArgs.self, returning: DictationModelStatusResponse.self) { args, _ in
    dictationModelStatus(modelId: args.modelId, state: state)
  }

  registry.register("dictation_download_model", args: DictationModelIdArgs.self, returning: DictationModelStatusResponse.self) { args, _ in
    dictationDownloadModel(modelId: args.modelId, state: state, eventManager: eventManager)
  }

  registry.register("dictation_cancel_download", args: DictationModelIdArgs.self, returning: DictationModelStatusResponse.self) { args, _ in
    dictationCancelDownload(modelId: args.modelId, state: state, eventManager: eventManager)
  }

  registry.register("dictation_remove_model", args: DictationModelIdArgs.self, returning: DictationModelStatusResponse.self) { args, _ in
    dictationRemoveModel(modelId: args.modelId, state: state, eventManager: eventManager)
  }

  registry.register("dictation_start", args: DictationStartArgs.self, returning: DeferredCommandResponse.self) { args, context in
    let deferred = try context.deferResponse()
    Task {
      do {
        try dictationStart(preferredLanguage: args.preferredLanguage, state: state, eventManager: eventManager)
        deferred.responder.resolve("listening")
      } catch {
        deferred.responder.reject(code: "Error", message: errorMessage(error))
      }
    }
    return deferred.pending
  }

  registry.register("dictation_stop", returning: String.self) { _ in
    dictationStop(state: state, eventManager: eventManager)
    return "processing"
  }

  registry.register("dictation_cancel", returning: String.self) { _ in
    dictationCancel(state: state, eventManager: eventManager)
    return "idle"
  }

  registry.register("dictation_request_permission", returning: DeferredCommandResponse.self) { context in
    let deferred = try context.deferResponse()
    Task {
      let granted = await dictationRequestPermission()
      deferred.responder.resolve(granted)
    }
    return deferred.pending
  }

  // MARK: - Stubs: Tauri Plugin Compat

  registry.register("plugin:webview|set_webview_zoom", args: WebviewZoomArgs.self, returning: Bool.self) { _, _ in
    true
  }

  registry.register("plugin:liquid-glass|is_glass_supported", returning: Bool.self) { _ in
    false
  }

  registry.register("plugin:window|set_effects", args: WindowSetEffectsArgs.self, returning: Bool.self) { _, _ in
    true
  }
}

private func errorMessage(_ error: Error) -> String {
  if let codexError = error as? CodexError {
    return codexError.message
  }
  return error.localizedDescription
}
