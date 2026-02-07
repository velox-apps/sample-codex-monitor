import Foundation

// MARK: - Git Types

struct GitFileStatus: Codable, Sendable {
  let path: String
  let status: String
  let additions: Int
  let deletions: Int
}

struct GitFileDiff: Codable, Sendable {
  let path: String
  let diff: String
  var oldLines: [String]?
  var newLines: [String]?
  var isBinary: Bool
  var isImage: Bool
  var oldImageData: String?
  var newImageData: String?
  var oldImageMime: String?
  var newImageMime: String?

  init(
    path: String,
    diff: String,
    oldLines: [String]? = nil,
    newLines: [String]? = nil,
    isBinary: Bool = false,
    isImage: Bool = false,
    oldImageData: String? = nil,
    newImageData: String? = nil,
    oldImageMime: String? = nil,
    newImageMime: String? = nil
  ) {
    self.path = path
    self.diff = diff
    self.oldLines = oldLines
    self.newLines = newLines
    self.isBinary = isBinary
    self.isImage = isImage
    self.oldImageData = oldImageData
    self.newImageData = newImageData
    self.oldImageMime = oldImageMime
    self.newImageMime = newImageMime
  }
}

struct GitCommitDiff: Codable, Sendable {
  let path: String
  let status: String
  let diff: String
  var oldLines: [String]?
  var newLines: [String]?
  var isBinary: Bool
  var isImage: Bool
  var oldImageData: String?
  var newImageData: String?
  var oldImageMime: String?
  var newImageMime: String?

  init(
    path: String,
    status: String,
    diff: String,
    oldLines: [String]? = nil,
    newLines: [String]? = nil,
    isBinary: Bool = false,
    isImage: Bool = false,
    oldImageData: String? = nil,
    newImageData: String? = nil,
    oldImageMime: String? = nil,
    newImageMime: String? = nil
  ) {
    self.path = path
    self.status = status
    self.diff = diff
    self.oldLines = oldLines
    self.newLines = newLines
    self.isBinary = isBinary
    self.isImage = isImage
    self.oldImageData = oldImageData
    self.newImageData = newImageData
    self.oldImageMime = oldImageMime
    self.newImageMime = newImageMime
  }
}

struct GitLogEntry: Codable, Sendable {
  let sha: String
  let summary: String
  let author: String
  let timestamp: Int64
}

struct GitLogResponse: Codable, Sendable {
  let total: Int
  let entries: [GitLogEntry]
  var ahead: Int
  var behind: Int
  var aheadEntries: [GitLogEntry]
  var behindEntries: [GitLogEntry]
  var upstream: String?

  init(
    total: Int,
    entries: [GitLogEntry],
    ahead: Int = 0,
    behind: Int = 0,
    aheadEntries: [GitLogEntry] = [],
    behindEntries: [GitLogEntry] = [],
    upstream: String? = nil
  ) {
    self.total = total
    self.entries = entries
    self.ahead = ahead
    self.behind = behind
    self.aheadEntries = aheadEntries
    self.behindEntries = behindEntries
    self.upstream = upstream
  }
}

struct BranchInfo: Codable, Sendable {
  let name: String
  let last_commit: Int64
}

// MARK: - GitHub Types

struct GitHubIssue: Codable, Sendable {
  let number: UInt64
  let title: String
  let url: String
  let updatedAt: String
}

struct GitHubIssuesResponse: Codable, Sendable {
  let total: Int
  let issues: [GitHubIssue]
}

struct GitHubPullRequestAuthor: Codable, Sendable {
  let login: String
}

struct GitHubPullRequest: Codable, Sendable {
  let number: UInt64
  let title: String
  let url: String
  let updatedAt: String
  let createdAt: String
  let body: String
  let headRefName: String
  let baseRefName: String
  let isDraft: Bool
  let author: GitHubPullRequestAuthor?
}

struct GitHubPullRequestsResponse: Codable, Sendable {
  let total: Int
  let pullRequests: [GitHubPullRequest]
}

struct GitHubPullRequestDiff: Codable, Sendable {
  let path: String
  let status: String
  let diff: String
}

struct GitHubPullRequestComment: Codable, Sendable {
  let id: UInt64
  let body: String
  let createdAt: String
  let url: String
  let author: GitHubPullRequestAuthor?

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UInt64.self, forKey: .id)
    body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
    createdAt = try container.decode(String.self, forKey: .createdAt)
    url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
    author = try container.decodeIfPresent(GitHubPullRequestAuthor.self, forKey: .author)
  }
}

