export {};

declare global {
  interface Window {
    __VELOX_EVENTS__?: {
      listen: (event: string, handler: (event: { event: string; payload: any; id: string; timestamp: number }) => void) => string;
      once: (event: string, handler: (event: { event: string; payload: any; id: string; timestamp: number }) => void) => string;
      unlisten: (id: string) => boolean;
      removeAllListeners: (event?: string) => void;
      emit: (event: string, payload?: unknown) => Promise<unknown>;
      _emit: (event: string, payload: unknown, id?: string, timestamp?: number) => void;
    };
    __VELOX_INVOKE__?: {
      invoke: <T = unknown>(command: string, args?: Record<string, unknown>) => Promise<T>;
    };
    Velox?: {
      invoke: <T = unknown>(command: string, args?: Record<string, unknown>) => Promise<T>;
      event: {
        listen: (event: string, handler: (event: { event: string; payload: any; id: string; timestamp: number }) => void) => string;
        once: (event: string, handler: (event: { event: string; payload: any; id: string; timestamp: number }) => void) => string;
        unlisten: (id: string) => void;
        emit: (event: string, payload?: unknown) => Promise<unknown>;
      };
    };
  }
}
