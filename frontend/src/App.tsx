import { useEffect, useState } from "react";
import { getCurrentWindow } from "./services/velox";
import "./styles/base.css";
import "./styles/buttons.css";
import "./styles/sidebar.css";
import "./styles/home.css";
import "./styles/main.css";
import "./styles/messages.css";
import "./styles/approval-toasts.css";
import "./styles/update-toasts.css";
import "./styles/composer.css";
import "./styles/diff.css";
import "./styles/diff-viewer.css";
import "./styles/debug.css";
import "./styles/plan.css";
import "./styles/about.css";
import "./styles/tabbar.css";
import "./styles/worktree-modal.css";
import "./styles/settings.css";
import "./styles/compact-base.css";
import "./styles/compact-phone.css";
import "./styles/compact-tablet.css";
import { Sidebar } from "./components/Sidebar";
import { WorktreePrompt } from "./components/WorktreePrompt";
import { Home } from "./components/Home";
import { MainHeader } from "./components/MainHeader";
import { Messages } from "./components/Messages";
import { ApprovalToasts } from "./components/ApprovalToasts";
import { UpdateToast } from "./components/UpdateToast";
import { Composer } from "./components/Composer";
import { GitDiffPanel } from "./components/GitDiffPanel";
import { GitDiffViewer } from "./components/GitDiffViewer";
import { DebugPanel } from "./components/DebugPanel";
import { PlanPanel } from "./components/PlanPanel";
import { AboutView } from "./components/AboutView";
import { TabBar } from "./components/TabBar";
import { TabletNav } from "./components/TabletNav";
import { SettingsView } from "./components/SettingsView";
import { ArrowLeft } from "lucide-react";
import { useWorkspaces } from "./hooks/useWorkspaces";
import { useThreads } from "./hooks/useThreads";
import { useWindowDrag } from "./hooks/useWindowDrag";
import { useGitStatus } from "./hooks/useGitStatus";
import { useGitDiffs } from "./hooks/useGitDiffs";
import { useGitLog } from "./hooks/useGitLog";
import { useGitRemote } from "./hooks/useGitRemote";
import { useModels } from "./hooks/useModels";
import { useSkills } from "./hooks/useSkills";
import { useWorkspaceFiles } from "./hooks/useWorkspaceFiles";
import { useGitBranches } from "./hooks/useGitBranches";
import { useDebugLog } from "./hooks/useDebugLog";
import { useWorkspaceRefreshOnFocus } from "./hooks/useWorkspaceRefreshOnFocus";
import { useWorkspaceRestore } from "./hooks/useWorkspaceRestore";
import { useResizablePanels } from "./hooks/useResizablePanels";
import { useLayoutMode } from "./hooks/useLayoutMode";
import { useAppSettings } from "./hooks/useAppSettings";
import { useUpdater } from "./hooks/useUpdater";
import type { AccessMode, QueuedMessage, WorkspaceInfo } from "./types";

function useWindowLabel() {
  const [label, setLabel] = useState("main");
  useEffect(() => {
    try {
      const window = getCurrentWindow();
      setLabel(window.label ?? "main");
    } catch {
      setLabel("main");
    }
  }, []);
  return label;
}

