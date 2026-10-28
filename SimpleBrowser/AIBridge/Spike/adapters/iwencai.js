/**
 * 同花顺问财 (www.iwencai.com/chat) adapter
 * Probed 2026-10-28；复测修复：完成后 `.chat-thinking-loading` 会残留为
 * `chat-thinking-summary-icon`，不可再当作 busy。
 *
 * Input:  Quill `.ql-editor[contenteditable=true]` (#footInput)
 * Send:   `.chat-input-bottom-right-button.send-button`
 * Busy:   仅文案「停止回答」（不要用 .chat-thinking-loading）
 * Done:   `.chat-thinking-title` 含「模型答案生成完成」+ markdown 有正文
 * Answer: `.chat-response-message-container .rich-text-container.aime-markdown`
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
      document.querySelector('#footInput .ql-editor[contenteditable="true"]') ||
      document.querySelector('.chat-input-text .ql-editor[contenteditable="true"]') ||
      document.querySelector('.ql-editor[contenteditable="true"]');
    return ce && visible(ce) ? ce : null;
  }

  function editorText(el) {
    return normalizeText(el ? el.innerText || el.textContent || '' : '');
  }

  function escapeHtml(s) {
    return String(s || '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  }

  function setQuillText(el, text) {
    if (!el) return false;
    el.focus();
    try {
      document.execCommand('selectAll', false, null);
      document.execCommand('delete', false, null);
    } catch (e) { /* ignore */ }
    el.classList.remove('ql-blank');
    var ok = false;
    try {
      ok = document.execCommand('insertText', false, text);
    } catch (e2) {
      ok = false;
    }
    if (!ok || !editorText(el)) {
      // Quill often needs structured HTML + input event
      var lines = String(text || '').split(/\n/);
      el.innerHTML = lines
        .map(function (line) {
          return '<p>' + (escapeHtml(line) || '<br>') + '</p>';
        })
        .join('');
      el.dispatchEvent(
        new InputEvent('input', { bubbles: true, inputType: 'insertText', data: text })
      );
      var root = document.querySelector('#footInput');
      if (root) root.dispatchEvent(new Event('input', { bubbles: true }));
    }
    return editorText(el).length > 0;
  }

  function findSendButton() {
    var btn = document.querySelector('.chat-input-bottom-right-button.send-button');
    if (btn && visible(btn)) return btn;
    return null;
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

  function findStopControl() {
    // 仅认可见「停止回答」文案。
    // 注意：完成后仍可能有 `.chat-thinking-loading.chat-thinking-summary-icon`，不能当 busy。
    var prefer = document.querySelectorAll(
      '.thinking-interrupt, .chat-thinking-header button, button, [class*="interrupt"], [class*="stop"]'
    );
    for (var i = 0; i < prefer.length; i++) {
      var t = normalizeText(prefer[i].innerText || prefer[i].getAttribute('aria-label') || '');
      if ((t === '停止回答' || /^停止回答/.test(t)) && visible(prefer[i])) return prefer[i];
    }
    var all = document.querySelectorAll('div, span, button, a');
    for (var j = 0; j < all.length; j++) {
      var el = all[j];
      // 只匹配短文本节点，避免父容器把整段回答算进来
      var raw = normalizeText(el.innerText || '');
      if (raw === '停止回答' && visible(el) && el.children.length === 0) return el;
      if (raw === '停止回答' && visible(el) && (el.innerText || '').length <= 8) return el;
    }
    return null;
  }

  function responseItems() {
    return AIBridgeRuntime.qsa('.chat-response-message-container');
  }

  function lastResponseItem() {
    var list = responseItems();
    return list.length ? list[list.length - 1] : null;
  }

  function hasAnswerComplete(item) {
    if (!item) return false;
    var title = item.querySelector('.chat-thinking-title, .chat-thinking-header');
    var t = normalizeText((title && title.innerText) || item.innerText || '');
    return /模型答案生成完成/.test(t);
  }

  function extractAnswerFromItem(item) {
    if (!item) return '';
    var md =
      item.querySelector('.rich-text-container.aime-markdown') ||
      item.querySelector('.aime-markdown') ||
      item.querySelector('.rich-text-container');
    if (!md) return '';
    var text = normalizeText(md.innerText || md.textContent || '');
    // strip status headers if leaked
    text = text
      .replace(/^问财\s*模型答案生成完成\s*/g, '')
      .replace(/^已快速推理[^\n]*\n?/g, '')
      .trim();
    if (!text) return '';
    if (/^(停止回答|模型答案生成完成|已快速推理)/.test(text) && text.length < 30) return '';
    return text;
  }

  function isGenerationComplete() {
    // 「停止回答」仍可见 → 未完成
    if (findStopControl()) return false;
    var item = lastResponseItem();
    if (!item) return false;
    if (!hasAnswerComplete(item)) return false;
    var answer = extractAnswerFromItem(item);
    return !!(answer && answer.length >= 1);
  }

  function findBusy() {
    var stop = findStopControl();
    if (stop) return stop;
    var item = lastResponseItem();
    // 已有回复容器但尚未「模型答案生成完成」
    if (item && !hasAnswerComplete(item)) return item;
    return null;
  }

  async function sendPrompt(text) {
    text = text == null ? '' : String(text);
    var el = findInput();
    if (!el) return { ok: false, error: 'input not found' };
    if (!setQuillText(el, text)) return { ok: false, error: 'setInput failed' };

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
      else clicked = true; // Enter path
    }

    await sleep(150);
    if (editorText(el).length && findSendButton()) {
      clickElement(findSendButton());
      pressEnter(el);
    }

    return { ok: true, clicked: clicked };
  }

  function readLastAssistant() {
    var item = lastResponseItem();
    var text = item ? extractAnswerFromItem(item) : '';
    return {
      text: text,
      count: responseItems().length,
      messageId: null,
      complete: isGenerationComplete()
    };
  }

  AIBridgeRuntime.install({
    id: 'iwencai',
    matchHosts: ['www.iwencai.com', 'iwencai.com'],
    inputSelector: '#footInput .ql-editor, .ql-editor',
    sendSelector: '.chat-input-bottom-right-button.send-button',
    assistantSelector: '.chat-response-message-container .rich-text-container.aime-markdown',
    busySelector: null,
    loggedIn: function () {
      return !!findInput();
    },
    setInput: function (el, text) {
      return setQuillText(findInput() || el, text);
    },
    clickSend: function () {
      var btn = findSendButton();
      return btn ? clickElement(btn) : false;
    },
    isBusy: function () {
      return !!findBusy();
    },
    newChat: function () {
      var links = AIBridgeRuntime.qsa('a, button, [role="button"], div, span');
      for (var i = 0; i < links.length; i++) {
        var t = normalizeText(links[i].innerText || links[i].getAttribute('aria-label') || '');
        if (t === '新对话' || /^\+?\s*新对话$/.test(t)) {
          links[i].click();
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
    if (!setQuillText(el, text)) return { ok: false, error: 'setInput failed' };
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
    var baselineCount = responseItems().length;
    var baselineText = readLastAssistant().text;

    var sent = await sendPrompt(text);
    if (!sent.ok) return { ok: false, phase: 'send', error: sent.error, sendMeta: sent };

    var start = Date.now();
    var sawStart = false;
    var lastText = '';
    var lastChange = 0;
    var doneSince = 0;

    while (Date.now() - start < timeoutMs) {
      var stop = !!findBusy();
      var count = responseItems().length;
      var complete = isGenerationComplete();
      var curText = extractAnswerFromItem(lastResponseItem());

      if (stop || count > baselineCount) sawStart = true;

      if (!complete) {
        doneSince = 0;
        lastText = curText;
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
      if (stableFor >= stableMs && isGenerationComplete()) {
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

    var finalText = extractAnswerFromItem(lastResponseItem());
    if (isGenerationComplete() && finalText) {
      return {
        ok: true,
        text: finalText,
        sawBusy: sawStart,
        count: responseItems().length,
        sendMeta: sent,
        soft: true
      };
    }

    return {
      ok: false,
      error: 'timeout',
      text: finalText || '',
      sawBusy: sawStart,
      count: responseItems().length,
      sendMeta: sent,
      complete: isGenerationComplete()
    };
  };

  api.probe = function () {
    var input = findInput();
    var host = location.hostname || '';
    var hostOk = host.indexOf('iwencai') !== -1;
    var send = findSendButton();
    var last = lastResponseItem();
    return {
      ok: !!(hostOk && input),
      id: 'iwencai',
      host: host,
      hostOk: hostOk,
      loggedIn: !!input,
      hasInput: !!input,
      hasSend: !!send,
      editorTextLen: input ? editorText(input).length : 0,
      responseCount: responseItems().length,
      answerComplete: last ? hasAnswerComplete(last) : false,
      lastAnswerPreview: (extractAnswerFromItem(last) || '').slice(0, 80),
      busy: !!findBusy(),
      href: location.href || '',
      detail: !hostOk ? 'host mismatch' : !input ? 'input not found (login?)' : 'ok'
    };
  };

  console.info('[AIBridge] iwencai adapter installed', api.probe());
})();
