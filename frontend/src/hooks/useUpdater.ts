import { useCallback, useEffect, useState } from "react";
import { isVelox } from "../services/velox";
import type { DebugEntry } from "../types";

type UpdateStage =
  | "idle"
  | "checking"
  | "available"
  | "downloading"
  | "installing"
  | "restarting"
  | "error";

type UpdateProgress = {
  totalBytes?: number;
  downloadedBytes: number;
};

export type UpdateState = {
  stage: UpdateStage;
  version?: string;
  progress?: UpdateProgress;
  error?: string;
};

type UseUpdaterOptions = {
  enabled?: boolean;
  onDebug?: (entry: DebugEntry) => void;
};

const supportsUpdater = false;

export function useUpdater({ enabled = true, onDebug }: UseUpdaterOptions) {
  const [state, setState] = useState<UpdateState>({ stage: "idle" });

  const resetToIdle = useCallback(async () => {
    setState({ stage: "idle" });
  }, []);

  const checkForUpdates = useCallback(async () => {
    if (!supportsUpdater) {
      setState({ stage: "idle" });
      return;
    }

    try {
      setState({ stage: "checking" });
      setState({ stage: "idle" });
    } catch (error) {
      const message =
        error instanceof Error ? error.message : JSON.stringify(error);
      onDebug?.({
        id: `${Date.now()}-client-updater-error`,
        timestamp: Date.now(),
        source: "error",
        label: "updater/error",
        payload: message,
      });
      setState({ stage: "error", error: message });
    }
  }, [onDebug]);

  const startUpdate = useCallback(async () => {
    if (!supportsUpdater) {
      setState({
        stage: "error",
        error: "Updates are not supported in this build.",
      });
      return;
    }

    try {
      setState({ stage: "restarting" });
    } catch (error) {
      const message =
        error instanceof Error ? error.message : JSON.stringify(error);
      onDebug?.({
        id: `${Date.now()}-client-updater-error`,
        timestamp: Date.now(),
        source: "error",
        label: "updater/error",
        payload: message,
      });
      setState((prev) => ({
        ...prev,
        stage: "error",
        error: message,
      }));
    }
  }, [onDebug]);

  useEffect(() => {
    if (!enabled || import.meta.env.DEV || !isVelox()) {
      return;
    }
    void checkForUpdates();
  }, [checkForUpdates, enabled]);

  return {
    state,
    startUpdate,
    dismiss: resetToIdle,
  };
}