// MARK: - Local Usage Types

struct LocalUsageDay: Codable, Sendable {
  let day: String
  let inputTokens: Int64
  let cachedInputTokens: Int64
  let outputTokens: Int64
  let totalTokens: Int64
  var agentTimeMs: Int64
  var agentRuns: Int64

  init(
    day: String,
    inputTokens: Int64,
    cachedInputTokens: Int64,
    outputTokens: Int64,
    totalTokens: Int64,
    agentTimeMs: Int64 = 0,
    agentRuns: Int64 = 0
  ) {
    self.day = day
    self.inputTokens = inputTokens
    self.cachedInputTokens = cachedInputTokens
    self.outputTokens = outputTokens
    self.totalTokens = totalTokens
    self.agentTimeMs = agentTimeMs
    self.agentRuns = agentRuns
  }
}

struct LocalUsageTotals: Codable, Sendable {
  let last7DaysTokens: Int64
  let last30DaysTokens: Int64
  let averageDailyTokens: Int64
  let cacheHitRatePercent: Double
  let peakDay: String?
  let peakDayTokens: Int64
}

struct LocalUsageModel: Codable, Sendable {
  let model: String
  let tokens: Int64
  let sharePercent: Double
}

struct LocalUsageSnapshot: Codable, Sendable {
  let updatedAt: Int64
  let days: [LocalUsageDay]
  let totals: LocalUsageTotals
  var topModels: [LocalUsageModel]

  init(
    updatedAt: Int64,
    days: [LocalUsageDay],
    totals: LocalUsageTotals,
    topModels: [LocalUsageModel] = []
  ) {
    self.updatedAt = updatedAt
    self.days = days
    self.totals = totals
    self.topModels = topModels
  }
}

// MARK: - Workspace Types

struct WorkspaceEntry: Codable, Sendable {
  let id: String
  let name: String
  let path: String
  var codex_bin: String?
  var kind: WorkspaceKind
  var parentId: String?
  var worktree: WorktreeInfo?
  var settings: WorkspaceSettings

  init(
    id: String,
    name: String,
    path: String,
    codex_bin: String?,
    kind: WorkspaceKind = .main,
    parentId: String? = nil,
    worktree: WorktreeInfo? = nil,
    settings: WorkspaceSettings = WorkspaceSettings()
  ) {
    self.id = id
    self.name = name
    self.path = path
    self.codex_bin = codex_bin
    self.kind = kind
    self.parentId = parentId
    self.worktree = worktree
    self.settings = settings
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    path = try container.decode(String.self, forKey: .path)
    codex_bin = try container.decodeIfPresent(String.self, forKey: .codex_bin)
    kind = try container.decodeIfPresent(WorkspaceKind.self, forKey: .kind) ?? .main
    parentId = try container.decodeIfPresent(String.self, forKey: .parentId)
    worktree = try container.decodeIfPresent(WorktreeInfo.self, forKey: .worktree)
    settings = try container.decodeIfPresent(WorkspaceSettings.self, forKey: .settings) ?? WorkspaceSettings()
  }
}

struct WorkspaceInfo: Codable, Sendable {
  let id: String
  let name: String
  let path: String
  let connected: Bool
  let codex_bin: String?
  let kind: WorkspaceKind
  let parentId: String?
  let worktree: WorktreeInfo?
  let settings: WorkspaceSettings
}

enum WorkspaceKind: String, Codable, Sendable {
  case main
  case worktree

  func isWorktree() -> Bool {
    self == .worktree
  }
}

struct WorktreeInfo: Codable, Sendable {
  let branch: String
}

struct WorkspaceGroup: Codable, Sendable {
  let id: String
  let name: String
  var sortOrder: Int?
  var copiesFolder: String?

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder)
    copiesFolder = try container.decodeIfPresent(String.self, forKey: .copiesFolder)
  }
}

struct WorkspaceSettings: Codable, Sendable {
  var sidebarCollapsed: Bool
  var sortOrder: Int?
  var groupId: String?
  var gitRoot: String?
  var codexHome: String?
  var codexArgs: String?
  var launchScript: String?
  var launchScripts: [LaunchScriptEntry]?
  var worktreeSetupScript: String?

