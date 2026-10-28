/**
 * Kimi (kimi.moonshot.cn / www.kimi.com) heuristic adapter.
 * Selectors are best-effort — revise after live probe on a logged-in tab.
 */
(function () {
  'use strict';
  if (!window.AIBridgeRuntime) {
    console.error('[AIBridge] runtime.js not loaded');
    return;
  }

  function findInput() {
    var sels = [
      'textarea[placeholder*="Kimi"]',
      'textarea[placeholder*="问"]',
      'div[contenteditable="true"][role="textbox"]',
      'textarea'
    ];
    for (var s = 0; s < sels.length; s++) {
      var list = AIBridgeRuntime.qsa(sels[s]);
      for (var i = 0; i < list.length; i++) {
        var el = list[i];
        var r = el.getBoundingClientRect();
        if (r.width > 40 && r.height > 16) return el;
      }
    }
    return null;
  }

  function findSendButton() {
    var cands = AIBridgeRuntime.qsa(
      'button[aria-label*="发送"], button[aria-label*="Send"], button[type="submit"], [data-testid*="send"]'
    );
    for (var i = 0; i < cands.length; i++) {
      var b = cands[i];
      var r = b.getBoundingClientRect();
      if (r.width > 0 && r.height > 0 && !b.disabled) return b;
    }
    var input = findInput();
    if (input) {
      var root = input.closest('form') || input.parentElement || document;
      var near = root.querySelectorAll('button, [role="button"]');
      for (var j = near.length - 1; j >= 0; j--) {
        var el = near[j];
        var rr = el.getBoundingClientRect();
        if (rr.width > 20 && rr.height > 20) return el;
      }
    }
    return null;
  }

  function findBusy() {
    var nodes = AIBridgeRuntime.qsa('button, [role="button"]');
    for (var i = 0; i < nodes.length; i++) {
      var b = nodes[i];
      var label = ((b.getAttribute('aria-label') || '') + ' ' + (b.innerText || '')).toLowerCase();
      if (/停止|stop|取消生成/.test(label)) {
        var r = b.getBoundingClientRect();
        if (r.width > 0 && r.height > 0) return b;
      }
    }
    return null;
  }

  function assistantNodes() {
    return AIBridgeRuntime.qsa(
      '[data-role="assistant"], .chat-content-item-assistant, .markdown-body, .kimimarkdown, .segment-assistant'
    ).filter(function (el) {
      return ((el.innerText || '').trim().length > 0);
    });
  }

  function readLastAssistant() {
    var list = assistantNodes();
    var el = list.length ? list[list.length - 1] : null;
    return {
      text: el ? (el.innerText || '').trim() : '',
      count: list.length,
      messageId: null
    };
  }

  AIBridgeRuntime.install({
    id: 'kimi',
    matchHosts: ['kimi.moonshot.cn', 'www.kimi.com', 'kimi.com'],
    inputSelector: 'textarea',
    sendSelector: null,
    assistantSelector: '.markdown-body',
    busySelector: null,
    loggedIn: function () {
      return !!findInput();
    },
    setInput: function (el, text) {
      var target = findInput() || el;
      if (target && target.isContentEditable) {
        target.focus();
        target.textContent = text;
        target.dispatchEvent(new InputEvent('input', { bubbles: true }));
        return true;
      }
      return AIBridgeRuntime.nativeSetValue(target, text);
    },
    clickSend: function () {
      var btn = findSendButton();
      if (!btn) return false;
      btn.click();
      return true;
    },
    isBusy: function () {
      return !!findBusy();
    },
    newChat: function () {
      var links = AIBridgeRuntime.qsa('a, button, [role="button"]');
      for (var i = 0; i < links.length; i++) {
        var t = (links[i].innerText || links[i].getAttribute('aria-label') || '').trim();
        if (/新对话|新会话|new chat/i.test(t)) {
          links[i].click();
          return { ok: true };
        }
      }
      return { ok: false, error: 'new chat control not found' };
    }
  });

  var api = window.__MeoAIBridge;
  api.readLastAssistant = readLastAssistant;

  api.sendAndWait = async function (text, opts) {
    opts = opts || {};
    var timeoutMs = opts.timeoutMs != null ? opts.timeoutMs : 120000;
    var stableMs = opts.stableMs != null ? opts.stableMs : 1000;
    var baseline = readLastAssistant();
    var sent = api.send(text);
    if (!sent.ok) return { ok: false, phase: 'send', error: sent.error };

    var start = Date.now();
    var lastText = baseline.text;
    var lastChange = Date.now();
    var sawGrowth = false;
    var sawBusy = false;

    while (Date.now() - start < timeoutMs) {
      if (api.isBusy()) sawBusy = true;
      var cur = readLastAssistant();
      if (cur.text && (cur.count > baseline.count || cur.text !== baseline.text)) {
        if (cur.text !== lastText) {
          lastText = cur.text;
          lastChange = Date.now();
        }
        sawGrowth = true;
      }
      if (sawGrowth && !api.isBusy() && Date.now() - lastChange >= stableMs) {
        return { ok: true, text: cur.text, sawBusy: sawBusy, count: cur.count };
      }
      await new Promise(function (r) {
        setTimeout(r, 250);
      });
    }
    return {
      ok: false,
      error: 'timeout',
      text: readLastAssistant().text,
      sawBusy: sawBusy,
      count: readLastAssistant().count
    };
  };

  api.probe = function () {
    var input = findInput();
    var host = location.hostname || '';
    var hostOk =
      host.indexOf('kimi') !== -1 ||
      host.indexOf('moonshot') !== -1;
    var send = findSendButton();
    return {
      ok: !!(hostOk && input),
      id: 'kimi',
      host: host,
      hostOk: hostOk,
      loggedIn: !!input,
      hasInput: !!input,
      hasSend: !!send,
      assistantCount: assistantNodes().length,
      busy: !!findBusy(),
      href: location.href || '',
      detail: !hostOk ? 'host mismatch' : !input ? 'input not found (login?)' : 'ok'
    };
  };

  console.info('[AIBridge] kimi adapter installed', api.probe());
})();