function MainApp() {
  const {
    sidebarWidth,
    rightPanelWidth,
    onSidebarResizeStart,
    onRightPanelResizeStart,
    planPanelHeight,
    onPlanPanelResizeStart,
    debugPanelHeight,
    onDebugPanelResizeStart,
  } = useResizablePanels();
  const layoutMode = useLayoutMode();
  const isCompact = layoutMode !== "desktop";
  const isTablet = layoutMode === "tablet";
  const isPhone = layoutMode === "phone";
  const [centerMode, setCenterMode] = useState<"chat" | "diff">("chat");
  const [selectedDiffPath, setSelectedDiffPath] = useState<string | null>(null);
  const [gitPanelMode, setGitPanelMode] = useState<"diff" | "log">("diff");
  const [accessMode, setAccessMode] = useState<AccessMode>("current");
  const [activeTab, setActiveTab] = useState<
    "projects" | "codex" | "git" | "log"
  >("codex");
  const tabletTab = activeTab === "projects" ? "codex" : activeTab;
  const [queuedByThread, setQueuedByThread] = useState<
    Record<string, QueuedMessage[]>
  >({});
  const [prefillDraft, setPrefillDraft] = useState<QueuedMessage | null>(null);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [reduceTransparency, setReduceTransparency] = useState(() => {
    const stored = localStorage.getItem("reduceTransparency");
    return stored === "true";
  });
  const [flushingByThread, setFlushingByThread] = useState<Record<string, boolean>>(
    {},
  );
  const [worktreePrompt, setWorktreePrompt] = useState<{
    workspace: WorkspaceInfo;
    branch: string;
    isSubmitting: boolean;
    error: string | null;
  } | null>(null);
  const {
    debugOpen,
    setDebugOpen,
    debugEntries,
    hasDebugAlerts,
    addDebugEntry,
    handleCopyDebug,
    clearDebugEntries,
  } = useDebugLog();

  const updater = useUpdater({ onDebug: addDebugEntry });

  const { settings: appSettings, saveSettings, doctor } = useAppSettings();

  const {
    workspaces,
    activeWorkspace,
    activeWorkspaceId,
    setActiveWorkspaceId,
    addWorkspace,
    addWorktreeAgent,
    connectWorkspace,
    markWorkspaceConnected,
    updateWorkspaceSettings,
    updateWorkspaceCodexBin,
    removeWorkspace,
    removeWorktree,
    hasLoaded,
    refreshWorkspaces,
  } = useWorkspaces({ onDebug: addDebugEntry, defaultCodexBin: appSettings.codexBin });

  useEffect(() => {
    setAccessMode((prev) =>
      prev === "current" ? appSettings.defaultAccessMode : prev,
    );
  }, [appSettings.defaultAccessMode]);

  useEffect(() => {
    localStorage.setItem("reduceTransparency", String(reduceTransparency));
  }, [reduceTransparency]);


  const { status: gitStatus, refresh: refreshGitStatus } =
    useGitStatus(activeWorkspace);
  const compactTab = isTablet ? tabletTab : activeTab;
  const shouldLoadDiffs =
    centerMode === "diff" || (isCompact && compactTab === "git");
  const {
    diffs: gitDiffs,
    isLoading: isDiffLoading,
    error: diffError,
  } = useGitDiffs(activeWorkspace, gitStatus.files, shouldLoadDiffs);
  const {
    entries: gitLogEntries,
    total: gitLogTotal,
    isLoading: gitLogLoading,
    error: gitLogError,
  } = useGitLog(activeWorkspace, gitPanelMode === "log");
  const { remote: gitRemoteUrl } = useGitRemote(activeWorkspace);
  const {
    models,
    selectedModel,
    selectedModelId,
    setSelectedModelId,
    reasoningOptions,
    selectedEffort,
    setSelectedEffort,
  } = useModels({ activeWorkspace, onDebug: addDebugEntry });
  const { skills } = useSkills({ activeWorkspace, onDebug: addDebugEntry });
  const { files } = useWorkspaceFiles({ activeWorkspace, onDebug: addDebugEntry });
  const {
    branches,
    checkoutBranch,
    createBranch,
  } = useGitBranches({ activeWorkspace, onDebug: addDebugEntry });
  const handleCheckoutBranch = async (name: string) => {
    await checkoutBranch(name);
    refreshGitStatus();
  };
  const handleCreateBranch = async (name: string) => {
    await createBranch(name);
    refreshGitStatus();
  };

  const resolvedModel = selectedModel?.model ?? null;
  const fileStatus =
    gitStatus.files.length > 0
      ? `${gitStatus.files.length} file${gitStatus.files.length === 1 ? "" : "s"} changed`
      : "Working tree clean";

  const {
    setActiveThreadId,
    activeThreadId,
    activeItems,
    approvals,
    threadsByWorkspace,
    threadStatusById,
    threadListLoadingByWorkspace,
    activeTurnIdByThread,
    tokenUsageByThread,
    rateLimitsByWorkspace,
    planByThread,
    interruptTurn,
    removeThread,
    startThreadForWorkspace,
    listThreadsForWorkspace,
    sendUserMessage,
    startReview,
    handleApprovalDecision,
  } = useThreads({
    activeWorkspace,
    onWorkspaceConnected: markWorkspaceConnected,
    onDebug: addDebugEntry,
    model: resolvedModel,
    effort: selectedEffort,
    accessMode,
    onMessageActivity: refreshGitStatus,
  });

  const activeRateLimits = activeWorkspaceId
    ? rateLimitsByWorkspace[activeWorkspaceId] ?? null
    : null;
  const activeTokenUsage = activeThreadId
    ? tokenUsageByThread[activeThreadId] ?? null
    : null;
  const activePlan = activeThreadId ? planByThread[activeThreadId] ?? null : null;
  const hasActivePlan = Boolean(
    activePlan && (activePlan.steps.length > 0 || activePlan.explanation),
  );
  const showHome = !activeWorkspace;
  const canInterrupt = activeThreadId
    ? Boolean(
        threadStatusById[activeThreadId]?.isProcessing &&
          activeTurnIdByThread[activeThreadId],
      )
    : false;
  const isProcessing = activeThreadId
    ? threadStatusById[activeThreadId]?.isProcessing ?? false
    : false;
  const isReviewing = activeThreadId
    ? threadStatusById[activeThreadId]?.isReviewing ?? false
    : false;
  const activeQueue = activeThreadId
    ? queuedByThread[activeThreadId] ?? []
    : [];
  const isWorktreeWorkspace = activeWorkspace?.kind === "worktree";
  const activeParentWorkspace = isWorktreeWorkspace
    ? workspaces.find((entry) => entry.id === activeWorkspace?.parentId) ?? null
    : null;
  const worktreeLabel = isWorktreeWorkspace
    ? activeWorkspace?.worktree?.branch ?? activeWorkspace?.name ?? null
    : null;

  useEffect(() => {
    if (!isPhone) {
      return;
    }
    if (!activeWorkspace && activeTab !== "projects") {
      setActiveTab("projects");
    }
  }, [activeTab, activeWorkspace, isPhone]);

  useEffect(() => {
    if (!isTablet) {
      return;
    }
    if (activeTab === "projects") {
      setActiveTab("codex");
    }
  }, [activeTab, isTablet]);

  useWindowDrag("titlebar");
  useWorkspaceRestore({
    workspaces,
    hasLoaded,
    connectWorkspace,
    listThreadsForWorkspace,
  });
  useWorkspaceRefreshOnFocus({
    workspaces,
    refreshWorkspaces,
    listThreadsForWorkspace,
  });

  async function handleAddWorkspace() {
    try {
      const workspace = await addWorkspace();
      if (workspace) {
        setActiveThreadId(null, workspace.id);
        if (isCompact) {
          setActiveTab("codex");
        }
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      addDebugEntry({
        id: `${Date.now()}-client-add-workspace-error`,
        timestamp: Date.now(),
        source: "error",
        label: "workspace/add error",
        payload: message,
      });
      alert(`Failed to add workspace.\n\n${message}`);
    }
  }

  function selectWorkspace(workspaceId: string) {
    const target = workspaces.find((entry) => entry.id === workspaceId);
    if (target?.settings.sidebarCollapsed) {
      void updateWorkspaceSettings(workspaceId, {
        ...target.settings,
        sidebarCollapsed: false,
      });
    }
    setActiveWorkspaceId(workspaceId);
    if (isCompact) {
      setActiveTab("codex");
    }
  }

  function exitDiffView() {
    setCenterMode("chat");
    setSelectedDiffPath(null);
  }

  async function handleAddAgent(workspace: (typeof workspaces)[number]) {
    exitDiffView();
    selectWorkspace(workspace.id);
    if (!workspace.connected) {
      await connectWorkspace(workspace);
    }
    await startThreadForWorkspace(workspace.id);
    if (isCompact) {
      setActiveTab("codex");
    }
  }

  async function handleAddWorktreeAgent(workspace: (typeof workspaces)[number]) {
    exitDiffView();
    const defaultBranch = `codex/${new Date().toISOString().slice(0, 10)}-${Math.random()
      .toString(36)
      .slice(2, 6)}`;
    setWorktreePrompt({
      workspace,
      branch: defaultBranch,
      isSubmitting: false,
      error: null,
    });
  }

  async function handleConfirmWorktreePrompt() {
    if (!worktreePrompt || worktreePrompt.isSubmitting) {
      return;
    }
    const { workspace, branch } = worktreePrompt;
    setWorktreePrompt((prev) =>
      prev ? { ...prev, isSubmitting: true, error: null } : prev,
    );
    try {
      const worktreeWorkspace = await addWorktreeAgent(workspace, branch);
      if (!worktreeWorkspace) {
        setWorktreePrompt(null);
        return;
      }
      selectWorkspace(worktreeWorkspace.id);
      if (!worktreeWorkspace.connected) {
        await connectWorkspace(worktreeWorkspace);
      }
      if (isCompact) {
        setActiveTab("codex");
      }
      setWorktreePrompt(null);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      setWorktreePrompt((prev) =>
        prev ? { ...prev, isSubmitting: false, error: message } : prev,
      );
      addDebugEntry({
        id: `${Date.now()}-client-add-worktree-error`,
        timestamp: Date.now(),
        source: "error",
        label: "worktree/add error",
        payload: message,
      });
    }
  }

  function handleSelectDiff(path: string) {
    setSelectedDiffPath(path);
    setCenterMode("diff");
    setGitPanelMode("diff");
    if (isCompact) {
      setActiveTab("git");
    }
  }

  async function handleSend(text: string) {
    const trimmed = text.trim();
    if (!trimmed) {
      return;
    }
    if (activeThreadId && threadStatusById[activeThreadId]?.isReviewing) {
      return;
    }
    if (isProcessing && activeThreadId) {
      const item: QueuedMessage = {
        id: `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
        text: trimmed,
        createdAt: Date.now(),
      };
      setQueuedByThread((prev) => ({
        ...prev,
        [activeThreadId]: [...(prev[activeThreadId] ?? []), item],
      }));
      return;
    }
    if (activeWorkspace && !activeWorkspace.connected) {
      await connectWorkspace(activeWorkspace);
    }
    if (trimmed.startsWith("/review")) {
      await startReview(trimmed);
      return;
    }
    await sendUserMessage(trimmed);
  }

  useEffect(() => {
    if (!activeThreadId || isProcessing || isReviewing) {
      return;
    }
    if (flushingByThread[activeThreadId]) {
      return;
    }
    const queue = queuedByThread[activeThreadId] ?? [];
    if (queue.length === 0) {
      return;
    }
    const threadId = activeThreadId;
    const nextItem = queue[0];
    setFlushingByThread((prev) => ({ ...prev, [threadId]: true }));
    setQueuedByThread((prev) => ({
      ...prev,
      [threadId]: (prev[threadId] ?? []).slice(1),
    }));
    (async () => {
      try {
        if (nextItem.text.trim().startsWith("/review")) {
          await startReview(nextItem.text);
        } else {
          await sendUserMessage(nextItem.text);
        }
      } catch {
        setQueuedByThread((prev) => ({
          ...prev,
          [threadId]: [nextItem, ...(prev[threadId] ?? [])],
        }));
      } finally {
        setFlushingByThread((prev) => ({ ...prev, [threadId]: false }));
      }
    })();
  }, [
    activeThreadId,
    flushingByThread,
    isProcessing,
    isReviewing,
    queuedByThread,
    sendUserMessage,
  ]);

  const handleDebugClick = () => {
    if (isCompact) {
      setActiveTab("log");
      return;
    }
    setDebugOpen((prev) => !prev);
  };
  const handleOpenSettings = () => setSettingsOpen(true);

  const orderValue = (entry: WorkspaceInfo) =>
    typeof entry.settings.sortOrder === "number"
      ? entry.settings.sortOrder
      : Number.MAX_SAFE_INTEGER;

  const handleMoveWorkspace = async (workspaceId: string, direction: "up" | "down") => {
    const ordered = workspaces
      .filter((entry) => (entry.kind ?? "main") !== "worktree")
      .slice()
      .sort((a, b) => {
        const orderDiff = orderValue(a) - orderValue(b);
        if (orderDiff !== 0) {
          return orderDiff;
        }
        return a.name.localeCompare(b.name);
      });
    const index = ordered.findIndex((entry) => entry.id === workspaceId);
    if (index === -1) {
      return;
    }
    const nextIndex = direction === "up" ? index - 1 : index + 1;
    if (nextIndex < 0 || nextIndex >= ordered.length) {
      return;
    }
    const next = ordered.slice();
    const temp = next[index];
    next[index] = next[nextIndex];
    next[nextIndex] = temp;
    await Promise.all(
      next.map((entry, idx) =>
        updateWorkspaceSettings(entry.id, {
          ...entry.settings,
          sortOrder: idx,
        }),
      ),
    );
  };

  const showComposer = !isCompact
    ? centerMode === "chat"
    : (isTablet ? tabletTab : activeTab) === "codex";
  const showGitDetail = Boolean(selectedDiffPath) && isPhone;
  const appClassName = `app ${isCompact ? "layout-compact" : "layout-desktop"}${
    isPhone ? " layout-phone" : ""
  }${isTablet ? " layout-tablet" : ""}${reduceTransparency ? " reduced-transparency" : ""}`;

  const sidebarNode = (
      <Sidebar
        workspaces={workspaces}
        threadsByWorkspace={threadsByWorkspace}
        threadStatusById={threadStatusById}
        threadListLoadingByWorkspace={threadListLoadingByWorkspace}
        activeWorkspaceId={activeWorkspaceId}
        activeThreadId={activeThreadId}
        accountRateLimits={activeRateLimits}
        onOpenSettings={handleOpenSettings}
        onOpenDebug={handleDebugClick}
        hasDebugAlerts={hasDebugAlerts}
        onAddWorkspace={handleAddWorkspace}
      onSelectHome={() => {
        exitDiffView();
        setActiveWorkspaceId(null);
        if (isCompact) {
          setActiveTab("projects");
        }
      }}
      onSelectWorkspace={(workspaceId) => {
        exitDiffView();
        selectWorkspace(workspaceId);
      }}
      onConnectWorkspace={async (workspace) => {
        await connectWorkspace(workspace);
        if (isCompact) {
          setActiveTab("codex");
        }
      }}
      onAddAgent={handleAddAgent}
      onAddWorktreeAgent={handleAddWorktreeAgent}
      onToggleWorkspaceCollapse={(workspaceId, collapsed) => {
        const target = workspaces.find((entry) => entry.id === workspaceId);
        if (!target) {
          return;
        }
        void updateWorkspaceSettings(workspaceId, {
          ...target.settings,
          sidebarCollapsed: collapsed,
        });
      }}
      onSelectThread={(workspaceId, threadId) => {
        exitDiffView();
        selectWorkspace(workspaceId);
        setActiveThreadId(threadId, workspaceId);
      }}
      onDeleteThread={(workspaceId, threadId) => {
        removeThread(workspaceId, threadId);
      }}
      onDeleteWorkspace={(workspaceId) => {
        void removeWorkspace(workspaceId);
      }}
      onDeleteWorktree={(workspaceId) => {
        void removeWorktree(workspaceId);
      }}
    />
  );

  const messagesNode = (
    <Messages
      items={activeItems}
      isThinking={
        activeThreadId ? threadStatusById[activeThreadId]?.isProcessing ?? false : false
      }
    />
  );

  const composerNode = showComposer ? (
    <Composer
      onSend={handleSend}
      onStop={interruptTurn}
      canStop={canInterrupt}
      disabled={
        activeThreadId ? threadStatusById[activeThreadId]?.isReviewing ?? false : false
      }
      contextUsage={activeTokenUsage}
      queuedMessages={activeQueue}
      sendLabel={isProcessing ? "Queue" : "Send"}
      prefillDraft={prefillDraft}
      onPrefillHandled={(id) => {
        if (prefillDraft?.id === id) {
          setPrefillDraft(null);
        }
      }}
      onEditQueued={(item) => {
        if (!activeThreadId) {
          return;
        }
        setQueuedByThread((prev) => ({
          ...prev,
          [activeThreadId]: (prev[activeThreadId] ?? []).filter(
            (entry) => entry.id !== item.id,
          ),
        }));
        setPrefillDraft(item);
      }}
      onDeleteQueued={(id) => {
        if (!activeThreadId) {
          return;
        }
        setQueuedByThread((prev) => ({
          ...prev,
          [activeThreadId]: (prev[activeThreadId] ?? []).filter(
            (entry) => entry.id !== id,
          ),
        }));
      }}
      models={models}
      selectedModelId={selectedModelId}
      onSelectModel={setSelectedModelId}
      reasoningOptions={reasoningOptions}
      selectedEffort={selectedEffort}
      onSelectEffort={setSelectedEffort}
      accessMode={accessMode}
      onSelectAccessMode={setAccessMode}
      skills={skills}
      files={files}
    />
  ) : null;

  const desktopLayout = (
    <>
      {sidebarNode}
      <div
        className="sidebar-resizer"
        role="separator"
        aria-orientation="vertical"
        aria-label="Resize sidebar"
        onMouseDown={onSidebarResizeStart}
      />

      <section className="main">
        <UpdateToast
          state={updater.state}
          onUpdate={updater.startUpdate}
          onDismiss={updater.dismiss}
        />
        {showHome && (
          <Home
            onOpenProject={handleAddWorkspace}
            onAddWorkspace={handleAddWorkspace}
            onCloneRepository={() => {}}
          />
        )}

        {activeWorkspace && !showHome && (
          <>
            <div className="main-topbar" data-tauri-drag-region>
              <div className="main-topbar-left">
                {centerMode === "diff" && (
                  <button
                    className="icon-button back-button"
                    onClick={() => {
                      setCenterMode("chat");
                      setSelectedDiffPath(null);
                    }}
                    aria-label="Back to chat"
                  >
                    <ArrowLeft aria-hidden />
                  </button>
                )}
                <MainHeader
                  workspace={activeWorkspace}
                  parentName={activeParentWorkspace?.name ?? null}
                  worktreeLabel={worktreeLabel}
                  disableBranchMenu={isWorktreeWorkspace}
                  parentPath={activeParentWorkspace?.path ?? null}
                  worktreePath={isWorktreeWorkspace ? activeWorkspace.path : null}
                  branchName={gitStatus.branchName || "unknown"}
                  branches={branches}
                  onCheckoutBranch={handleCheckoutBranch}
                  onCreateBranch={handleCreateBranch}
                />
              </div>
              <div className="actions">
                {null}
              </div>
            </div>
            <ApprovalToasts
              approvals={approvals}
              workspaces={workspaces}
              onDecision={handleApprovalDecision}
            />
            <div className="content">
              {centerMode === "diff" ? (
                <GitDiffViewer
                  diffs={gitDiffs}
                  selectedPath={selectedDiffPath}
                  isLoading={isDiffLoading}
                  error={diffError}
                />
              ) : (
                messagesNode
              )}
            </div>

            <div
              className="right-panel-resizer"
              role="separator"
              aria-orientation="vertical"
              aria-label="Resize right panel"
              onMouseDown={onRightPanelResizeStart}
            />
            <div className={`right-panel ${hasActivePlan ? "" : "plan-collapsed"}`}>
              <div className="right-panel-top">
                <GitDiffPanel
                  mode={gitPanelMode}
                  onModeChange={setGitPanelMode}
                  branchName={gitStatus.branchName || "unknown"}
                  totalAdditions={gitStatus.totalAdditions}
                  totalDeletions={gitStatus.totalDeletions}
                  fileStatus={fileStatus}
                  error={gitStatus.error}
                  logError={gitLogError}
                  logLoading={gitLogLoading}
                  files={gitStatus.files}
                  selectedPath={selectedDiffPath}
                  onSelectFile={handleSelectDiff}
                  logEntries={gitLogEntries}
                  logTotal={gitLogTotal}
                  gitRemoteUrl={gitRemoteUrl}
                />
              </div>
              <div
                className="right-panel-divider"
                role="separator"
                aria-orientation="horizontal"
                aria-label="Resize plan panel"
                onMouseDown={onPlanPanelResizeStart}
              />
              <div className="right-panel-bottom">
                <PlanPanel plan={activePlan} isProcessing={isProcessing} />
              </div>
            </div>

            {composerNode}
            <DebugPanel
              entries={debugEntries}
              isOpen={debugOpen}
              onClear={clearDebugEntries}
              onCopy={handleCopyDebug}
              onResizeStart={onDebugPanelResizeStart}
            />
          </>
        )}
      </section>
    </>
  );

  const tabletLayout = (
    <>
      <TabletNav activeTab={tabletTab} onSelect={setActiveTab} />
      <div className="tablet-projects">{sidebarNode}</div>
      <div
        className="projects-resizer"
        role="separator"
        aria-orientation="vertical"
        aria-label="Resize projects"
        onMouseDown={onSidebarResizeStart}
      />
      <section className="tablet-main">
        <ApprovalToasts
          approvals={approvals}
          workspaces={workspaces}
          onDecision={handleApprovalDecision}
        />
        <UpdateToast
          state={updater.state}
          onUpdate={updater.startUpdate}
          onDismiss={updater.dismiss}
        />
        {showHome && (
          <Home
            onOpenProject={handleAddWorkspace}
            onAddWorkspace={handleAddWorkspace}
            onCloneRepository={() => {}}
          />
        )}
        {activeWorkspace && !showHome && (
          <>
            <div className="main-topbar tablet-topbar" data-tauri-drag-region>
              <div className="main-topbar-left">
                <MainHeader
                  workspace={activeWorkspace}
                  parentName={activeParentWorkspace?.name ?? null}
                  worktreeLabel={worktreeLabel}
                  disableBranchMenu={isWorktreeWorkspace}
                  parentPath={activeParentWorkspace?.path ?? null}
                  worktreePath={isWorktreeWorkspace ? activeWorkspace.path : null}
                  branchName={gitStatus.branchName || "unknown"}
                  branches={branches}
                  onCheckoutBranch={handleCheckoutBranch}
                  onCreateBranch={handleCreateBranch}
                />
              </div>
              <div className="actions" />
            </div>
            {tabletTab === "codex" && (
              <>
                <div className="content tablet-content">
                  {messagesNode}
                </div>
                {composerNode}
              </>
            )}
            {tabletTab === "git" && (
              <div className="tablet-git">
                <GitDiffPanel
                  mode={gitPanelMode}
                  onModeChange={setGitPanelMode}
                  branchName={gitStatus.branchName || "unknown"}
                  totalAdditions={gitStatus.totalAdditions}
                  totalDeletions={gitStatus.totalDeletions}
                  fileStatus={fileStatus}
                  error={gitStatus.error}
                  logError={gitLogError}
                  logLoading={gitLogLoading}
                  files={gitStatus.files}
                  selectedPath={selectedDiffPath}
                  onSelectFile={handleSelectDiff}
                  logEntries={gitLogEntries}
                  logTotal={gitLogTotal}
                  gitRemoteUrl={gitRemoteUrl}
                />
                <div className="tablet-git-viewer">
                  <GitDiffViewer
                    diffs={gitDiffs}
                    selectedPath={selectedDiffPath}
                    isLoading={isDiffLoading}
                    error={diffError}
                  />
                </div>
              </div>
            )}
            {tabletTab === "log" && (
              <DebugPanel
                entries={debugEntries}
                isOpen
                onClear={clearDebugEntries}
                onCopy={handleCopyDebug}
                variant="full"
              />
            )}
          </>
        )}
      </section>
    </>
  );

  const phoneLayout = (
    <div className="compact-shell">
      <ApprovalToasts
        approvals={approvals}
        workspaces={workspaces}
        onDecision={handleApprovalDecision}
      />
      <UpdateToast
        state={updater.state}
        onUpdate={updater.startUpdate}
        onDismiss={updater.dismiss}
      />
      {activeTab === "projects" && <div className="compact-panel">{sidebarNode}</div>}
      {activeTab === "codex" && (
        <div className="compact-panel">
          {activeWorkspace ? (
            <>
              <div className="main-topbar compact-topbar" data-tauri-drag-region>
                <div className="main-topbar-left">
                <MainHeader
                  workspace={activeWorkspace}
                  parentName={activeParentWorkspace?.name ?? null}
                  worktreeLabel={worktreeLabel}
                  disableBranchMenu={isWorktreeWorkspace}
                  parentPath={activeParentWorkspace?.path ?? null}
                  worktreePath={isWorktreeWorkspace ? activeWorkspace.path : null}
                  branchName={gitStatus.branchName || "unknown"}
                  branches={branches}
                  onCheckoutBranch={handleCheckoutBranch}
                  onCreateBranch={handleCreateBranch}
                />
                </div>
                <div className="actions" />
              </div>
              <div className="content compact-content">
                {messagesNode}
              </div>
              {composerNode}
            </>
          ) : (
            <div className="compact-empty">
              <h3>No workspace selected</h3>
              <p>Choose a project to start chatting.</p>
              <button className="ghost" onClick={() => setActiveTab("projects")}>
                Go to Projects
              </button>
            </div>
          )}
        </div>
      )}
      {activeTab === "git" && (
        <div className="compact-panel">
          {!activeWorkspace && (
            <div className="compact-empty">
              <h3>No workspace selected</h3>
              <p>Select a project to inspect diffs.</p>
              <button className="ghost" onClick={() => setActiveTab("projects")}>
                Go to Projects
              </button>
            </div>
          )}
          {activeWorkspace && showGitDetail && (
            <>
              <div className="compact-git-back">
                <button
                  onClick={() => {
                    setSelectedDiffPath(null);
                    setCenterMode("chat");
                  }}
                >
                  ‹ Back
                </button>
                <span className="workspace-title">Diff</span>
              </div>
              <div className="compact-git-viewer">
                <GitDiffViewer
                  diffs={gitDiffs}
                  selectedPath={selectedDiffPath}
                  isLoading={isDiffLoading}
                  error={diffError}
                />
              </div>
            </>
          )}
          {activeWorkspace && !showGitDetail && (
            <>
              <div className="main-topbar compact-topbar" data-tauri-drag-region>
                <div className="main-topbar-left">
                <MainHeader
                  workspace={activeWorkspace}
                  parentName={activeParentWorkspace?.name ?? null}
                  worktreeLabel={worktreeLabel}
                  disableBranchMenu={isWorktreeWorkspace}
                  parentPath={activeParentWorkspace?.path ?? null}
                  worktreePath={isWorktreeWorkspace ? activeWorkspace.path : null}
                  branchName={gitStatus.branchName || "unknown"}
                  branches={branches}
                  onCheckoutBranch={handleCheckoutBranch}
                  onCreateBranch={handleCreateBranch}
                />
                </div>
              </div>
              <div className="compact-git">
                <div className="compact-git-list">
                  <GitDiffPanel
                    mode={gitPanelMode}
                    onModeChange={setGitPanelMode}
                    branchName={gitStatus.branchName || "unknown"}
                    totalAdditions={gitStatus.totalAdditions}
                    totalDeletions={gitStatus.totalDeletions}
                    fileStatus={fileStatus}
                    error={gitStatus.error}
                    logError={gitLogError}
                    logLoading={gitLogLoading}
                    files={gitStatus.files}
                    selectedPath={selectedDiffPath}
                    onSelectFile={handleSelectDiff}
                    logEntries={gitLogEntries}
                    logTotal={gitLogTotal}
                    gitRemoteUrl={gitRemoteUrl}
                  />
                </div>
                {!isPhone && (
                  <div className="compact-git-viewer">
                    <GitDiffViewer
                      diffs={gitDiffs}
                      selectedPath={selectedDiffPath}
                      isLoading={isDiffLoading}
                      error={diffError}
                    />
                  </div>
                )}
              </div>
            </>
          )}
        </div>
      )}
      {activeTab === "log" && (
        <div className="compact-panel">
          <DebugPanel
            entries={debugEntries}
            isOpen
            onClear={clearDebugEntries}
            onCopy={handleCopyDebug}
            variant="full"
          />
        </div>
      )}
      <TabBar activeTab={activeTab} onSelect={setActiveTab} />
    </div>
  );

  return (
    <div
      className={appClassName}
      style={
        {
          "--sidebar-width": `${sidebarWidth}px`,
          "--right-panel-width": `${rightPanelWidth}px`,
          "--plan-panel-height": `${planPanelHeight}px`,
          "--debug-panel-height": `${debugPanelHeight}px`,
        } as React.CSSProperties
      }
    >
      <div className="drag-strip" id="titlebar" data-tauri-drag-region />
      {isPhone ? phoneLayout : isTablet ? tabletLayout : desktopLayout}
      {worktreePrompt && (
        <WorktreePrompt
          workspaceName={worktreePrompt.workspace.name}
          branch={worktreePrompt.branch}
          error={worktreePrompt.error}
          isBusy={worktreePrompt.isSubmitting}
          onChange={(value) =>
            setWorktreePrompt((prev) =>
              prev ? { ...prev, branch: value, error: null } : prev,
            )
          }
          onCancel={() => setWorktreePrompt(null)}
          onConfirm={handleConfirmWorktreePrompt}
        />
      )}
      {settingsOpen && (
        <SettingsView
          workspaces={workspaces}
          onClose={() => setSettingsOpen(false)}
          onMoveWorkspace={handleMoveWorkspace}
          onDeleteWorkspace={(workspaceId) => {
            void removeWorkspace(workspaceId);
          }}
          reduceTransparency={reduceTransparency}
          onToggleTransparency={setReduceTransparency}
          appSettings={appSettings}
          onUpdateAppSettings={async (next) => {
            await saveSettings(next);
          }}
          onRunDoctor={doctor}
          onUpdateWorkspaceCodexBin={async (id, codexBin) => {
            await updateWorkspaceCodexBin(id, codexBin);
          }}
        />
      )}
    </div>
  );
}

function App() {
  const windowLabel = useWindowLabel();
  if (windowLabel === "about") {
    return <AboutView />;
  }
  return <MainApp />;
}

export default App;
