/**
 * Google Gemini (gemini.google.com/app) adapter
 * Probed 2026-10-28 guest；复测登录态（meetrice / Gemini 自动）同日通过。
 *
 * Input:  Quill `.ql-editor[contenteditable=true]`（aria-label「为 Gemini 输入提示」）
 * Send:   `button[aria-label="发送"]` / `Send`；容器 `[data-test-id="send-button-container"]`
 * Busy:   `button[aria-label="停止回答"]` / `Stop responding`
 * Done:   停止消失 + `[data-test-id="regenerate-button"]` 出现 + 正文稳定
 * Answer: `model-response .markdown-main-panel` / `message-content .markdown`
 * New:    「发起新对话」/ `[data-testid="reset-button"]`
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
        'rich-textarea .ql-editor[contenteditable="true"]:not(.ql-clipboard)'
      ) ||
      document.querySelector(
        '.ql-editor.textarea[contenteditable="true"]:not(.ql-clipboard)'
      ) ||
      document.querySelector(
        '.ql-editor[contenteditable="true"][aria-label]:not(.ql-clipboard)'
      ) ||
      document.querySelector('.ql-editor[contenteditable="true"]:not(.ql-clipboard)');
    return ce && visible(ce) ? ce : null;
  }

  function editorText(el) {
    return normalizeText(el ? el.innerText || el.textContent || '' : '');
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
    // While generating, stop replaces send — never treat stop as send
    if (findStopButton()) return null;
    var sels = [
      'button[aria-label="发送"]',
      'button[aria-label="Send message"]',
      'button[aria-label="Send"]',
      'gem-icon-button.send-button.has-input button',
      'gem-icon-button.send-button button',
      '[data-test-id="send-button-container"] button[aria-label]'
    ];
    for (var i = 0; i < sels.length; i++) {
      var btn = document.querySelector(sels[i]);
      if (!btn) continue;
      var aria = (btn.getAttribute('aria-label') || '').toLowerCase();
      if (/停止|stop/.test(aria)) continue;
      if (!/^发送$|^send( message)?$/i.test(aria) && sels[i].indexOf('aria-label') !== -1) {
        // allow non-aria selectors below
      }
      if (btn.getAttribute('aria-disabled') === 'true' || btn.disabled) continue;
      if (visible(btn)) return btn;
    }
    var gem = document.querySelector(
      'gem-icon-button.send-button.has-input, gem-icon-button.send-button.submit'
    );
    if (gem && visible(gem) && gem.getAttribute('aria-disabled') !== 'true') return gem;
    return null;
  }

  function findStopButton() {
    var candidates = [
      document.querySelector('button[aria-label="停止回答"]'),
      document.querySelector('button[aria-label="Stop responding"]'),
      document.querySelector('button[aria-label="Stop"]'),
      document.querySelector('button[aria-label*="停止"]')
    ];
    for (var i = 0; i < candidates.length; i++) {
      if (candidates[i] && visible(candidates[i])) return candidates[i];
    }
    return null;
  }

  function hasRegenerate(item) {
    if (!item) return false;
    return !!(
      item.querySelector('[data-test-id="regenerate-button"]') ||
      item.querySelector('[data-testid="regenerate-button"]')
    );
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

  function modelResponses() {
    return AIBridgeRuntime.qsa('model-response');
  }

  function lastModelResponse() {
    var list = modelResponses();
    return list.length ? list[list.length - 1] : null;
  }

  function stripGeminiPrefix(text) {
    return normalizeText(text)
      .replace(/^Gemini\s*说\s*/i, '')
      .replace(/^Gemini\s*said\s*/i, '')
      .replace(/^Gemini\s*/i, '')
      .trim();
  }

  function extractAnswerFromItem(item) {
    if (!item) return '';
    var md =
      item.querySelector('.markdown.markdown-main-panel') ||
      item.querySelector('.markdown-main-panel') ||
      item.querySelector('message-content .markdown') ||
      item.querySelector('.md-content') ||
      item.querySelector('.markdown') ||
      item.querySelector('message-content') ||
      item.querySelector('.model-response-text');
    var raw = '';
    if (md) {
      raw =
        (AIBridgeRuntime.richMarkdownFromElement && AIBridgeRuntime.richMarkdownFromElement(md)) ||
        md.innerText ||
        md.textContent ||
        '';
    } else {
      raw = item.innerText || item.textContent || '';
    }
    raw = String(raw)
      .replace(/\n?登录即可关联到[^\n]*/g, '')
      .replace(/\n?Sign in to[^\n]*/gi, '');
    return stripGeminiPrefix(raw);
  }

  function isTypingStatus() {
    var t = document.body ? document.body.innerText || '' : '';
    return /Gemini\s*正在输入|is typing|Generating/i.test(t);
  }

  function isRepliedStatus() {
    var t = document.body ? document.body.innerText || '' : '';
    return /Gemini\s*已回复|Response complete|Finished responding/i.test(t);
  }

  function isGenerationComplete(baselineCount) {
    if (findStopButton()) return false;
    if (isTypingStatus()) return false;
    var item = lastModelResponse();
    if (!item) return false;
    var count = modelResponses().length;
    if (count <= baselineCount) return false;
    var text = extractAnswerFromItem(item);
    if (!text) return false;
    // Logged-in: regenerate appears when finished（比「已回复」文案更稳）
    if (hasRegenerate(item)) return true;
    if (isRepliedStatus()) return true;
    return true;
  }

  function findBusy() {
    var stop = findStopButton();
    if (stop && visible(stop)) return stop;
    if (isTypingStatus()) return document.body;
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
      else clicked = true;
    }

    await sleep(150);
    if (editorText(el).length && findSendButton()) {
      clickElement(findSendButton());
    }

    return { ok: true, clicked: clicked };
  }

  function readLastAssistant() {
    var item = lastModelResponse();
    var text = item ? extractAnswerFromItem(item) : '';
    return {
      text: text,
      count: modelResponses().length,
      messageId: null,
      complete: !findStopButton() && !!text
    };
  }

  AIBridgeRuntime.install({
    id: 'gemini',
    matchHosts: ['gemini.google.com', 'bard.google.com'],
    inputSelector: 'rich-textarea .ql-editor, .ql-editor.textarea',
    sendSelector: 'button[aria-label="发送"], button[aria-label="Send"], gem-icon-button.send-button',
    assistantSelector: 'model-response',
    busySelector: null,
    loggedIn: function () {
      // Guest can chat; treat input presence as ready
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
      var reset = document.querySelector('[data-testid="reset-button"]');
      if (reset) {
        reset.click();
        return { ok: true };
      }
      var links = AIBridgeRuntime.qsa('a, button, [role="button"]');
      for (var i = 0; i < links.length; i++) {
        var t = normalizeText(
          (links[i].getAttribute('aria-label') || '') + ' ' + (links[i].innerText || '')
        );
        if (/发起新对话|New chat|新对话/.test(t)) {
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
    var baselineCount = modelResponses().length;
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
      var count = modelResponses().length;
      var curText = extractAnswerFromItem(lastModelResponse());
      var complete = isGenerationComplete(baselineCount);

      if (busy || count > baselineCount || isTypingStatus()) sawStart = true;

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
      // Prefer replied status + stable, or just stable after stop gone
      if (
        stableFor >= stableMs &&
        isGenerationComplete(baselineCount) &&
        (isRepliedStatus() || !findStopButton())
      ) {
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

    var finalText = extractAnswerFromItem(lastModelResponse());
    if (isGenerationComplete(baselineCount) && finalText) {
      return {
        ok: true,
        text: finalText,
        sawBusy: sawStart,
        count: modelResponses().length,
        sendMeta: sent,
        soft: true
      };
    }

    return {
      ok: false,
      error: 'timeout',
      text: finalText || '',
      sawBusy: sawStart,
      count: modelResponses().length,
      sendMeta: sent,
      complete: isGenerationComplete(baselineCount)
    };
  };

  api.probe = function () {
    var input = findInput();
    var host = location.hostname || '';
    var hostOk = host.indexOf('gemini.google') !== -1 || host.indexOf('bard.google') !== -1;
    var send = findSendButton();
    var last = lastModelResponse();
    return {
      ok: !!(hostOk && input),
      id: 'gemini',
      host: host,
      hostOk: hostOk,
      loggedIn: !!input,
      hasInput: !!input,
      hasSend: !!send,
      editorTextLen: input ? editorText(input).length : 0,
      responseCount: modelResponses().length,
      lastAnswerPreview: (extractAnswerFromItem(last) || '').slice(0, 80),
      busy: !!findBusy(),
      hasStop: !!findStopButton(),
      href: location.href || '',
      detail: !hostOk ? 'host mismatch' : !input ? 'input not found (login?)' : 'ok'
    };
  };

  console.info('[AIBridge] gemini adapter installed', api.probe());
})();