  init(
    sidebarCollapsed: Bool = false,
    sortOrder: Int? = nil,
    groupId: String? = nil,
    gitRoot: String? = nil,
    codexHome: String? = nil,
    codexArgs: String? = nil,
    launchScript: String? = nil,
    launchScripts: [LaunchScriptEntry]? = nil,
    worktreeSetupScript: String? = nil
  ) {
    self.sidebarCollapsed = sidebarCollapsed
    self.sortOrder = sortOrder
    self.groupId = groupId
    self.gitRoot = gitRoot
    self.codexHome = codexHome
    self.codexArgs = codexArgs
    self.launchScript = launchScript
    self.launchScripts = launchScripts
    self.worktreeSetupScript = worktreeSetupScript
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    sidebarCollapsed = try container.decodeIfPresent(Bool.self, forKey: .sidebarCollapsed) ?? false
    sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder)
    groupId = try container.decodeIfPresent(String.self, forKey: .groupId)
    gitRoot = try container.decodeIfPresent(String.self, forKey: .gitRoot)
    codexHome = try container.decodeIfPresent(String.self, forKey: .codexHome)
    codexArgs = try container.decodeIfPresent(String.self, forKey: .codexArgs)
    launchScript = try container.decodeIfPresent(String.self, forKey: .launchScript)
    launchScripts = try container.decodeIfPresent([LaunchScriptEntry].self, forKey: .launchScripts)
    worktreeSetupScript = try container.decodeIfPresent(String.self, forKey: .worktreeSetupScript)
  }
}

struct LaunchScriptEntry: Codable, Sendable {
  let id: String
  let script: String
  let icon: String
  var label: String?

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    script = try container.decode(String.self, forKey: .script)
    icon = try container.decode(String.self, forKey: .icon)
    label = try container.decodeIfPresent(String.self, forKey: .label)
  }
}

struct WorktreeSetupStatus: Codable, Sendable {
  let shouldRun: Bool
  let script: String?
}

struct OpenAppTarget: Codable, Sendable {
  let id: String
  let label: String
  let kind: String
  var appName: String?
  var command: String?
  var args: [String]

  init(
    id: String,
    label: String,
    kind: String,
    appName: String? = nil,
    command: String? = nil,
    args: [String] = []
  ) {
    self.id = id
    self.label = label
    self.kind = kind
    self.appName = appName
    self.command = command
    self.args = args
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    label = try container.decode(String.self, forKey: .label)
    kind = try container.decode(String.self, forKey: .kind)
    appName = try container.decodeIfPresent(String.self, forKey: .appName)
    command = try container.decodeIfPresent(String.self, forKey: .command)
    args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
  }
}

// MARK: - Backend Mode

enum BackendMode: String, Codable, Sendable {
  case local
  case remote
}

// MARK: - App Settings

struct AppSettings: Codable, Sendable {
  var codexBin: String?
  var codexArgs: String?
  var backendMode: BackendMode
  var remoteBackendHost: String
  var remoteBackendToken: String?
  var defaultAccessMode: String
  var reviewDeliveryMode: String
  // Shortcuts
  var composerModelShortcut: String?
  var composerAccessShortcut: String?
  var composerReasoningShortcut: String?
  var interruptShortcut: String?
  var composerCollaborationShortcut: String?
  var newAgentShortcut: String?
  var newWorktreeAgentShortcut: String?
  var newCloneAgentShortcut: String?
  var archiveThreadShortcut: String?
  var toggleProjectsSidebarShortcut: String?
  var toggleGitSidebarShortcut: String?
  var toggleDebugPanelShortcut: String?
  var toggleTerminalShortcut: String?
  var cycleAgentNextShortcut: String?
  var cycleAgentPrevShortcut: String?
  var cycleWorkspaceNextShortcut: String?
  var cycleWorkspacePrevShortcut: String?
  // Composer state
  var lastComposerModelId: String?
  var lastComposerReasoningEffort: String?
  // UI
  var uiScale: Double
  var theme: String
  var usageShowRemaining: Bool
  var uiFontFamily: String
  var codeFontFamily: String
  var codeFontSize: UInt8
  var notificationSoundsEnabled: Bool
  var preloadGitDiffs: Bool
  var gitDiffIgnoreWhitespaceChanges: Bool
  var systemNotificationsEnabled: Bool
  // Feature flags
  var experimentalCollabEnabled: Bool
  var collaborationModesEnabled: Bool
  var steerEnabled: Bool
  var unifiedExecEnabled: Bool
  var experimentalAppsEnabled: Bool
  var personality: String
  // Dictation
  var dictationEnabled: Bool
  var dictationModelId: String
  var dictationPreferredLanguage: String?
  var dictationHoldKey: String
  // Composer editor
  var composerEditorPreset: String
  var composerFenceExpandOnSpace: Bool
  var composerFenceExpandOnEnter: Bool
  var composerFenceLanguageTags: Bool
  var composerFenceWrapSelection: Bool
  var composerFenceAutoWrapPasteMultiline: Bool
  var composerFenceAutoWrapPasteCodeLike: Bool
  var composerListContinuation: Bool
  var composerCodeBlockCopyUseModifier: Bool
  // Groups and open-in targets
  var workspaceGroups: [WorkspaceGroup]
  var openAppTargets: [OpenAppTarget]
  var selectedOpenAppId: String

