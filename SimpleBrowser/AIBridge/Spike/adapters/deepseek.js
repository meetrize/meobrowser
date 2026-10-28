/**
 * DeepSeek web chat adapter (chat.deepseek.com)
 * Revised 2026-10-28 after live probe on logged-in session.
 *
 * Findings:
 * - Composer: textarea[placeholder*="DeepSeek"]
 * - Send control: DIV.ds-button--primary (not <button>, often no aria-label)
 * - Assistant bubble: .ds-markdown.ds-assistant-message-main-content (inside .ds-message)
 * - Do NOT use .ds-markdown-paragraph alone (last paragraph ≠ whole reply)
 * - waitComplete must snapshot baseline BEFORE send (fast replies race otherwise)
 */
(function () {
  'use strict';
  if (!window.AIBridgeRuntime) {
    console.error('[AIBridge] runtime.js not loaded');
    return;
  }

  function findInput() {
    var list = AIBridgeRuntime.qsa('textarea');
    for (var i = 0; i < list.length; i++) {
      var el = list[i];
      var r = el.getBoundingClientRect();
      if (r.width > 40 && r.height > 16) return el;
    }
    return null;
  }

  function composerRoot(input) {
    if (!input) return document;
    return (
      input.closest('.aaff8b8f') ||
      input.closest('[class*="composer"]') ||
      input.parentElement && input.parentElement.parentElement && input.parentElement.parentElement.parentElement ||
      document
    );
  }

  function findSendButton() {
    var input = findInput();
    var root = composerRoot(input);
    var cands = AIBridgeRuntime.qsa('.ds-button--primary, .ds-button--filled', root);
    for (var i = 0; i < cands.length; i++) {
      var b = cands[i];
      var r = b.getBoundingClientRect();
      if (r.width > 0 && r.height > 0) return b;
    }
    // broader fallback near textarea
    if (input && input.parentElement) {
      var near = input.parentElement.parentElement || input.parentElement;
      var all = near.querySelectorAll('.ds-button, [role="button"]');
      for (var j = all.length - 1; j >= 0; j--) {
        var el = all[j];
        var rr = el.getBoundingClientRect();
        if (rr.width > 20 && rr.height > 20) return el;
      }
    }
    return null;
  }

  function findBusy() {
    // Stop control often replaces send during generation
    var input = findInput();
    var root = composerRoot(input);
    var nodes = AIBridgeRuntime.qsa('.ds-button, [role="button"], button', root);
    for (var i = 0; i < nodes.length; i++) {
      var b = nodes[i];
      var label = (
        (b.getAttribute('aria-label') || '') +
        ' ' +
        (b.innerText || '') +
        ' ' +
        (b.className || '')
      ).toLowerCase();
      if (/停止|stop/.test(label)) {
        var r = b.getBoundingClientRect();
        if (r.width > 0 && r.height > 0) return b;
      }
    }
    return null;
  }

  function assistantNodes() {
    return AIBridgeRuntime.qsa(
      '.ds-markdown.ds-assistant-message-main-content, .ds-message .ds-markdown.ds-assistant-message-main-content'
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
    id: 'deepseek',
    matchHosts: ['chat.deepseek.com'],
    inputSelector: 'textarea',
    sendSelector: null,
    assistantSelector: '.ds-markdown.ds-assistant-message-main-content',
    busySelector: null,
    newChatSelector: null,
    loggedIn: function () {
      return !!findInput();
    },
    setInput: function (el, text) {
      var target = findInput() || el;
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
        if (/开启新对话|新对话|新聊天|new chat/i.test(t)) {
          links[i].click();
          return { ok: true };
        }
      }
      return { ok: false, error: 'new chat control not found' };
    }
  });

  var api = window.__MeoAIBridge;
  api.readLastAssistant = readLastAssistant;

  // Race-safe: capture baseline before send, then wait
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
    var hostOk = host === 'chat.deepseek.com' || host.endsWith('.deepseek.com');
    var send = findSendButton();
    return {
      ok: !!(hostOk && input),
      id: 'deepseek',
      host: host,
      hostOk: hostOk,
      loggedIn: !!input,
      hasInput: !!input,
      hasSend: !!send,
      sendClass: send ? String(send.className || '').slice(0, 80) : null,
      assistantCount: assistantNodes().length,
      busy: !!findBusy(),
      href: location.href || '',
      detail: !hostOk ? 'host mismatch' : !input ? 'input not found (login?)' : 'ok'
    };
  };

  console.info('[AIBridge] deepseek adapter installed', api.probe());
})();
