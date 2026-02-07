import Foundation

/// JavaScript compatibility shim that bridges the Tauri JS API surface
/// (`window.__TAURI_INTERNALS__`) to the Velox bridge (`window.Velox`).
/// Injected after the Velox bridge scripts so the unmodified React frontend
/// (which imports from `@tauri-apps/api`) continues to work.
enum TauriCompat {
  static let shimScript: String = """
  (function() {
    if (window.__TAURI_INTERNALS__) return;

    // --------------- callback registry (transformCallback) ----------------
    var _cbId = 0;
    var _cbs = {};

    function transformCallback(cb, once) {
      var id = '__tcb_' + (++_cbId);
      _cbs[id] = function() {
        var args = arguments;
        if (once) delete _cbs[id];
        if (cb) return cb.apply(null, args);
      };
      return id;
    }

    // --------------- event system bridge ----------------
    // Maps Velox listener IDs to unlisten functions for cleanup
    var _veloxListenerIds = {};
    var _tauriEventId = 0;

    function tauriListen(event, handlerRef) {
      // handlerRef is a callback ID string from transformCallback
      var realHandler = (typeof handlerRef === 'function')
        ? handlerRef
        : _cbs[handlerRef];

      if (!realHandler) {
        console.warn('[TauriCompat] No handler found for', handlerRef);
        return Promise.resolve(0);
      }

      var eventId = ++_tauriEventId;

      // Register directly with Velox's native event system so that
      // backend _emit() calls reach us.
      if (window.Velox && window.Velox.event && window.Velox.event.listen) {
        var veloxId = window.Velox.event.listen(event, function(veloxEvent) {
          // Convert Velox event shape {name, payload, id, timestamp}
          // to Tauri event shape {event, payload, id}
          try {
            if (event === 'app-server-event') {
              var msg = veloxEvent.payload && veloxEvent.payload.message;
              console.log('[TauriCompat] app-server-event method=' +
                (msg && msg.method) + ' params=' + JSON.stringify(msg && msg.params));
            }
            realHandler({
              event: veloxEvent.name || event,
              payload: veloxEvent.payload,
              id: veloxEvent.id || eventId
            });
          } catch(e) {
            console.error('[TauriCompat] Event handler error:', e);
          }
        });
        _veloxListenerIds[eventId] = veloxId;
      }

      return Promise.resolve(eventId);
    }

    function tauriUnlisten(event, eventId) {
      var veloxId = _veloxListenerIds[eventId];
      if (veloxId != null && window.Velox && window.Velox.event) {
        window.Velox.event.unlisten(veloxId);
      }
      delete _veloxListenerIds[eventId];
    }

    function tauriEmit(event, payload) {
      // Emit to backend via Velox
      if (window.Velox && window.Velox.event && window.Velox.event.emit) {
        return window.Velox.event.emit(event, payload);
      }
    }

    // --------------- invoke bridge ----------------
    function tauriInvoke(cmd, args, options) {
      // Handle plugin-style commands
      if (cmd === 'plugin:event|listen') {
        return tauriListen(args.event, args.handler);
      }
      if (cmd === 'plugin:event|unlisten') {
        tauriUnlisten(args.event, args.eventId);
        return Promise.resolve();
      }
      if (cmd === 'plugin:event|emit') {
        tauriEmit(args.event, args.payload);
        return Promise.resolve();
      }

      if (cmd === 'plugin:dialog|open') {
        var opts = args && args.options ? args.options : (args || {});
        return window.Velox.invoke(cmd, args || {}).then(function(result) {
          if (!opts || opts.multiple) return result;
          if (Array.isArray(result)) {
            return result.length > 0 ? result[0] : null;
          }
          return result;
        });
      }

      // Delegate to Velox invoke
      if (window.Velox && window.Velox.invoke) {
        return window.Velox.invoke(cmd, args || {});
      }

      return Promise.reject(new Error('Velox bridge not available'));
    }

    // --------------- __TAURI_INTERNALS__ ----------------
    window.__TAURI_INTERNALS__ = {
      invoke: tauriInvoke,
      transformCallback: transformCallback,
      unregisterCallback: function(id) {
        delete _cbs[id];
      },
      metadata: {
        currentWindow: { label: 'main' },
        currentWebview: { label: 'main' },
        windows: [{ label: 'main' }],
        webviews: [{ label: 'main', windowLabel: 'main' }]
      },
      convertFileSrc: function(path, protocol) {
        protocol = protocol || 'asset';
        return protocol + '://localhost/' + encodeURIComponent(path);
      }
    };

    // --------------- event plugin internals ----------------
    // Required by @tauri-apps/api/event _unlisten() to clean up listeners
    window.__TAURI_EVENT_PLUGIN_INTERNALS__ = {
      unregisterListener: function(event, eventId) {
        tauriUnlisten(event, eventId);
      }
    };

    // --------------- __TAURI__ namespace ----------------
    // The @tauri-apps/api package checks for window.__TAURI__ to detect
    // it is running inside Tauri.
    window.__TAURI__ = window.__TAURI__ || {};
    window.__TAURI__.__INVOKE_KEY__ = window.__TAURI__.__INVOKE_KEY__ || 'velox-compat';

    // Provide event helpers at the expected paths for @tauri-apps/api/event
    window.__TAURI__.event = {
      listen: function(event, handler) {
        // This path is called directly by code that uses @tauri-apps/api/event
        // without going through invoke. The handler here is the real function.
        return tauriListen(event, handler);
      },
      emit: tauriEmit,
      TauriEvent: {
        WINDOW_CLOSE_REQUESTED: 'tauri://close-requested'
      }
    };

    // Provide the core at the expected path
    window.__TAURI__.core = {
      invoke: tauriInvoke,
      transformCallback: transformCallback
    };

    // Also expose under path
    window.__TAURI__.path = window.__TAURI__.path || {};
    window.__TAURI__.window = window.__TAURI__.window || {};
  })();
  """
}
