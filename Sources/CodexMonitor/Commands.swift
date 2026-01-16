import Foundation
import VeloxRuntime
import VeloxRuntimeWry

private func unwrapCodexResponse(_ response: JSONValue) -> JSONValue {
  if let result = response["result"] {
    return result
  }
  return response
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
        let process = try CodexManager.buildCodexProcess(codexBin: resolved, args: ["app-server", "--help"])
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
        let params = JSONValue.object([
          "cursor": args.cursor.map { .string($0) } ?? .null,
          "limit": args.limit.map { .number(Double($0)) } ?? .null
        ])
        let response = try await session.sendRequest(method: "thread/list", params: params)
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

        let params = JSONValue.object([
          "threadId": .string(args.threadId),
          "input": JSONValue.array([
            JSONValue.object([
              "type": .string("text"),
              "text": .string(args.text)
            ])
          ]),
          "cwd": .string(session.entry.path),
          "approvalPolicy": .string(approvalPolicy),
          "sandboxPolicy": sandboxPolicy,
          "model": args.model.map { .string($0) } ?? .null,
          "effort": args.effort.map { .string($0) } ?? .null
        ])
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
}

private func errorMessage(_ error: Error) -> String {
  if let codexError = error as? CodexError {
    return codexError.message
  }
  return error.localizedDescription
}
