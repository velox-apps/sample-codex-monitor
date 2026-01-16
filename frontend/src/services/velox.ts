type VeloxEvent<T> = {
  event: string;
  payload: T;
  id: string;
  timestamp: number;
};

type VeloxEventBridge = {
  listen: (event: string, handler: (event: VeloxEvent<any>) => void) => string;
  once: (event: string, handler: (event: VeloxEvent<any>) => void) => string;
  unlisten: (id: string) => boolean;
  removeAllListeners: (event?: string) => void;
  emit: (event: string, payload?: unknown) => Promise<unknown>;
  _emit: (event: string, payload: unknown, id?: string, timestamp?: number) => void;
};

type VeloxInvokeBridge = {
  invoke: <T = unknown>(command: string, args?: Record<string, unknown>) => Promise<T>;
};

type VeloxGlobal = {
  invoke: <T = unknown>(command: string, args?: Record<string, unknown>) => Promise<T>;
  event: {
    listen: (event: string, handler: (event: VeloxEvent<any>) => void) => string;
    once: (event: string, handler: (event: VeloxEvent<any>) => void) => string;
    unlisten: (id: string) => void;
    emit: (event: string, payload?: unknown) => Promise<unknown>;
  };
};

function ensureVeloxEvents() {
  if (typeof window === "undefined" || window.__VELOX_EVENTS__) {
    return;
  }

  const listeners = new Map<
    string,
    { handler: (event: VeloxEvent<any>) => void; once: boolean; id: string }[]
  >();
  let idCounter = 0;

  const buildId = () => `evt_${Date.now()}_${idCounter++}`;

  const listen = (eventName: string, handler: (event: VeloxEvent<any>) => void) => {
    const id = buildId();
    const list = listeners.get(eventName) ?? [];
    list.push({ handler, once: false, id });
    listeners.set(eventName, list);
    return id;
  };

  const once = (eventName: string, handler: (event: VeloxEvent<any>) => void) => {
    const id = buildId();
    const list = listeners.get(eventName) ?? [];
    list.push({ handler, once: true, id });
    listeners.set(eventName, list);
    return id;
  };

  const unlisten = (id: string) => {
    for (const [eventName, handlers] of listeners) {
      const idx = handlers.findIndex((entry) => entry.id === id);
      if (idx !== -1) {
        handlers.splice(idx, 1);
        if (handlers.length === 0) {
          listeners.delete(eventName);
        } else {
          listeners.set(eventName, handlers);
        }
        return true;
      }
    }
    return false;
  };

  const removeAllListeners = (eventName?: string) => {
    if (eventName) {
      listeners.delete(eventName);
    } else {
      listeners.clear();
    }
  };

  const emit = async (eventName: string, payload?: unknown) => {
    const response = await fetch("ipc://localhost/__velox_event__", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ event: eventName, payload }),
    });
    return response.json();
  };

  const _emit = (
    eventName: string,
    payload: unknown,
    id: string = buildId(),
    timestamp: number = Date.now(),
  ) => {
    const event = { event: eventName, payload, id, timestamp };
    const handlers = listeners.get(eventName) ?? [];
    const pending = handlers.slice();
    pending.forEach((entry) => {
      entry.handler(event);
      if (entry.once) {
        unlisten(entry.id);
      }
    });
  };

  const bridge: VeloxEventBridge = {
    listen,
    once,
    unlisten,
    removeAllListeners,
    emit,
    _emit,
  };

  window.__VELOX_EVENTS__ = bridge;
  window.Velox = window.Velox || {};
  window.Velox.event = {
    listen: (event, handler) => bridge.listen(event, handler),
    once: (event, handler) => bridge.once(event, handler),
    unlisten: (id) => {
      bridge.unlisten(id);
    },
    emit: (event, payload) => bridge.emit(event, payload),
  };
}

