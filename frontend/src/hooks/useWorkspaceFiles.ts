import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { DebugEntry, WorkspaceInfo } from "../types";
import { getWorkspaceFiles } from "../services/tauri";

type UseWorkspaceFilesOptions = {
  activeWorkspace: WorkspaceInfo | null;
  onDebug?: (entry: DebugEntry) => void;
};

export function useWorkspaceFiles({
  activeWorkspace,
  onDebug,
}: UseWorkspaceFilesOptions) {
  const [files, setFiles] = useState<string[]>([]);
  const lastFetchedWorkspaceId = useRef<string | null>(null);
  const inFlight = useRef(false);

  const workspaceId = activeWorkspace?.id ?? null;
  const isConnected = Boolean(activeWorkspace?.connected);

  const refreshFiles = useCallback(async () => {
    if (!workspaceId || !isConnected) {
      return;
    }
    if (inFlight.current) {
      return;
    }
    inFlight.current = true;
    onDebug?.({
      id: `${Date.now()}-client-files-list`,
      timestamp: Date.now(),
      source: "client",
      label: "files/list",
      payload: { workspaceId },
    });
    try {
      const response = await getWorkspaceFiles(workspaceId);
      onDebug?.({
        id: `${Date.now()}-server-files-list`,
        timestamp: Date.now(),
        source: "server",
        label: "files/list response",
        payload: response,
      });
      setFiles(Array.isArray(response) ? response : []);
      lastFetchedWorkspaceId.current = workspaceId;
    } catch (error) {
      onDebug?.({
        id: `${Date.now()}-client-files-list-error`,
        timestamp: Date.now(),
        source: "error",
        label: "files/list error",
        payload: error instanceof Error ? error.message : String(error),
      });
    } finally {
      inFlight.current = false;
    }
  }, [isConnected, onDebug, workspaceId]);

  useEffect(() => {
    if (!workspaceId || !isConnected) {
      return;
    }
    if (lastFetchedWorkspaceId.current === workspaceId && files.length > 0) {
      return;
    }
    refreshFiles();
  }, [files.length, isConnected, refreshFiles, workspaceId]);

  const fileOptions = useMemo(() => files.filter(Boolean), [files]);

  return {
    files: fileOptions,
    refreshFiles,
  };
}
