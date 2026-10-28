/**
 * 豆包 (www.doubao.com/chat) adapter
 * Probed 2026-10-28 on logged-in session.
 *
 * Input:  TipTap `.tiptap.ProseMirror[contenteditable=true]`
 *         wrapper `[data-testid="chat_input_input"]`
 * Send:   `[data-testid="chat_input_send_button"]` / `#flow-end-msg-send`
 *         （有字才出现；生成中 `.send-btn-wrapper` 带 `!hidden`）
 * Busy:   新 `receive_message` 尚无 `message_action_regenerate`，或正文仍在增长
 * Done:   末条 `[data-testid="receive_message"]` 出现
 *         `[data-testid="message_action_regenerate"]` + 正文稳定
 * Answer: `[data-testid="receive_message"] [data-testid="message_text_content"]`
 * New:    `button[aria-label="新对话"]`
 */
(function () {
  'use strict';
  if (!window.AIBridgeRuntime) {
    console.error('[AIBridge] runtime.js not loaded');
    return;
  }

  function sleep(ms) {
    return new Promise(function (r) {
      setTimeout(r, ms);
    });
  }

  function normalizeText(s) {
    return String(s || '')
      .replace(/\u00a0/g, ' ')
      .replace(/\r/g, '')
      .trim();
  }

  function visible(el) {
    if (!el) return false;
    var r = el.getBoundingClientRect();
    return r.width > 8 && r.height > 8;
  }

  function findInput() {
    var ce =
      document.querySelector('[data-testid="chat_input_input"] .tiptap.ProseMirror[contenteditable="true"]') ||
      document.querySelector('[data-testid="chat_input"] .tiptap.ProseMirror[contenteditable="true"]') ||
      document.querySelector('.tiptap.ProseMirror[contenteditable="true"]');
    return ce && visible(ce) ? ce : null;
  }

  function editorText(el) {
    return normalizeText(el ? el.innerText || el.textContent || '' : '');
  }

  function setTipTapText(el, text) {
    if (!el) return false;
    el.focus();
    try {
      document.execCommand('selectAll', false, null);
      document.execCommand('delete', false, null);
    } catch (e) { /* ignore */ }
    var ok = false;
    try {
      ok = document.execCommand('insertText', false, text);
    } catch (e2) {
      ok = false;
    }
    if (!ok || !editorText(el)) {
      var lines = String(text || '').split(/\n/);
      el.innerHTML = lines
        .map(function (line) {
          var esc = String(line || '')
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;');
          return '<p>' + (esc || '<br>') + '</p>';
        })
        .join('');
      el.dispatchEvent(
        new InputEvent('input', { bubbles: true, inputType: 'insertText', data: text })
      );
      var root = document.querySelector('[data-testid="chat_input_input"]');
      if (root) root.dispatchEvent(new Event('input', { bubbles: true }));
    }
    return editorText(el).length > 0;
  }

  function findSendButton() {
    var btn =
      document.querySelector('[data-testid="chat_input_send_button"]') ||
      document.querySelector('#flow-end-msg-send');
    if (!btn) return null;
    var wrap = btn.closest('.send-btn-wrapper');
    if (wrap) {
      var cls = (wrap.className || '').toString();
      if (cls.indexOf('!hidden') !== -1 || cls.indexOf(' hidden') !== -1) return null;
    }
    if (btn.getAttribute('aria-disabled') === 'true' || btn.getAttribute('data-disabled') === 'true') {
      return null;
    }
    return visible(btn) ? btn : null;
  }

  function clickElement(el) {
    if (!el) return false;
    try {
      el.click();
    } catch (e) {
      return false;
    }
    return true;
  }

  function pressEnter(el) {
    if (!el) return;
    el.focus();
    var opts = {
      key: 'Enter',
      code: 'Enter',
      keyCode: 13,
      which: 13,
      bubbles: true,
      cancelable: true,
      shiftKey: false
    };
    el.dispatchEvent(new KeyboardEvent('keydown', opts));
    el.dispatchEvent(new KeyboardEvent('keypress', opts));
    el.dispatchEvent(new KeyboardEvent('keyup', opts));
  }

  async function waitForSendButton(maxMs) {
    var deadline = Date.now() + (maxMs || 2500);
    while (Date.now() < deadline) {
      var btn = findSendButton();
      if (btn) return btn;
      await sleep(50);
    }
    return null;
  }

  function receiveMessages() {
    return AIBridgeRuntime.qsa('[data-testid="receive_message"]');
  }

  function lastReceive() {
    var list = receiveMessages();
    return list.length ? list[list.length - 1] : null;
  }

  function messageIdOf(item) {
    if (!item) return null;
    var n = item.querySelector('[data-message-id]');
    return n ? n.getAttribute('data-message-id') : null;
  }

  function extractAnswerFromItem(item) {
    if (!item) return '';
    var md =
      item.querySelector('[data-testid="message_text_content"]') ||
      item.querySelector('.md-box-root');
    if (!md) return '';
    var rich =
      (AIBridgeRuntime.richMarkdownFromElement && AIBridgeRuntime.richMarkdownFromElement(md)) || '';
    if (rich && rich.trim()) return rich.trim();
    return normalizeText(md.innerText || md.textContent || '');
  }

  function hasRegenerate(item) {
    if (!item) return false;
    return !!item.querySelector('[data-testid="message_action_regenerate"]');
  }

  function isSendHiddenBusy() {
    var wrap = document.querySelector('.send-btn-wrapper');
    if (!wrap) return false;
    var cls = (wrap.className || '').toString();
    return cls.indexOf('!hidden') !== -1;
  }

  function isGenerationComplete(baselineId, baselineCount) {
    var item = lastReceive();
    if (!item) return false;
    var id = messageIdOf(item);
    var count = receiveMessages().length;
    var isNew = (id && id !== baselineId) || count > baselineCount;
    if (!isNew) return false;
    var text = extractAnswerFromItem(item);
    if (!text) return false;
    // Prefer regenerate as done signal; fallback to action bar + stable caller
    if (hasRegenerate(item)) return true;
    if (item.querySelector('[data-testid="message_action_bar"]') && !isSendHiddenBusy()) {
      return true;
    }
    return false;
  }

  function findBusy() {
    if (isSendHiddenBusy()) return document.querySelector('.send-btn-wrapper') || document.body;
    var item = lastReceive();
    if (item && extractAnswerFromItem(item) && !hasRegenerate(item) && isSendHiddenBusy()) {
      return item;
    }
    return null;
  }

  async function sendPrompt(text) {
    text = text == null ? '' : String(text);
    var el = findInput();
    if (!el) return { ok: false, error: 'input not found' };
    if (!setTipTapText(el, text)) return { ok: false, error: 'setInput failed' };

    await sleep(80);
    var btn = await waitForSendButton(2500);
    var clicked = false;
    if (btn) {
      clicked = clickElement(btn);
    } else {
      pressEnter(el);
      await sleep(80);
      btn = findSendButton();
      if (btn) clicked = clickElement(btn);
      else clicked = true;
    }

    await sleep(150);
    if (editorText(el).length && findSendButton()) {
      clickElement(findSendButton());
    }

    return { ok: true, clicked: clicked };
  }

  function readLastAssistant() {
    var item = lastReceive();
    var text = item ? extractAnswerFromItem(item) : '';
    return {
      text: text,
      count: receiveMessages().length,
      messageId: messageIdOf(item),
      complete: item ? hasRegenerate(item) : false
    };
  }

  AIBridgeRuntime.install({
    id: 'doubao',
    matchHosts: ['www.doubao.com', 'doubao.com'],
    inputSelector: '.tiptap.ProseMirror, [data-testid="chat_input_input"]',
    sendSelector: '[data-testid="chat_input_send_button"], #flow-end-msg-send',
    assistantSelector: '[data-testid="receive_message"] [data-testid="message_text_content"]',
    busySelector: null,
    loggedIn: function () {
      return !!findInput();
    },
    setInput: function (el, text) {
      return setTipTapText(findInput() || el, text);
    },
    clickSend: function () {
      var btn = findSendButton();
      return btn ? clickElement(btn) : false;
    },
    isBusy: function () {
      return !!findBusy();
    },
    newChat: function () {
      var btns = AIBridgeRuntime.qsa('button, [role="button"], a');
      for (var i = 0; i < btns.length; i++) {
        var aria = normalizeText(btns[i].getAttribute('aria-label') || '');
        var t = normalizeText(btns[i].innerText || '');
        if (aria === '新对话' || t === '新对话' || /^新对话/.test(t)) {
          btns[i].click();
          return { ok: true };
        }
      }
      return { ok: false, error: 'new chat control not found' };
    }
  });

  var api = window.__MeoAIBridge;

  api.send = function (text) {
    text = text == null ? '' : String(text);
    var el = findInput();
    if (!el) return { ok: false, error: 'input not found' };
    if (!setTipTapText(el, text)) return { ok: false, error: 'setInput failed' };
    var btn = findSendButton();
    if (btn) clickElement(btn);
    else pressEnter(el);
    return { ok: true };
  };

  api.readLastAssistant = readLastAssistant;

  api.sendAndWait = async function (text, opts) {
    opts = opts || {};
    var timeoutMs = opts.timeoutMs != null ? opts.timeoutMs : 180000;
    var stableMs = opts.stableMs != null ? opts.stableMs : 1000;
    var baselineCount = receiveMessages().length;
    var baselineId = messageIdOf(lastReceive());
    var baselineText = readLastAssistant().text;

    var sent = await sendPrompt(text);
    if (!sent.ok) return { ok: false, phase: 'send', error: sent.error, sendMeta: sent };

    var start = Date.now();
    var sawStart = false;
    var lastText = '';
    var lastChange = 0;
    var doneSince = 0;

    while (Date.now() - start < timeoutMs) {
      var count = receiveMessages().length;
      var item = lastReceive();
      var id = messageIdOf(item);
      var curText = extractAnswerFromItem(item);
      var complete = isGenerationComplete(baselineId, baselineCount);
      var busy = isSendHiddenBusy();

      if (busy || count > baselineCount || (id && id !== baselineId)) sawStart = true;

      if (!complete) {
        doneSince = 0;
        if (curText !== lastText) {
          lastText = curText;
          lastChange = Date.now();
        }
        await sleep(300);
        continue;
      }

      if (!curText) {
        doneSince = 0;
        await sleep(300);
        continue;
      }

      var isNew =
        count > baselineCount ||
        (id && id !== baselineId) ||
        (curText && curText !== baselineText);
      if (!isNew && !sawStart) {
        await sleep(300);
        continue;
      }

      if (curText !== lastText) {
        lastText = curText;
        lastChange = Date.now();
        doneSince = Date.now();
      } else if (!doneSince) {
        doneSince = Date.now();
      }

      var stableFor = Date.now() - Math.max(lastChange || doneSince, doneSince);
      if (stableFor >= stableMs && isGenerationComplete(baselineId, baselineCount)) {
        return {
          ok: true,
          text: curText,
          sawBusy: sawStart,
          count: count,
          messageId: id,
          sendMeta: sent,
          complete: true
        };
      }
      await sleep(300);
    }

    var finalItem = lastReceive();
    var finalText = extractAnswerFromItem(finalItem);
    if (isGenerationComplete(baselineId, baselineCount) && finalText) {
      return {
        ok: true,
        text: finalText,
        sawBusy: sawStart,
        count: receiveMessages().length,
        messageId: messageIdOf(finalItem),
        sendMeta: sent,
        soft: true
      };
    }

    return {
      ok: false,
      error: 'timeout',
      text: finalText || '',
      sawBusy: sawStart,
      count: receiveMessages().length,
      sendMeta: sent,
      complete: isGenerationComplete(baselineId, baselineCount)
    };
  };

  api.probe = function () {
    var input = findInput();
    var host = location.hostname || '';
    var hostOk = host.indexOf('doubao') !== -1;
    var send = findSendButton();
    var last = lastReceive();
    return {
      ok: !!(hostOk && input),
      id: 'doubao',
      host: host,
      hostOk: hostOk,
      loggedIn: !!input,
      hasInput: !!input,
      hasSend: !!send,
      editorTextLen: input ? editorText(input).length : 0,
      responseCount: receiveMessages().length,
      lastMessageId: messageIdOf(last),
      hasRegenerate: last ? hasRegenerate(last) : false,
      lastAnswerPreview: (extractAnswerFromItem(last) || '').slice(0, 80),
      busy: !!findBusy(),
      href: location.href || '',
      detail: !hostOk ? 'host mismatch' : !input ? 'input not found (login?)' : 'ok'
    };
  };

  console.info('[AIBridge] doubao adapter installed', api.probe());
})();
