import type { GitLogEntry } from "../types";
import type { MouseEvent as ReactMouseEvent } from "react";
import { LogicalPosition, Menu, MenuItem, getCurrentWindow, openUrl } from "../services/velox";
import { GitBranch } from "lucide-react";

type GitDiffPanelProps = {
  mode: "diff" | "log";
  onModeChange: (mode: "diff" | "log") => void;
  branchName: string;
  totalAdditions: number;
  totalDeletions: number;
  fileStatus: string;
  error?: string | null;
  logError?: string | null;
  logLoading?: boolean;
  logTotal?: number;
  gitRemoteUrl?: string | null;
  selectedPath?: string | null;
  onSelectFile?: (path: string) => void;
  files: {
    path: string;
    status: string;
    additions: number;
    deletions: number;
  }[];
  logEntries: GitLogEntry[];
};

function splitPath(path: string) {
  const parts = path.split("/");
  if (parts.length === 1) {
    return { name: path, dir: "" };
  }
  return { name: parts[parts.length - 1], dir: parts.slice(0, -1).join("/") };
}

function splitNameAndExtension(name: string) {
  const lastDot = name.lastIndexOf(".");
  if (lastDot <= 0 || lastDot === name.length - 1) {
    return { base: name, extension: "" };
  }
  return {
    base: name.slice(0, lastDot),
    extension: name.slice(lastDot + 1).toLowerCase(),
  };
}

function getStatusSymbol(status: string) {
  switch (status) {
    case "A":
      return "+";
    case "M":
      return "M";
    case "D":
      return "-";
    case "R":
      return "R";
    case "T":
      return "T";
    default:
      return "?";
  }
}

function getStatusClass(status: string) {
  switch (status) {
    case "A":
      return "diff-icon-added";
    case "M":
      return "diff-icon-modified";
    case "D":
      return "diff-icon-deleted";
    case "R":
      return "diff-icon-renamed";
    case "T":
      return "diff-icon-typechange";
    default:
      return "diff-icon-unknown";
  }
}

export function GitDiffPanel({
  mode,
  onModeChange,
  branchName,
  fileStatus,
  error,
  logError,
  logLoading = false,
  logTotal = 0,
  gitRemoteUrl = null,
  selectedPath,
  onSelectFile,
  files,
  logEntries,
}: GitDiffPanelProps) {
  const githubBaseUrl = (() => {
    if (!gitRemoteUrl) {
      return null;
    }
    const trimmed = gitRemoteUrl.trim();
    if (!trimmed) {
      return null;
    }
    let path = "";
    if (trimmed.startsWith("git@github.com:")) {
      path = trimmed.slice("git@github.com:".length);
    } else if (trimmed.startsWith("ssh://git@github.com/")) {
      path = trimmed.slice("ssh://git@github.com/".length);
    } else if (trimmed.includes("github.com/")) {
      path = trimmed.split("github.com/")[1] ?? "";
    }
    path = path.replace(/\.git$/, "").replace(/\/$/, "");
    if (!path) {
      return null;
    }
    return `https://github.com/${path}`;
  })();

  async function showLogMenu(event: ReactMouseEvent<HTMLDivElement>, entry: GitLogEntry) {
    event.preventDefault();
    event.stopPropagation();
    const copyItem = await MenuItem.new({
      text: "Copy SHA",
      action: async () => {
        await navigator.clipboard.writeText(entry.sha);
      },
    });
    const items = [copyItem];
    if (githubBaseUrl) {
      const openItem = await MenuItem.new({
        text: "Open on GitHub",
        action: async () => {
          await openUrl(`${githubBaseUrl}/commit/${entry.sha}`);
        },
      });
      items.push(openItem);
    }
    const menu = await Menu.new({ items });
    const window = getCurrentWindow();
    const position = new LogicalPosition(event.clientX, event.clientY);
    await menu.popup(position, window);
  }
  const logCountLabel = logTotal
    ? `${logTotal} commit${logTotal === 1 ? "" : "s"}`
    : logEntries.length
      ? `${logEntries.length} commit${logEntries.length === 1 ? "" : "s"}`
    : "No commits";
  return (
    <aside className="diff-panel">
      <div className="git-panel-header">
        <div className="git-panel-title">
          <GitBranch className="git-panel-icon" />
          Git
        </div>
        <div className="git-panel-toggle" role="tablist" aria-label="Git panel">
          <button
            type="button"
            role="tab"
            aria-selected={mode === "diff"}
            className={mode === "diff" ? "active" : ""}
            onClick={() => onModeChange("diff")}
          >
            Diff
          </button>
          <button
            type="button"
            role="tab"
            aria-selected={mode === "log"}
            className={mode === "log" ? "active" : ""}
            onClick={() => onModeChange("log")}
          >
            Log
          </button>
        </div>
      </div>
      <div className="diff-status">
        {mode === "diff" ? fileStatus : logCountLabel}
      </div>
      <div className="diff-branch">{branchName || "unknown"}</div>
      {mode === "diff" ? (
        <div className="diff-list">
          {error && <div className="diff-error">{error}</div>}
          {!error && !files.length && (
            <div className="diff-empty">No changes detected.</div>
          )}
          {files.map((file) => {
            const { name } = splitPath(file.path);
            const { base, extension } = splitNameAndExtension(name);
            const isSelected = file.path === selectedPath;
            const statusSymbol = getStatusSymbol(file.status);
            const statusClass = getStatusClass(file.status);
            return (
              <div
                key={file.path}
                className={`diff-row ${isSelected ? "active" : ""}`}
                role="button"
                tabIndex={0}
                onClick={() => onSelectFile?.(file.path)}
                onKeyDown={(event) => {
                  if (event.key === "Enter" || event.key === " ") {
                    event.preventDefault();
                    onSelectFile?.(file.path);
                  }
                }}
              >
                <span className={`diff-icon ${statusClass}`} aria-hidden>
                  {statusSymbol}
                </span>
                <div className="diff-file">
                  <div className="diff-path">
                    <span className="diff-name">
                      <span className="diff-name-base">{base}</span>
                      {extension && (
                        <span className="diff-name-ext">.{extension}</span>
                      )}
                    </span>
                    <span className="diff-counts-inline">
                      <span className="diff-add">+{file.additions}</span>
                      <span className="diff-sep">/</span>
                      <span className="diff-del">-{file.deletions}</span>
                    </span>
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      ) : (
        <div className="git-log-list">
          {logError && <div className="diff-error">{logError}</div>}
          {!logError && logLoading && (
            <div className="diff-viewer-loading">Loading commits...</div>
          )}
          {!logError && !logLoading && !logEntries.length && (
            <div className="diff-empty">No commits yet.</div>
          )}
          {logEntries.map((entry) => (
            <div
              key={entry.sha}
              className="git-log-entry"
              onContextMenu={(event) => showLogMenu(event, entry)}
            >
              <div className="git-log-summary">{entry.summary || "No message"}</div>
              <div className="git-log-meta">
                <span className="git-log-sha">{entry.sha.slice(0, 7)}</span>
                <span className="git-log-sep">·</span>
                <span className="git-log-author">
                  {entry.author || "Unknown"}
                </span>
                <span className="git-log-sep">·</span>
                <span className="git-log-date">
                  {new Date(entry.timestamp * 1000).toLocaleDateString()}
                </span>
              </div>
            </div>
          ))}
        </div>
      )}
    </aside>
  );
}