  init(
    codexBin: String? = nil,
    codexArgs: String? = nil,
    backendMode: BackendMode = .local,
    remoteBackendHost: String = "127.0.0.1:4732",
    remoteBackendToken: String? = nil,
    defaultAccessMode: String = "current",
    reviewDeliveryMode: String = "inline",
    composerModelShortcut: String? = "cmd+shift+m",
    composerAccessShortcut: String? = "cmd+shift+a",
    composerReasoningShortcut: String? = "cmd+shift+r",
    interruptShortcut: String? = "ctrl+c",
    composerCollaborationShortcut: String? = "shift+tab",
    newAgentShortcut: String? = "cmd+n",
    newWorktreeAgentShortcut: String? = "cmd+shift+n",
    newCloneAgentShortcut: String? = "cmd+alt+n",
    archiveThreadShortcut: String? = "cmd+ctrl+a",
    toggleProjectsSidebarShortcut: String? = "cmd+shift+p",
    toggleGitSidebarShortcut: String? = "cmd+shift+g",
    toggleDebugPanelShortcut: String? = "cmd+shift+d",
    toggleTerminalShortcut: String? = "cmd+shift+t",
    cycleAgentNextShortcut: String? = "cmd+ctrl+down",
    cycleAgentPrevShortcut: String? = "cmd+ctrl+up",
    cycleWorkspaceNextShortcut: String? = "cmd+shift+down",
    cycleWorkspacePrevShortcut: String? = "cmd+shift+up",
    lastComposerModelId: String? = nil,
    lastComposerReasoningEffort: String? = nil,
    uiScale: Double = 1.0,
    theme: String = "system",
    usageShowRemaining: Bool = false,
    uiFontFamily: String = "system-ui, -apple-system, BlinkMacSystemFont, \"Segoe UI\", Roboto, \"Helvetica Neue\", Arial, sans-serif",
    codeFontFamily: String = "ui-monospace, \"Cascadia Mono\", \"Segoe UI Mono\", Menlo, Monaco, Consolas, \"Liberation Mono\", \"Courier New\", monospace",
    codeFontSize: UInt8 = 11,
    notificationSoundsEnabled: Bool = true,
    preloadGitDiffs: Bool = true,
    gitDiffIgnoreWhitespaceChanges: Bool = false,
    systemNotificationsEnabled: Bool = true,
    experimentalCollabEnabled: Bool = false,
    collaborationModesEnabled: Bool = true,
    steerEnabled: Bool = true,
    unifiedExecEnabled: Bool = true,
    experimentalAppsEnabled: Bool = false,
    personality: String = "friendly",
    dictationEnabled: Bool = false,
    dictationModelId: String = "base",
    dictationPreferredLanguage: String? = nil,
    dictationHoldKey: String = "alt",
    composerEditorPreset: String = "default",
    composerFenceExpandOnSpace: Bool = false,
    composerFenceExpandOnEnter: Bool = false,
    composerFenceLanguageTags: Bool = false,
    composerFenceWrapSelection: Bool = false,
    composerFenceAutoWrapPasteMultiline: Bool = false,
    composerFenceAutoWrapPasteCodeLike: Bool = false,
    composerListContinuation: Bool = false,
    composerCodeBlockCopyUseModifier: Bool = false,
    workspaceGroups: [WorkspaceGroup] = [],
    openAppTargets: [OpenAppTarget]? = nil,
    selectedOpenAppId: String = "vscode"
  ) {
    self.codexBin = codexBin
    self.codexArgs = codexArgs
    self.backendMode = backendMode
    self.remoteBackendHost = remoteBackendHost
    self.remoteBackendToken = remoteBackendToken
    self.defaultAccessMode = defaultAccessMode
    self.reviewDeliveryMode = reviewDeliveryMode
    self.composerModelShortcut = composerModelShortcut
    self.composerAccessShortcut = composerAccessShortcut
    self.composerReasoningShortcut = composerReasoningShortcut
    self.interruptShortcut = interruptShortcut
    self.composerCollaborationShortcut = composerCollaborationShortcut
    self.newAgentShortcut = newAgentShortcut
    self.newWorktreeAgentShortcut = newWorktreeAgentShortcut
    self.newCloneAgentShortcut = newCloneAgentShortcut
    self.archiveThreadShortcut = archiveThreadShortcut
    self.toggleProjectsSidebarShortcut = toggleProjectsSidebarShortcut
    self.toggleGitSidebarShortcut = toggleGitSidebarShortcut
    self.toggleDebugPanelShortcut = toggleDebugPanelShortcut
    self.toggleTerminalShortcut = toggleTerminalShortcut
    self.cycleAgentNextShortcut = cycleAgentNextShortcut
    self.cycleAgentPrevShortcut = cycleAgentPrevShortcut
    self.cycleWorkspaceNextShortcut = cycleWorkspaceNextShortcut
    self.cycleWorkspacePrevShortcut = cycleWorkspacePrevShortcut
    self.lastComposerModelId = lastComposerModelId
    self.lastComposerReasoningEffort = lastComposerReasoningEffort
    self.uiScale = uiScale
    self.theme = theme
    self.usageShowRemaining = usageShowRemaining
    self.uiFontFamily = uiFontFamily
    self.codeFontFamily = codeFontFamily
    self.codeFontSize = codeFontSize
    self.notificationSoundsEnabled = notificationSoundsEnabled
    self.preloadGitDiffs = preloadGitDiffs
    self.gitDiffIgnoreWhitespaceChanges = gitDiffIgnoreWhitespaceChanges
    self.systemNotificationsEnabled = systemNotificationsEnabled
    self.experimentalCollabEnabled = experimentalCollabEnabled
    self.collaborationModesEnabled = collaborationModesEnabled
    self.steerEnabled = steerEnabled
    self.unifiedExecEnabled = unifiedExecEnabled
    self.experimentalAppsEnabled = experimentalAppsEnabled
    self.personality = personality
    self.dictationEnabled = dictationEnabled
    self.dictationModelId = dictationModelId
    self.dictationPreferredLanguage = dictationPreferredLanguage
    self.dictationHoldKey = dictationHoldKey
    self.composerEditorPreset = composerEditorPreset
    self.composerFenceExpandOnSpace = composerFenceExpandOnSpace
    self.composerFenceExpandOnEnter = composerFenceExpandOnEnter
    self.composerFenceLanguageTags = composerFenceLanguageTags
    self.composerFenceWrapSelection = composerFenceWrapSelection
    self.composerFenceAutoWrapPasteMultiline = composerFenceAutoWrapPasteMultiline
    self.composerFenceAutoWrapPasteCodeLike = composerFenceAutoWrapPasteCodeLike
    self.composerListContinuation = composerListContinuation
    self.composerCodeBlockCopyUseModifier = composerCodeBlockCopyUseModifier
    self.workspaceGroups = workspaceGroups
    self.openAppTargets = openAppTargets ?? AppSettings.defaultOpenAppTargets()
    self.selectedOpenAppId = selectedOpenAppId
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    codexBin = try container.decodeIfPresent(String.self, forKey: .codexBin)
    codexArgs = try container.decodeIfPresent(String.self, forKey: .codexArgs)
    backendMode = try container.decodeIfPresent(BackendMode.self, forKey: .backendMode) ?? .local
    remoteBackendHost = try container.decodeIfPresent(String.self, forKey: .remoteBackendHost) ?? "127.0.0.1:4732"
    remoteBackendToken = try container.decodeIfPresent(String.self, forKey: .remoteBackendToken)
    defaultAccessMode = try container.decodeIfPresent(String.self, forKey: .defaultAccessMode) ?? "current"
    reviewDeliveryMode = try container.decodeIfPresent(String.self, forKey: .reviewDeliveryMode) ?? "inline"
    composerModelShortcut = try container.decodeIfPresent(String.self, forKey: .composerModelShortcut) ?? "cmd+shift+m"
    composerAccessShortcut = try container.decodeIfPresent(String.self, forKey: .composerAccessShortcut) ?? "cmd+shift+a"
    composerReasoningShortcut = try container.decodeIfPresent(String.self, forKey: .composerReasoningShortcut) ?? "cmd+shift+r"
    interruptShortcut = try container.decodeIfPresent(String.self, forKey: .interruptShortcut) ?? "ctrl+c"
    composerCollaborationShortcut = try container.decodeIfPresent(String.self, forKey: .composerCollaborationShortcut) ?? "shift+tab"
    newAgentShortcut = try container.decodeIfPresent(String.self, forKey: .newAgentShortcut) ?? "cmd+n"
    newWorktreeAgentShortcut = try container.decodeIfPresent(String.self, forKey: .newWorktreeAgentShortcut) ?? "cmd+shift+n"
    newCloneAgentShortcut = try container.decodeIfPresent(String.self, forKey: .newCloneAgentShortcut) ?? "cmd+alt+n"
    archiveThreadShortcut = try container.decodeIfPresent(String.self, forKey: .archiveThreadShortcut) ?? "cmd+ctrl+a"
    toggleProjectsSidebarShortcut = try container.decodeIfPresent(String.self, forKey: .toggleProjectsSidebarShortcut) ?? "cmd+shift+p"
    toggleGitSidebarShortcut = try container.decodeIfPresent(String.self, forKey: .toggleGitSidebarShortcut) ?? "cmd+shift+g"
    toggleDebugPanelShortcut = try container.decodeIfPresent(String.self, forKey: .toggleDebugPanelShortcut) ?? "cmd+shift+d"
    toggleTerminalShortcut = try container.decodeIfPresent(String.self, forKey: .toggleTerminalShortcut) ?? "cmd+shift+t"
    cycleAgentNextShortcut = try container.decodeIfPresent(String.self, forKey: .cycleAgentNextShortcut) ?? "cmd+ctrl+down"
    cycleAgentPrevShortcut = try container.decodeIfPresent(String.self, forKey: .cycleAgentPrevShortcut) ?? "cmd+ctrl+up"
    cycleWorkspaceNextShortcut = try container.decodeIfPresent(String.self, forKey: .cycleWorkspaceNextShortcut) ?? "cmd+shift+down"
    cycleWorkspacePrevShortcut = try container.decodeIfPresent(String.self, forKey: .cycleWorkspacePrevShortcut) ?? "cmd+shift+up"
    lastComposerModelId = try container.decodeIfPresent(String.self, forKey: .lastComposerModelId)
    lastComposerReasoningEffort = try container.decodeIfPresent(String.self, forKey: .lastComposerReasoningEffort)
    uiScale = try container.decodeIfPresent(Double.self, forKey: .uiScale) ?? 1.0
    theme = try container.decodeIfPresent(String.self, forKey: .theme) ?? "system"
    usageShowRemaining = try container.decodeIfPresent(Bool.self, forKey: .usageShowRemaining) ?? false
    uiFontFamily = try container.decodeIfPresent(String.self, forKey: .uiFontFamily) ?? "system-ui, -apple-system, BlinkMacSystemFont, \"Segoe UI\", Roboto, \"Helvetica Neue\", Arial, sans-serif"
    codeFontFamily = try container.decodeIfPresent(String.self, forKey: .codeFontFamily) ?? "ui-monospace, \"Cascadia Mono\", \"Segoe UI Mono\", Menlo, Monaco, Consolas, \"Liberation Mono\", \"Courier New\", monospace"
    codeFontSize = try container.decodeIfPresent(UInt8.self, forKey: .codeFontSize) ?? 11
    notificationSoundsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationSoundsEnabled) ?? true
    preloadGitDiffs = try container.decodeIfPresent(Bool.self, forKey: .preloadGitDiffs) ?? true
    gitDiffIgnoreWhitespaceChanges = try container.decodeIfPresent(Bool.self, forKey: .gitDiffIgnoreWhitespaceChanges) ?? false
    systemNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .systemNotificationsEnabled) ?? true
    experimentalCollabEnabled = try container.decodeIfPresent(Bool.self, forKey: .experimentalCollabEnabled) ?? false
    collaborationModesEnabled = try container.decodeIfPresent(Bool.self, forKey: .collaborationModesEnabled) ?? true
    steerEnabled = try container.decodeIfPresent(Bool.self, forKey: .steerEnabled) ?? true
    unifiedExecEnabled = try container.decodeIfPresent(Bool.self, forKey: .unifiedExecEnabled) ?? true
    experimentalAppsEnabled = try container.decodeIfPresent(Bool.self, forKey: .experimentalAppsEnabled) ?? false
    personality = try container.decodeIfPresent(String.self, forKey: .personality) ?? "friendly"
    dictationEnabled = try container.decodeIfPresent(Bool.self, forKey: .dictationEnabled) ?? false
    dictationModelId = try container.decodeIfPresent(String.self, forKey: .dictationModelId) ?? "base"
    dictationPreferredLanguage = try container.decodeIfPresent(String.self, forKey: .dictationPreferredLanguage)
    dictationHoldKey = try container.decodeIfPresent(String.self, forKey: .dictationHoldKey) ?? "alt"
    composerEditorPreset = try container.decodeIfPresent(String.self, forKey: .composerEditorPreset) ?? "default"
    composerFenceExpandOnSpace = try container.decodeIfPresent(Bool.self, forKey: .composerFenceExpandOnSpace) ?? false
    composerFenceExpandOnEnter = try container.decodeIfPresent(Bool.self, forKey: .composerFenceExpandOnEnter) ?? false
    composerFenceLanguageTags = try container.decodeIfPresent(Bool.self, forKey: .composerFenceLanguageTags) ?? false
    composerFenceWrapSelection = try container.decodeIfPresent(Bool.self, forKey: .composerFenceWrapSelection) ?? false
    composerFenceAutoWrapPasteMultiline = try container.decodeIfPresent(Bool.self, forKey: .composerFenceAutoWrapPasteMultiline) ?? false
    composerFenceAutoWrapPasteCodeLike = try container.decodeIfPresent(Bool.self, forKey: .composerFenceAutoWrapPasteCodeLike) ?? false
    composerListContinuation = try container.decodeIfPresent(Bool.self, forKey: .composerListContinuation) ?? false
    composerCodeBlockCopyUseModifier = try container.decodeIfPresent(Bool.self, forKey: .composerCodeBlockCopyUseModifier) ?? false
    workspaceGroups = try container.decodeIfPresent([WorkspaceGroup].self, forKey: .workspaceGroups) ?? []
    openAppTargets = try container.decodeIfPresent([OpenAppTarget].self, forKey: .openAppTargets) ?? AppSettings.defaultOpenAppTargets()
    selectedOpenAppId = try container.decodeIfPresent(String.self, forKey: .selectedOpenAppId) ?? "vscode"
  }

  static func defaultOpenAppTargets() -> [OpenAppTarget] {
    [
      OpenAppTarget(id: "vscode", label: "VS Code", kind: "app", appName: "Visual Studio Code"),
      OpenAppTarget(id: "cursor", label: "Cursor", kind: "app", appName: "Cursor"),
      OpenAppTarget(id: "zed", label: "Zed", kind: "app", appName: "Zed"),
      OpenAppTarget(id: "ghostty", label: "Ghostty", kind: "app", appName: "Ghostty"),
      OpenAppTarget(id: "antigravity", label: "Antigravity", kind: "app", appName: "Antigravity"),
      OpenAppTarget(id: "finder", label: "Finder", kind: "finder"),
    ]
  }
}

struct CodexDoctorResult: Codable, Sendable {
  let ok: Bool
  let codexBin: String?
  let version: String?
  let appServerOk: Bool
  let details: String?
}

// MARK: - File Types

enum FileScope: String, Codable, Sendable {
  case workspace
  case global
}

enum FileKind: String, Codable, Sendable {
  case agents
  case config
}

struct TextFileResponse: Codable, Sendable {
  let exists: Bool
  let content: String
  let truncated: Bool
}

// MARK: - Prompt Types

struct PromptEntry: Codable, Sendable {
  let name: String
  let path: String
  let scope: String
  var description: String?
  var argumentHint: String?
  var content: String
}

// MARK: - Workspace File Response

struct WorkspaceFileResponse: Codable, Sendable {
  let content: String
  let truncated: Bool
}
