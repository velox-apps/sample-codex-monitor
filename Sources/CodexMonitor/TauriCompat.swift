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
    var _listeners = {};
    var _listenerId = 0;

    function tauriListen(event, handler) {
      var id = ++_listenerId;
      if (!_listeners[event]) _listeners[event] = {};
      _listeners[event][id] = handler;

      if (window.Velox && window.Velox.event && window.Velox.event.listen) {
        window.Velox.event.listen(event, handler);
      }

      return Promise.resolve(function unlisten() {
        if (_listeners[event]) delete _listeners[event][id];
      });
    }

    function tauriUnlisten(event, handlerId) {
      if (_listeners[event]) delete _listeners[event][handlerId];
    }

    function tauriEmit(event, payload) {
      var handlers = _listeners[event];
      if (handlers) {
        Object.keys(handlers).forEach(function(id) {
          try { handlers[id]({ event: event, payload: payload }); } catch(e) {}
        });
      }
    }

    // Hook into Velox event system for backend→frontend events
    if (window.Velox && window.Velox.event && window.Velox.event.listen) {
      var origVeloxListen = window.Velox.event.listen.bind(window.Velox.event);
      // Patch Velox listen to also notify Tauri-style listeners
      window.Velox.event._patchedListen = origVeloxListen;
    }

    // --------------- invoke bridge ----------------
    function tauriInvoke(cmd, args, options) {
      // Handle plugin-style commands
      if (cmd === 'plugin:event|listen') {
        return tauriListen(args.event, args.handler);
      }
      if (cmd === 'plugin:event|unlisten') {
        return Promise.resolve();
      }
      if (cmd === 'plugin:event|emit') {
        tauriEmit(args.event, args.payload);
        return Promise.resolve();
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

    // --------------- __TAURI__ namespace ----------------
    // The @tauri-apps/api package checks for window.__TAURI__ to detect
    // it is running inside Tauri.
    window.__TAURI__ = window.__TAURI__ || {};
    window.__TAURI__.__INVOKE_KEY__ = window.__TAURI__.__INVOKE_KEY__ || 'velox-compat';

    // Provide event helpers at the expected paths for @tauri-apps/api/event
    window.__TAURI__.event = {
      listen: tauriListen,
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

    // --------------- global event dispatch from Velox ----------------
    // When Velox emits events, forward them to the Tauri listener registry
    if (window.Velox && window.Velox.event) {
      var origEmit = window.Velox.event.emit;
      window.Velox.event.emit = function(event, payload) {
        tauriEmit(event, payload);
        if (origEmit) return origEmit.call(window.Velox.event, event, payload);
      };
    }
  })();
  """
}
