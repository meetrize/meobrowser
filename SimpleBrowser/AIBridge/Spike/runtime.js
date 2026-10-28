/**
 * Meo AI Bridge — page runtime (BR-0 Spike)
 * Contract: window.__MeoAIBridge
 *
 * Adapters call AIBridgeRuntime.install({ ...selectors, setInput?, clickSend? })
 */
(function (global) {
  'use strict';

  var DEFAULT_STABLE_MS = 800;
  var DEFAULT_TIMEOUT_MS = 120000;

  function qs(sel, root) {
    if (!sel) return null;
    try {
      return (root || document).querySelector(sel);
    } catch (e) {
      return null;
    }
  }

  function qsa(sel, root) {
    if (!sel) return [];
    try {
      return Array.prototype.slice.call((root || document).querySelectorAll(sel));
    } catch (e) {
      return [];
    }
  }

  /** Set value on React/Vue-friendly controlled inputs. */
  function nativeSetValue(el, value) {
    if (!el) return false;
    var tag = (el.tagName || '').toLowerCase();
    el.focus();

    if (tag === 'textarea' || (tag === 'input' && el.type !== 'file')) {
      var proto = tag === 'textarea' ? window.HTMLTextAreaElement.prototype : window.HTMLInputElement.prototype;
      var desc = Object.getOwnPropertyDescriptor(proto, 'value');
      if (desc && desc.set) {
        desc.set.call(el, value);
      } else {
        el.value = value;
      }
      el.dispatchEvent(new InputEvent('input', { bubbles: true, data: value, inputType: 'insertText' }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
      return true;
    }

    if (el.isContentEditable || el.getAttribute('contenteditable') === 'true') {
      el.textContent = value;
      el.dispatchEvent(new InputEvent('input', { bubbles: true, data: value, inputType: 'insertText' }));
      return true;
    }

    return false;
  }

  function pressEnter(el) {
    if (!el) return;
    var opts = { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true };
    el.dispatchEvent(new KeyboardEvent('keydown', opts));
    el.dispatchEvent(new KeyboardEvent('keypress', opts));
    el.dispatchEvent(new KeyboardEvent('keyup', opts));
  }

  function textOf(el) {
    if (!el) return '';
    return (el.innerText || el.textContent || '').trim();
  }

  function sleep(ms) {
    return new Promise(function (resolve) {
      setTimeout(resolve, ms);
    });
  }

  /**
   * @param {object} cfg
   * @param {string} [cfg.id]
   * @param {string|string[]} [cfg.matchHosts]
   * @param {string} cfg.inputSelector
   * @param {string} [cfg.sendSelector]
   * @param {string} cfg.assistantSelector
   * @param {string} [cfg.busySelector]
   * @param {string} [cfg.newChatSelector]
   * @param {function():boolean} [cfg.loggedIn]
   * @param {function(HTMLElement,string):boolean} [cfg.setInput]
   * @param {function():boolean} [cfg.clickSend]
   */
  function install(cfg) {
    cfg = cfg || {};
    var aborted = false;

    function inputEl() {
      return qs(cfg.inputSelector);
    }

    function busy() {
      if (typeof cfg.isBusy === 'function') return !!cfg.isBusy();
      if (!cfg.busySelector) return false;
      var el = qs(cfg.busySelector);
      if (!el) return false;
      var style = window.getComputedStyle(el);
      if (style && (style.display === 'none' || style.visibility === 'hidden' || style.opacity === '0')) {
        return false;
      }
      return true;
    }

    function assistants() {
      return qsa(cfg.assistantSelector).filter(function (el) {
        return textOf(el).length > 0;
      });
    }

    function readLastAssistant() {
      var list = assistants();
      var el = list.length ? list[list.length - 1] : null;
      return {
        text: textOf(el),
        messageId: el ? el.getAttribute('data-message-id') || null : null,
        count: list.length
      };
    }

    function probe() {
      var host = location.hostname || '';
      var hosts = cfg.matchHosts
        ? Array.isArray(cfg.matchHosts)
          ? cfg.matchHosts
          : [cfg.matchHosts]
        : null;
      var hostOk = !hosts || hosts.some(function (h) {
        return host === h || host.endsWith('.' + h);
      });
      var input = inputEl();
      var loggedIn = typeof cfg.loggedIn === 'function' ? !!cfg.loggedIn() : true;
      return {
        ok: !!(hostOk && input && loggedIn),
        id: cfg.id || 'unknown',
        host: host,
        hostOk: !!hostOk,
        loggedIn: loggedIn,
        hasInput: !!input,
        hasSend: !!(cfg.sendSelector && qs(cfg.sendSelector)),
        assistantCount: assistants().length,
        busy: busy(),
        href: location.href || '',
        detail: !hostOk ? 'host mismatch' : !input ? 'input not found' : !loggedIn ? 'not logged in' : 'ok'
      };
    }

    function send(text) {
      aborted = false;
      text = text == null ? '' : String(text);
      var el = inputEl();
      if (!el) return { ok: false, error: 'input not found' };

      var okSet = typeof cfg.setInput === 'function' ? cfg.setInput(el, text) : nativeSetValue(el, text);
      if (!okSet) return { ok: false, error: 'setInput failed' };

      var clicked = false;
      if (typeof cfg.clickSend === 'function') {
        clicked = !!cfg.clickSend();
      } else if (cfg.sendSelector) {
        var btn = qs(cfg.sendSelector);
        if (btn && !btn.disabled) {
          btn.click();
          clicked = true;
        }
      }
      if (!clicked) {
        pressEnter(el);
      }
      return { ok: true };
    }

    function waitComplete(opts) {
      opts = opts || {};
      var timeoutMs = opts.timeoutMs != null ? opts.timeoutMs : DEFAULT_TIMEOUT_MS;
      var stableMs = opts.stableMs != null ? opts.stableMs : DEFAULT_STABLE_MS;
      // Prefer caller-supplied baseline taken BEFORE send (avoids fast-reply race).
      var baseline = opts.baseline || readLastAssistant();
      var start = Date.now();
      var lastText = baseline.text;
      var lastChange = Date.now();
      var sawBusy = false;
      var sawGrowth = false;

      return new Promise(function (resolve) {
        (async function loop() {
          while (!aborted) {
            var now = Date.now();
            if (now - start > timeoutMs) {
              resolve({ ok: false, error: 'timeout', text: readLastAssistant().text });
              return;
            }
            var b = busy();
            if (b) sawBusy = true;
            var cur = readLastAssistant();
            if (cur.text && (cur.count > baseline.count || cur.text !== baseline.text)) {
              if (cur.text !== lastText) {
                lastText = cur.text;
                lastChange = now;
              }
              sawGrowth = true;
            }
            var idle = !b && sawGrowth && now - lastChange >= stableMs;
            var idleNoBusySignal =
              typeof cfg.isBusy !== 'function' &&
              !cfg.busySelector &&
              sawGrowth &&
              now - lastChange >= stableMs;
            if (idle || idleNoBusySignal) {
              resolve({ ok: true, text: cur.text, sawBusy: sawBusy });
              return;
            }
            await sleep(200);
          }
          resolve({ ok: false, error: 'aborted', text: readLastAssistant().text });
        })();
      });
    }

    /** Race-safe helper: snapshot → send → wait. */
    function sendAndWait(text, opts) {
      opts = opts || {};
      var baseline = readLastAssistant();
      var sent = send(text);
      if (!sent.ok) {
        return Promise.resolve({ ok: false, phase: 'send', error: sent.error });
      }
      return waitComplete({
        timeoutMs: opts.timeoutMs,
        stableMs: opts.stableMs,
        baseline: baseline
      });
    }

    function newChat() {
      if (typeof cfg.newChat === 'function') return cfg.newChat();
      if (!cfg.newChatSelector) return { ok: false, error: 'no newChatSelector' };
      var el = qs(cfg.newChatSelector);
      if (!el) return { ok: false, error: 'newChat control not found' };
      el.click();
      return { ok: true };
    }

    var api = {
      probe: probe,
      send: send,
      isBusy: busy,
      readLastAssistant: readLastAssistant,
      waitComplete: waitComplete,
      sendAndWait: sendAndWait,
      newChat: newChat,
      abort: function () {
        aborted = true;
      },
      _cfg: cfg,
      _nativeSetValue: nativeSetValue
    };

    global.__MeoAIBridge = api;
    return api;
  }

  global.AIBridgeRuntime = {
    install: install,
    nativeSetValue: nativeSetValue,
    qs: qs,
    qsa: qsa
  };
})(typeof window !== 'undefined' ? window : this);
