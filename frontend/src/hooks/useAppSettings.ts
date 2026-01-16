import { useCallback, useEffect, useState } from "react";
import type { AppSettings } from "../types";
import { getAppSettings, runCodexDoctor, updateAppSettings } from "../services/tauri";

const defaultSettings: AppSettings = {
  codexBin: null,
  defaultAccessMode: "current",
};

export function useAppSettings() {
  const [settings, setSettings] = useState<AppSettings>(defaultSettings);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    let active = true;
    void (async () => {
      try {
        const response = await getAppSettings();
        if (active) {
          setSettings({
            ...defaultSettings,
            ...response,
          });
        }
      } finally {
        if (active) {
          setIsLoading(false);
        }
      }
    })();
    return () => {
      active = false;
    };
  }, []);

  const saveSettings = useCallback(async (next: AppSettings) => {
    const saved = await updateAppSettings(next);
    setSettings({
      ...defaultSettings,
      ...saved,
    });
    return saved;
  }, []);

  const doctor = useCallback(async (codexBin: string | null) => {
    return runCodexDoctor(codexBin);
  }, []);

  return {
    settings,
    setSettings,
    saveSettings,
    doctor,
    isLoading,
  };
}