function ensureVeloxInvoke() {
  if (typeof window === "undefined" || window.__VELOX_INVOKE__) {
    return;
  }

  const pending = new Map<string, { resolve: (value: unknown) => void; reject: (error: Error) => void }>();
  const earlyResponses = new Map<string, any>();
  let listenerReady = false;
  let listenerReadyPromise: Promise<void> | null = null;

  const handleInvokePayload = (payload: any, entry: { resolve: (value: unknown) => void; reject: (error: Error) => void }) => {
    if (payload?.ok) {
      let result: unknown = null;
      if (payload.resultJSON) {
        try {
          result = JSON.parse(payload.resultJSON);
        } catch {
          result = null;
        }
      }
      entry.resolve(result);
    } else {
      const message = payload?.error?.message ?? "Command failed";
      const err = new Error(message);
      (err as any).code = payload?.error?.code;
      entry.reject(err);
    }
  };

  const registerListener = () => {
    if (listenerReady || !window.__VELOX_EVENTS__?.listen) {
      return listenerReady;
    }
    window.__VELOX_EVENTS__.listen("__velox_invoke_response__", (event) => {
      const payload = event?.payload ?? {};
      const id = payload?.id;
      if (!id) {
        return;
      }
      const entry = pending.get(id);
      if (!entry) {
        earlyResponses.set(id, payload);
        return;
      }
      pending.delete(id);
      handleInvokePayload(payload, entry);
    });
    listenerReady = true;
    return true;
  };

  const ensureListener = () => {
    if (listenerReady) {
      return Promise.resolve();
    }
    if (listenerReadyPromise) {
      return listenerReadyPromise;
    }
    listenerReadyPromise = new Promise((resolve) => {
      const tryRegister = () => {
        if (registerListener()) {
          resolve();
          return true;
        }
        return false;
      };
      if (!tryRegister()) {
        const timer = setInterval(() => {
          if (tryRegister()) {
            clearInterval(timer);
          }
        }, 50);
      }
    });
    return listenerReadyPromise;
  };

  const invoke = async (command: string, args: Record<string, unknown> = {}) => {
    await ensureListener();
    const response = await fetch(`ipc://localhost/${command}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(args),
    });
    const text = await response.text();
    if (!response.ok) {
      let message = `Command failed: ${command}`;
      try {
        const err = JSON.parse(text);
        if (err?.message) {
          message = err.message;
        }
      } catch {
        // Ignore parse failures.
      }
      throw new Error(message);
    }
    if (!text) {
      return null;
    }
    let data: any = null;
    try {
      data = JSON.parse(text);
    } catch {
      return null;
    }
    const result = data?.result ?? null;
    if (result?.__veloxPending && result.id) {
      return new Promise((resolve, reject) => {
        const entry = { resolve, reject };
        pending.set(result.id, entry);
        const early = earlyResponses.get(result.id);
        if (early) {
          earlyResponses.delete(result.id);
          pending.delete(result.id);
          handleInvokePayload(early, entry);
        }
      });
    }
    return result;
  };

  window.__VELOX_INVOKE__ = { invoke } as VeloxInvokeBridge;
  window.Velox = window.Velox || {};
  if (typeof window.Velox.invoke !== "function") {
    window.Velox.invoke = invoke;
  }
}

function ensureVeloxBridge() {
  ensureVeloxEvents();
  ensureVeloxInvoke();
}

function requireVelox(): VeloxGlobal {
  ensureVeloxBridge();
  if (typeof window === "undefined" || !window.Velox || !window.Velox.invoke) {
    throw new Error("Velox runtime not available");
  }
  return window.Velox as VeloxGlobal;
}

export function isVelox() {
  ensureVeloxBridge();
  return typeof window !== "undefined" && !!window.Velox?.invoke;
}

export async function invoke<T>(command: string, args: Record<string, unknown> = {}) {
  return requireVelox().invoke<T>(command, args);
}

export async function listen<T>(eventName: string, handler: (event: VeloxEvent<T>) => void) {
  const velox = requireVelox();
  const id = velox.event.listen(eventName, handler as (event: VeloxEvent<any>) => void);
  return () => {
    velox.event.unlisten(id);
  };
}

type DialogOpenOptions = {
  directory?: boolean;
  multiple?: boolean;
  title?: string;
  defaultPath?: string;
  filters?: { name: string; extensions: string[] }[];
};

type DialogAskOptions = {
  title?: string;
  message: string;
  kind?: string;
  okLabel?: string;
  cancelLabel?: string;
};

export async function open(options: DialogOpenOptions) {
  return invoke<string[] | null>("plugin:dialog:open", options);
}

export async function ask(
  messageOrOptions: string | DialogAskOptions,
  legacyOptions?: Omit<DialogAskOptions, "message">,
) {
  const options: DialogAskOptions =
    typeof messageOrOptions === "string"
      ? { message: messageOrOptions, ...(legacyOptions ?? {}) }
      : messageOrOptions;
  const payload = { title: options.title, message: options.message };
  try {
    return await invoke<boolean>("plugin:dialog:ask", payload);
  } catch {
    if (typeof window !== "undefined" && typeof window.confirm === "function") {
      return window.confirm(options.message);
    }
    return false;
  }
}

export async function openUrl(url: string) {
  return invoke<boolean>("plugin:opener:openUrl", { url });
}

export async function revealItemInDir(path: string) {
  return invoke<boolean>("plugin:opener:revealPath", { path });
}

export async function relaunch() {
  await invoke("plugin:process:relaunch");
}

export async function getVersion() {
  return invoke<string>("app_version");
}

export class LogicalPosition {
  x: number;
  y: number;

  constructor(x: number, y: number) {
    this.x = x;
    this.y = y;
  }
}

type MenuItemOptions = {
  text: string;
  action?: () => void | Promise<void>;
};

export class MenuItem {
  text: string;
  action?: () => void | Promise<void>;

  constructor(options: MenuItemOptions) {
    this.text = options.text;
    this.action = options.action;
  }

  static async new(options: MenuItemOptions) {
    return new MenuItem(options);
  }
}

type MenuOptions = {
  items: MenuItem[];
};

let activeMenu: HTMLDivElement | null = null;
let activeCleanup: (() => void) | null = null;

function ensureMenuStyles() {
  const id = "velox-context-menu-style";
  if (document.getElementById(id)) {
    return;
  }
  const style = document.createElement("style");
  style.id = id;
  style.textContent = `
    .velox-context-menu {
      position: fixed;
      min-width: 160px;
      background: rgba(24, 24, 24, 0.98);
      border: 1px solid rgba(255, 255, 255, 0.08);
      border-radius: 10px;
      box-shadow: 0 12px 24px rgba(0, 0, 0, 0.35);
      padding: 6px;
      z-index: 9999;
      color: #f3f3f3;
      font-size: 13px;
    }
    .velox-context-menu button {
      display: block;
      width: 100%;
      background: transparent;
      border: none;
      color: inherit;
      text-align: left;
      padding: 8px 12px;
      border-radius: 6px;
      cursor: pointer;
      font: inherit;
    }
    .velox-context-menu button:hover {
      background: rgba(255, 255, 255, 0.08);
    }
  `;
  document.head.appendChild(style);
}

function closeMenu() {
  if (activeCleanup) {
    activeCleanup();
    activeCleanup = null;
  }
  if (activeMenu) {
    activeMenu.remove();
    activeMenu = null;
  }
}

export class Menu {
  items: MenuItem[];

  constructor(options: MenuOptions) {
    this.items = options.items;
  }

  static async new(options: MenuOptions) {
    return new Menu(options);
  }

  async popup(position: LogicalPosition, _window?: unknown) {
    ensureMenuStyles();
    closeMenu();

    const menu = document.createElement("div");
    menu.className = "velox-context-menu";

    this.items.forEach((item) => {
      const button = document.createElement("button");
      button.type = "button";
      button.textContent = item.text;
      button.addEventListener("click", async () => {
        closeMenu();
        await item.action?.();
      });
      menu.appendChild(button);
    });

    const maxLeft = window.innerWidth - 180;
    const maxTop = window.innerHeight - 120;
    const left = Math.max(8, Math.min(position.x, maxLeft));
    const top = Math.max(8, Math.min(position.y, maxTop));

    menu.style.left = `${left}px`;
    menu.style.top = `${top}px`;

    document.body.appendChild(menu);
    activeMenu = menu;

    const handlePointer = (event: MouseEvent) => {
      if (activeMenu && !activeMenu.contains(event.target as Node)) {
        closeMenu();
      }
    };

    const cleanup = () => {
      window.removeEventListener("mousedown", handlePointer);
      window.removeEventListener("scroll", closeMenu, true);
      window.removeEventListener("resize", closeMenu);
    };

    window.addEventListener("mousedown", handlePointer);
    window.addEventListener("scroll", closeMenu, true);
    window.addEventListener("resize", closeMenu);
    activeCleanup = cleanup;
  }
}

export function getCurrentWindow() {
  return {
    label: "main",
    startDragging: async () => {
      await invoke("window_start_dragging");
    },
  };
}
