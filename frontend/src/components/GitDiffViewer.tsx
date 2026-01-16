import { useEffect, useRef } from "react";
import { DiffBlock } from "./DiffBlock";
import { languageFromPath } from "../utils/syntax";
type GitDiffViewerItem = {
  path: string;
  status: string;
  diff: string;
};

type GitDiffViewerProps = {
  diffs: GitDiffViewerItem[];
  selectedPath: string | null;
  isLoading: boolean;
  error: string | null;
};

export function GitDiffViewer({
  diffs,
  selectedPath,
  isLoading,
  error,
}: GitDiffViewerProps) {
  const itemRefs = useRef(new Map<string, HTMLDivElement>());
  const lastScrolledPath = useRef<string | null>(null);

  useEffect(() => {
    if (!selectedPath) {
      return;
    }
    if (lastScrolledPath.current === selectedPath) {
      return;
    }
    const target = itemRefs.current.get(selectedPath);
    if (target) {
      target.scrollIntoView({ behavior: "smooth", block: "start" });
      lastScrolledPath.current = selectedPath;
    }
  }, [selectedPath, diffs.length]);

  return (
    <div className="diff-viewer">
      {error && <div className="diff-viewer-empty">{error}</div>}
      {!error && isLoading && diffs.length > 0 && (
        <div className="diff-viewer-loading">Refreshing diff...</div>
      )}
      {!error && !isLoading && !diffs.length && (
        <div className="diff-viewer-empty">No changes detected.</div>
      )}
      {!error &&
        diffs.map((entry) => {
          const isSelected = entry.path === selectedPath;
          const hasDiff = entry.diff.trim().length > 0;
          const language = languageFromPath(entry.path);
          return (
            <div
              key={entry.path}
              ref={(node) => {
                if (node) {
                  itemRefs.current.set(entry.path, node);
                } else {
                  itemRefs.current.delete(entry.path);
                }
              }}
              className={`diff-viewer-item ${isSelected ? "active" : ""}`}
            >
              <div className="diff-viewer-header">
                <span className="diff-viewer-status">{entry.status}</span>
                <span className="diff-viewer-path">{entry.path}</span>
              </div>
              {hasDiff ? (
                <div className="diff-viewer-output">
                  <DiffBlock diff={entry.diff} language={language} />
                </div>
              ) : (
                <div className="diff-viewer-placeholder">Diff unavailable.</div>
              )}
            </div>
          );
        })}
    </div>
  );
}
