/**
 * ChatGPT (chatgpt.com) adapter
 * Probed 2026-10-28 logged-in (新 UI：无 data-message-author-role / .markdown)。
 *
 * Input:  TipTap/ProseMirror `.ProseMirror[contenteditable=true]`（aria-label「询问 ChatGPT」）
 * Send:   `button[aria-label="发送"]` / `Send`（有字才出现）
 * Busy:   `button[aria-label="停止"]` / `Stop…`
 * Done:   停止消失 + `button[aria-label="重新生成回复"]` + 正文稳定
 * Answer: `[data-markdown-text-style="assistant-message"]`
 * New:    `button`「新聊天」
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
      document.querySelector(
        '.ProseMirror[contenteditable="true"][role="textbox"]'
      ) ||
      document.querySelector(
        '[contenteditable="true"][aria-label*="ChatGPT"]'
      ) ||
      document.querySelector('#prompt-textarea') ||
      document.querySelector('.ProseMirror[contenteditable="true"]');
    return ce && visible(ce) ? ce : null;
  }

  function editorText(el) {
    return normalizeText(el ? el.innerText || el.textContent || '' : '');
  }

  function setComposerText(el, text) {
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
    }
    return editorText(el).length > 0;
  }

  function findSendButton() {
    if (findStopButton()) return null;
    var btns = document.querySelectorAll('button');
    for (var i = 0; i < btns.length; i++) {
      var aria = btns[i].getAttribute('aria-label') || '';
      if (
        aria === '发送' ||
        aria === 'Send' ||
        /^Send message$/i.test(aria)
      ) {
        if (
          visible(btns[i]) &&
          btns[i].getAttribute('aria-disabled') !== 'true' &&
          !btns[i].disabled
        ) {
          return btns[i];
        }
      }
    }
    var byTest =
      document.querySelector('[data-testid="send-button"]') ||
      document.querySelector('[data-testid="composer-send-button"]');
    if (byTest && visible(byTest) && byTest.getAttribute('aria-disabled') !== 'true') {
      return byTest;
    }
    return null;
  }

  function findStopButton() {
    var btns = document.querySelectorAll('button');
    for (var i = 0; i < btns.length; i++) {
      var aria = btns[i].getAttribute('aria-label') || '';
      if (
        aria === '停止' ||
        /^Stop( streaming| generating)?$/i.test(aria) ||
        /停止(生成|回答)?/.test(aria)
      ) {
        if (visible(btns[i])) return btns[i];
      }
    }
    var byTest = document.querySelector('[data-testid="stop-button"]');
    return byTest && visible(byTest) ? byTest : null;
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

  function assistantNodes() {
    var list = AIBridgeRuntime.qsa('[data-markdown-text-style="assistant-message"]');
    if (list.length) return list;
    // fallback legacy
    return AIBridgeRuntime.qsa(
      '[data-message-author-role="assistant"] .markdown, [data-message-author-role="assistant"]'
    );
  }

  function lastAssistant() {
    var list = assistantNodes();
    return list.length ? list[list.length - 1] : null;
  }

  function extractAnswerFromItem(item) {
    if (!item) return '';
    return normalizeText(item.innerText || item.textContent || '');
  }

  function hasRegenerate() {
    var btns = document.querySelectorAll('button');
    for (var i = 0; i < btns.length; i++) {
      var aria = btns[i].getAttribute('aria-label') || '';
      if (
        (aria === '重新生成回复' || /Regenerate/i.test(aria)) &&
        visible(btns[i])
      ) {
        return true;
      }
    }
    return false;
  }

  function isGenerationComplete(baselineCount) {
    if (findStopButton()) return false;
    var item = lastAssistant();
    if (!item) return false;
    var count = assistantNodes().length;
    if (count <= baselineCount) return false;
    var text = extractAnswerFromItem(item);
    if (!text) return false;
    if (hasRegenerate()) return true;
    return true;
  }

  function findBusy() {
    var stop = findStopButton();
    if (stop) return stop;
    return null;
  }

  async function sendPrompt(text) {
    text = text == null ? '' : String(text);
    var el = findInput();
    if (!el) return { ok: false, error: 'input not found' };
    if (!setComposerText(el, text)) return { ok: false, error: 'setInput failed' };

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
    var item = lastAssistant();
    var text = item ? extractAnswerFromItem(item) : '';
    return {
      text: text,
      count: assistantNodes().length,
      messageId: null,
      complete: !findStopButton() && !!text
    };
  }

  AIBridgeRuntime.install({
    id: 'chatgpt',
    matchHosts: ['chatgpt.com', 'chat.openai.com'],
    inputSelector: '.ProseMirror[contenteditable="true"], #prompt-textarea',
    sendSelector: 'button[aria-label="发送"], button[aria-label="Send"]',
    assistantSelector: '[data-markdown-text-style="assistant-message"]',
    busySelector: null,
    loggedIn: function () {
      return !!findInput();
    },
    setInput: function (el, text) {
      return setComposerText(findInput() || el, text);
    },
    clickSend: function () {
      var btn = findSendButton();
      return btn ? clickElement(btn) : false;
    },
    isBusy: function () {
      return !!findBusy();
    },
    newChat: function () {
      var btns = AIBridgeRuntime.qsa('button, a, [role="button"]');
      for (var i = 0; i < btns.length; i++) {
        var aria = normalizeText(btns[i].getAttribute('aria-label') || '');
        var t = normalizeText(btns[i].innerText || '');
        if (
          aria === '新聊天' ||
          t === '新聊天' ||
          aria === 'New chat' ||
          t === 'New chat'
        ) {
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
    if (!setComposerText(el, text)) return { ok: false, error: 'setInput failed' };
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
    var baselineCount = assistantNodes().length;
    var baselineText = readLastAssistant().text;

    var sent = await sendPrompt(text);
    if (!sent.ok) return { ok: false, phase: 'send', error: sent.error, sendMeta: sent };

    var start = Date.now();
    var sawStart = false;
    var lastText = '';
    var lastChange = 0;
    var doneSince = 0;

    while (Date.now() - start < timeoutMs) {
      var busy = !!findBusy();
      var count = assistantNodes().length;
      var curText = extractAnswerFromItem(lastAssistant());
      var complete = isGenerationComplete(baselineCount);

      if (busy || count > baselineCount) sawStart = true;

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

      var isNew = count > baselineCount || (curText && curText !== baselineText);
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
      if (stableFor >= stableMs && isGenerationComplete(baselineCount)) {
        return {
          ok: true,
          text: curText,
          sawBusy: sawStart,
          count: count,
          sendMeta: sent,
          complete: true
        };
      }
      await sleep(300);
    }

    var finalText = extractAnswerFromItem(lastAssistant());
    if (isGenerationComplete(baselineCount) && finalText) {
      return {
        ok: true,
        text: finalText,
        sawBusy: sawStart,
        count: assistantNodes().length,
        sendMeta: sent,
        soft: true
      };
    }

    return {
      ok: false,
      error: 'timeout',
      text: finalText || '',
      sawBusy: sawStart,
      count: assistantNodes().length,
      sendMeta: sent,
      complete: isGenerationComplete(baselineCount)
    };
  };

  api.probe = function () {
    var input = findInput();
    var host = location.hostname || '';
    var hostOk =
      host.indexOf('chatgpt.com') !== -1 || host.indexOf('openai.com') !== -1;
    var send = findSendButton();
    var last = lastAssistant();
    return {
      ok: !!(hostOk && input),
      id: 'chatgpt',
      host: host,
      hostOk: hostOk,
      loggedIn: !!input,
      hasInput: !!input,
      hasSend: !!send,
      editorTextLen: input ? editorText(input).length : 0,
      responseCount: assistantNodes().length,
      lastAnswerPreview: (extractAnswerFromItem(last) || '').slice(0, 80),
      busy: !!findBusy(),
      hasStop: !!findStopButton(),
      hasRegenerate: hasRegenerate(),
      href: location.href || '',
      detail: !hostOk ? 'host mismatch' : !input ? 'input not found (login?)' : 'ok'
    };
  };

  console.info('[AIBridge] chatgpt adapter installed', api.probe());
})();
