/**
 * Kimi web chat adapter (kimi.moonshot.cn / www.kimi.com / kimi.com)
 * Revised 2026-10-28 #7 (live inspect):
 * - Done label:「思考已完成」in .thinking-container
 * - Answer: .markdown-container:not(.toolcall-content-text) .markdown
 * - Do NOT strip [class*="tool"] (breaks toolcall DOM)
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

  function visible(el) {
    if (!el) return false;
    var r = el.getBoundingClientRect();
    return r.width > 12 && r.height > 12;
  }

  function isDisabled(el) {
    if (!el) return true;
    if (el.disabled) return true;
    if (el.getAttribute && el.getAttribute('aria-disabled') === 'true') return true;
    if (el.classList && el.classList.contains('disabled')) return true;
    var parent = el.closest && el.closest('.send-button-container');
    if (parent && parent.classList && parent.classList.contains('disabled')) return true;
    return false;
  }

  function normalizeText(s) {
    return String(s || '')
      .replace(/\u00a0/g, ' ')
      .replace(/\r/g, '')
      .trim();
  }

  function editorText(el) {
    if (!el) return '';
    return normalizeText(el.innerText || el.textContent || '');
  }

  function findInput() {
    // Prefer composer region near chat input / send button
    var roots = [];
    var chatInput = document.querySelector('.chat-input, .chat-editor, [class*="chat-input"]');
    if (chatInput) roots.push(chatInput);
    var sendWrap = document.querySelector('.send-button-container, [data-testid="msh-chatinput-send-button"]');
    if (sendWrap) {
      var near = sendWrap.closest('.chat-input, form, [class*="composer"], [class*="editor"]') || sendWrap.parentElement;
      if (near) roots.push(near);
    }
    roots.push(document);

    var sels = [
      '[data-testid="msh-chatinput-editor"]',
      '.chat-input-editor[contenteditable="true"]',
      '.chat-input-editor[data-lexical-editor]',
      '.chat-input-editor',
      '[data-lexical-editor="true"][contenteditable="true"]',
      '[data-lexical-editor="true"]',
      'div[contenteditable="true"][role="textbox"]',
      '[contenteditable="true"]'
    ];

    for (var r = 0; r < roots.length; r++) {
      var root = roots[r];
      if (!root || !root.querySelectorAll) continue;
      for (var s = 0; s < sels.length; s++) {
        var list;
        try {
          list = Array.prototype.slice.call(root.querySelectorAll(sels[s]));
        } catch (e) {
          list = [];
        }
        for (var i = 0; i < list.length; i++) {
          var el = list[i];
          if (!visible(el)) continue;
          // skip message bubbles that happen to be contenteditable
          if (el.closest && el.closest('.chat-content-item, .chat-content-list .segment-content')) {
            continue;
          }
          return el;
        }
      }
    }
    return null;
  }

  function moveCursorToEnd(el) {
    try {
      el.focus();
      var range = document.createRange();
      range.selectNodeContents(el);
      range.collapse(false);
      var sel = window.getSelection();
      sel.removeAllRanges();
      sel.addRange(range);
    } catch (e) { /* ignore */ }
  }

  function clearLexical(el) {
    try {
      el.focus();
      document.execCommand('selectAll', false, null);
      document.execCommand('delete', false, null);
    } catch (e) { /* ignore */ }
    // Lexical empty often is <p><br></p> — wipe children if still "non-empty" junk
    var t = editorText(el);
    if (t.length) {
      try {
        el.focus();
        document.execCommand('selectAll', false, null);
        document.execCommand('insertText', false, '');
      } catch (e2) { /* ignore */ }
    }
  }

  function tryInsertText(el, text) {
    moveCursorToEnd(el);
    try {
      return !!document.execCommand('insertText', false, text);
    } catch (e) {
      return false;
    }
  }

  function tryPaste(el, text) {
    try {
      var dt = new DataTransfer();
      dt.setData('text/plain', text);
      var evt = new ClipboardEvent('paste', {
        bubbles: true,
        cancelable: true,
        clipboardData: dt
      });
      el.focus();
      return el.dispatchEvent(evt);
    } catch (e) {
      return false;
    }
  }

  function tryBeforeInput(el, text) {
    try {
      el.focus();
      moveCursorToEnd(el);
      var before = new InputEvent('beforeinput', {
        bubbles: true,
        cancelable: true,
        inputType: 'insertText',
        data: text
      });
      var ok = el.dispatchEvent(before);
      if (ok !== false && !editorText(el)) {
        // if not cancelled but still empty, append via insertText
        document.execCommand('insertText', false, text);
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  function editorLooksFilled(el, expect) {
    var t = editorText(el);
    if (!t) return false;
    var exp = normalizeText(expect);
    if (!exp) return t.length > 0;
    return t.indexOf(exp) !== -1 || t === exp || t.replace(/\n/g, '') === exp.replace(/\n/g, '');
  }

  /**
   * Async fill with retries. Success if:
   * - editor contains text, OR
   * - send button becomes enabled (Lexical state synced)
   */
  async function setLexicalTextAsync(el, text) {
    if (!el) return false;
    text = String(text || '');
    for (var attempt = 0; attempt < 4; attempt++) {
      el.focus();
      await sleep(20);
      clearLexical(el);
      await sleep(40);

      if (attempt === 0) {
        tryInsertText(el, text);
      } else if (attempt === 1) {
        tryPaste(el, text);
        await sleep(30);
        if (!editorLooksFilled(el, text)) tryInsertText(el, text);
      } else if (attempt === 2) {
        tryBeforeInput(el, text);
        await sleep(30);
        if (!editorLooksFilled(el, text)) tryInsertText(el, text);
      } else {
        // last: insert in small chunks (helps some Lexical builds)
        clearLexical(el);
        await sleep(20);
        var chunk = 16;
        for (var i = 0; i < text.length; i += chunk) {
          tryInsertText(el, text.slice(i, i + chunk));
          await sleep(10);
        }
      }

      await sleep(60);
      if (editorLooksFilled(el, text)) return true;
      if (findSendButton(false)) return true; // enabled send ⇒ Lexical accepted content
    }
    // Soft success: any non-empty editor text after attempts
    return editorText(el).length > 0 || !!findSendButton(false);
  }

  function findSendButton(includeDisabled) {
    var preferred = [
      '.send-button-container:not(.disabled) .send-button',
      '.send-button-container:not(.disabled) button',
      '[data-testid="msh-chatinput-send-button"]:not([disabled])',
      '[data-testid="msh-chatinput-send-button"]',
      'button[data-testid*="send"]',
      '.send-button-container .send-button',
      '.send-button'
    ];
    for (var s = 0; s < preferred.length; s++) {
      var list = AIBridgeRuntime.qsa(preferred[s]);
      for (var i = 0; i < list.length; i++) {
        var b = list[i];
        if (!visible(b)) continue;
        if (!includeDisabled && isDisabled(b)) continue;
        return b;
      }
    }
    var icon = document.querySelector('svg[name="Send"], .send-icon');
    if (icon) {
      var parent =
        icon.closest('.send-button') ||
        icon.closest('button') ||
        icon.closest('.send-button-container');
      if (parent && visible(parent) && (includeDisabled || !isDisabled(parent))) return parent;
    }
    return null;
  }

  function clickElement(el) {
    if (!el) return false;
    try {
      el.scrollIntoView({ block: 'nearest', inline: 'nearest' });
    } catch (e) { /* ignore */ }
    var rect = el.getBoundingClientRect();
    var x = rect.left + Math.min(Math.max(rect.width / 2, 4), 20);
    var y = rect.top + Math.min(Math.max(rect.height / 2, 4), 20);
    var opts = { bubbles: true, cancelable: true, view: window, clientX: x, clientY: y, button: 0 };
    try {
      el.dispatchEvent(new PointerEvent('pointerdown', opts));
      el.dispatchEvent(new MouseEvent('mousedown', opts));
      el.dispatchEvent(new PointerEvent('pointerup', opts));
      el.dispatchEvent(new MouseEvent('mouseup', opts));
      el.dispatchEvent(new MouseEvent('click', opts));
    } catch (e2) {
      try {
        el.click();
      } catch (e3) { /* ignore */ }
    }
    try {
      el.click();
    } catch (e4) { /* ignore */ }
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

  async function waitForEnabledSend(maxMs) {
    var deadline = Date.now() + (maxMs || 3000);
    while (Date.now() < deadline) {
      var btn = findSendButton(false);
      if (btn) return btn;
      await sleep(50);
    }
    return findSendButton(true);
  }

  async function sendPrompt(text) {
    text = text == null ? '' : String(text);
    var el = findInput();
    if (!el) return { ok: false, error: 'input not found' };

    var filled = await setLexicalTextAsync(el, text);
    if (!filled) {
      // one more soft path: if any text present, continue
      if (!editorText(el).length) {
        return { ok: false, error: 'setInput failed' };
      }
    }

    await sleep(80);
    var btn = await waitForEnabledSend(3000);
    var clicked = false;
    if (btn) {
      clicked = clickElement(btn);
      var container = btn.closest && btn.closest('.send-button-container');
      if (container && container !== btn) clickElement(container);
    }
    if (!clicked || isDisabled(btn)) {
      pressEnter(el);
      await sleep(80);
      pressEnter(el);
      btn = findSendButton(false);
      if (btn) clickElement(btn);
      clicked = true;
    }

    // If composer still holds the prompt, retry click/enter once
    await sleep(150);
    if (editorLooksFilled(el, text)) {
      btn = findSendButton(false) || findSendButton(true);
      if (btn) clickElement(btn);
      pressEnter(el);
    }

    return {
      ok: true,
      clicked: clicked,
      editorPreview: editorText(el).slice(0, 40),
      hasSendEnabled: !!findSendButton(false)
    };
  }

  /** Single status line / intermediate chrome — never final answer. */
  function isStatusLine(line) {
    var t = normalizeText(line);
    if (!t) return true;
    if (
      /^(正在思考中|思考中|深度思考中|已深度思考|思考已完成了?|思考完成了?|正在搜索|搜索中|生成中|正在生成|Thinking|Thinking\.\.\.|Thinking…)$/i.test(
        t
      )
    ) {
      return true;
    }
    if (/思考已完成|思考完成/.test(t) && t.length <= 20) return true;
    if (/^使用\s*\d+\s*个工具/.test(t)) return true;
    if (/^已使用\s*\d+\s*个工具/.test(t)) return true;
    if (/^(调用|正在调用).{0,24}工具/.test(t)) return true;
    if (/搜索了?\s*\d+\s*个?(网页|结果|站点|来源)?/.test(t) && t.length < 48) return true;
    if (/^(重新生成|复制|分享|点赞|踩)$/.test(t)) return true;
    if (t.length <= 18 && /^(正在)?(思考|搜索|生成|调用)/.test(t)) return true;
    return false;
  }

  function isStatusOnlyText(text) {
    var t = normalizeText(text);
    if (!t) return true;
    if (isStatusLine(t)) return true;
    var lines = t.split(/\n+/).map(normalizeText).filter(Boolean);
    if (!lines.length) return true;
    return lines.every(isStatusLine);
  }

  function stripStatusLines(text) {
    var cleaned = String(text || '')
      .split(/\n+/)
      .map(normalizeText)
      .filter(function (line) {
        return line && !isStatusLine(line);
      })
      .join('\n')
      .trim();
    // Same-line prefix:「思考已完成 pong — …」
    cleaned = cleaned
      .replace(/^(思考已完成了?|思考完成了?|已深度思考|正在思考中)\s*/g, '')
      .replace(/\s*(思考已完成了?|思考完成了?)\s*/g, ' ')
      .trim();
    return cleaned;
  }

  function hasThinkingFinishedLabel(item) {
    if (!item) return false;
    // Live dump: label text is「思考已完成」(用户口述「思考已完成了」)
    return /思考已完成|思考完成|已深度思考/.test(item.innerText || '');
  }

  function isInsideThinkingChrome(el) {
    if (!el || !el.closest) return false;
    return !!(
      el.closest('.thinking-container') ||
      el.closest('.toolcall-content-text') ||
      el.closest('.toolcall-container.thinking-container')
    );
  }

  /**
   * Live DOM (inspect 2026-10-28):
   *   .thinking-container / toolcall →「思考已完成」(+ optional think markdown)
   *   .markdown-container:not(.toolcall-content-text) .markdown → 真正回复
   * 切勿用 [class*="tool"] 删除节点：会误伤 toolcall / markdown-container。
   */
  function richFrom(el) {
    if (!el) return '';
    var rich =
      (AIBridgeRuntime.richMarkdownFromElement && AIBridgeRuntime.richMarkdownFromElement(el)) || '';
    if (rich && rich.trim()) return rich.trim();
    return stripStatusLines(el.innerText || el.textContent || '');
  }

  function extractAnswerFromItem(item) {
    if (!item) return '';

    // A) Preferred: answer markdown containers outside thinking chrome
    var containers = item.querySelectorAll('.markdown-container');
    var best = '';
    for (var i = 0; i < containers.length; i++) {
      var c = containers[i];
      if (c.classList && c.classList.contains('toolcall-content-text')) continue;
      if (isInsideThinkingChrome(c)) continue;
      var ct = stripStatusLines(richFrom(c));
      if (ct && !isStatusOnlyText(ct)) best = ct;
    }
    if (best) return best;

    // B) .markdown leaves outside thinking
    var marks = item.querySelectorAll('.markdown');
    for (var m = 0; m < marks.length; m++) {
      var md = marks[m];
      if (isInsideThinkingChrome(md)) continue;
      if (md.closest && md.closest('.toolcall-content-text')) continue;
      var mt = stripStatusLines(richFrom(md));
      if (mt && !isStatusOnlyText(mt)) best = mt;
    }
    if (best) return best;

    // C) Sibling after the「思考已完成」rollup part
    var parts = item.querySelectorAll('.toolcall-rollup__part');
    for (var p = 0; p < parts.length; p++) {
      var part = parts[p];
      var pt = normalizeText(part.innerText || '');
      if (pt.length <= 20 && /思考已完成|思考完成/.test(pt)) {
        var sib = part.nextElementSibling;
        while (sib) {
          var st = stripStatusLines(sib.innerText || '');
          if (st && !isStatusOnlyText(st) && !/思考已完成/.test(st)) return st;
          sib = sib.nextElementSibling;
        }
      }
    }

    // D) Last resort: whole item minus thinking-container + status lines
    var clone = item.cloneNode(true);
    try {
      var drop = clone.querySelectorAll(
        '.thinking-container, .toolcall-content-text, .recommend-prompt-list, .segment-assistant-actions, .segment-assistant-actions-content, .segment-429-tip, .segment-avatar'
      );
      for (var d = 0; d < drop.length; d++) {
        if (drop[d].parentNode) drop[d].parentNode.removeChild(drop[d]);
      }
    } catch (e) { /* ignore */ }
    var text = stripStatusLines(clone.innerText || clone.textContent || '');
    if (isStatusOnlyText(text)) return '';
    return text;
  }

  function assistantItemCount() {
    return AIBridgeRuntime.qsa('.chat-content-item-assistant').length;
  }

  function lastAssistantItem() {
    var items = AIBridgeRuntime.qsa('.chat-content-item-assistant');
    return items.length ? items[items.length - 1] : null;
  }

  /** Stop / cancel-generation control (true in-flight signal). */
  function findStopButton() {
    var sels = [
      '[data-testid*="stop"]',
      'button[aria-label*="停止"]',
      'button[aria-label*="Stop"]',
      '.stop___Cioqe'
    ];
    for (var s = 0; s < sels.length; s++) {
      var list = AIBridgeRuntime.qsa(sels[s]);
      for (var i = 0; i < list.length; i++) {
        var b = list[i];
        var label = ((b.getAttribute('aria-label') || '') + ' ' + (b.innerText || '') + ' ' + (b.className || '')).toLowerCase();
        if (/停止|stop|取消生成/.test(label) && visible(b)) return b;
        if (sels[s].indexOf('stop') !== -1 && visible(b)) return b;
      }
    }
    var nodes = AIBridgeRuntime.qsa('button, [role="button"]');
    for (var j = 0; j < nodes.length; j++) {
      var n = nodes[j];
      var t = ((n.getAttribute('aria-label') || '') + ' ' + (n.innerText || '')).toLowerCase();
      if (/停止|stop|取消生成/.test(t) && visible(n)) return n;
    }
    return null;
  }

  function hasCopyOnItem(item) {
    if (!item) return false;
    return !!(
      item.querySelector('[data-testid="msh-chat-segment-copy"]') ||
      item.querySelector('[data-testid*="copy"]') ||
      item.querySelector('[aria-label*="复制"]') ||
      item.querySelector('[aria-label*="Copy"]') ||
      item.querySelector('.segment-assistant-actions')
    );
  }

  function isLiveThinking(item) {
    if (!item) return false;
    // Finished label means thinking phase ended
    if (hasThinkingFinishedLabel(item)) return false;
    var raw = item.innerText || '';
    if (/正在思考中|正在搜索|正在生成|正在调用/.test(raw)) return true;
    return false;
  }

  /**
   * Generation finished on page:
   *  1) no Stop
   *  2) preferably「思考已完成了」shown (thinking models)
   *  3) real answer text below that label
   */
  function isGenerationComplete() {
    if (findStopButton()) return false;
    var item = lastAssistantItem();
    if (!item) return false;
    if (isLiveThinking(item)) return false;
    var answer = extractAnswerFromItem(item);
    if (!answer || isStatusOnlyText(answer)) return false;
    // Thinking models: wait until finished label appears
    var raw = item.innerText || '';
    var usesThinkingUI = /思考|Thinking/i.test(raw);
    if (usesThinkingUI) {
      return hasThinkingFinishedLabel(item) && answer.length >= 1;
    }
    if (hasCopyOnItem(item)) return true;
    if (findSendButton(false) && answer.length >= 2) return true;
    return false;
  }

  function findBusy() {
    if (findStopButton()) return true;
    var item = lastAssistantItem();
    if (item && isLiveThinking(item)) return true;
    if (item && isStatusOnlyText(extractAnswerFromItem(item))) {
      var raw = normalizeText(item.innerText || '');
      if (/思考|工具|搜索|生成|Thinking/i.test(raw)) return true;
    }
    return false;
  }

  function readLastAssistant() {
    var item = lastAssistantItem();
    var text = item ? extractAnswerFromItem(item) : '';
    if (isStatusOnlyText(text)) text = '';
    return {
      text: text,
      count: assistantItemCount(),
      messageId: null,
      complete: isGenerationComplete()
    };
  }

  AIBridgeRuntime.install({
    id: 'kimi',
    matchHosts: ['kimi.moonshot.cn', 'www.kimi.com', 'kimi.com', 'app.kimi.ai'],
    inputSelector: '[data-testid="msh-chatinput-editor"], .chat-input-editor, [data-lexical-editor="true"]',
    sendSelector: '.send-button-container:not(.disabled) .send-button, [data-testid="msh-chatinput-send-button"]',
    assistantSelector: '.chat-content-item-assistant .segment-content, .chat-content-item-assistant',
    busySelector: null,
    loggedIn: function () {
      return !!findInput();
    },
    setInput: function (el, text) {
      var target = findInput() || el;
      if (!target) return false;
      clearLexical(target);
      return tryInsertText(target, text) || editorText(target).length > 0;
    },
    clickSend: function () {
      var btn = findSendButton(false) || findSendButton(true);
      return btn ? clickElement(btn) : false;
    },
    isBusy: function () {
      return !!findBusy();
    },
    newChat: function () {
      var links = AIBridgeRuntime.qsa('a, button, [role="button"]');
      for (var i = 0; i < links.length; i++) {
        var t = (links[i].innerText || links[i].getAttribute('aria-label') || '').trim();
        if (/^新对话$|^新会话$|new chat/i.test(t) || /开启新对话/.test(t)) {
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
    clearLexical(el);
    tryInsertText(el, text);
    var btn = findSendButton(false);
    if (btn) clickElement(btn);
    else pressEnter(el);
    return { ok: true };
  };

  api.readLastAssistant = readLastAssistant;

  /**
   * Wait until the PAGE finishes responding, then parse answer.
   * Do NOT return on intermediate labels (思考中 / 使用 N 个工具).
   */
  api.sendAndWait = async function (text, opts) {
    opts = opts || {};
    var timeoutMs = opts.timeoutMs != null ? opts.timeoutMs : 180000;
    var stableMs = opts.stableMs != null ? opts.stableMs : 1200;
    var baselineCount = assistantItemCount();
    var baselineText = readLastAssistant().text;

    var sent = await sendPrompt(text);
    if (!sent.ok) return { ok: false, phase: 'send', error: sent.error, sendMeta: sent };

    var start = Date.now();
    var sawStart = false;
    var lastText = '';
    var lastChange = 0;
    var doneSince = 0;

    while (Date.now() - start < timeoutMs) {
      var stop = !!findStopButton();
      var itemCount = assistantItemCount();
      var item = lastAssistantItem();
      var thinking = item ? isLiveThinking(item) : false;
      var complete = isGenerationComplete();
      var curText = item ? extractAnswerFromItem(item) : '';
      if (isStatusOnlyText(curText)) curText = '';

      if (stop || thinking || itemCount > baselineCount) {
        sawStart = true;
      }

      // Still running — keep waiting (even if some intermediate text appeared)
      if (!complete) {
        doneSince = 0;
        lastText = curText;
        await sleep(300);
        continue;
      }

      // Page signals complete — require answer + stability
      if (!curText || isStatusOnlyText(curText)) {
        doneSince = 0;
        await sleep(300);
        continue;
      }
      // Must be a new reply vs baseline (or clearly different after new item)
      var isNew =
        itemCount > baselineCount ||
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
      if (stableFor >= stableMs && !findStopButton() && isGenerationComplete()) {
        return {
          ok: true,
          text: curText,
          sawBusy: sawStart,
          count: itemCount,
          sendMeta: sent,
          complete: true
        };
      }
      await sleep(300);
    }

    // Timeout: only soft-return if generation looks finished with real text
    var finalItem = lastAssistantItem();
    var finalText = finalItem ? extractAnswerFromItem(finalItem) : '';
    if (
      isGenerationComplete() &&
      finalText &&
      !isStatusOnlyText(finalText) &&
      (assistantItemCount() > baselineCount || finalText !== baselineText)
    ) {
      return {
        ok: true,
        text: finalText,
        sawBusy: sawStart,
        count: assistantItemCount(),
        sendMeta: sent,
        soft: true
      };
    }

    return {
      ok: false,
      error: 'timeout',
      text: isStatusOnlyText(finalText) ? '' : finalText,
      sawBusy: sawStart,
      count: assistantItemCount(),
      sendMeta: sent,
      complete: isGenerationComplete()
    };
  };

  api.probe = function () {
    var input = findInput();
    var host = location.hostname || '';
    var hostOk = host.indexOf('kimi') !== -1 || host.indexOf('moonshot') !== -1;
    var sendEnabled = findSendButton(false);
    var sendAny = findSendButton(true);
    var last = readLastAssistant();
    return {
      ok: !!(hostOk && input),
      id: 'kimi',
      host: host,
      hostOk: hostOk,
      loggedIn: !!input,
      hasInput: !!input,
      hasSend: !!sendAny,
      hasSendEnabled: !!sendEnabled,
      editorTextLen: input ? editorText(input).length : 0,
      assistantCount: last.count,
      lastAssistantPreview: (last.text || '').slice(0, 60),
      busy: !!findBusy(),
      href: location.href || '',
      detail: !hostOk ? 'host mismatch' : !input ? 'input not found' : 'ok'
    };
  };

  console.info('[AIBridge] kimi adapter installed', api.probe());
})();
