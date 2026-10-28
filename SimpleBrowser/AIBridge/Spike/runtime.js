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

  /**
   * 从已渲染的 Markdown DOM（如 DeepSeek .ds-markdown）还原 Markdown 文本。
   * 避免 innerText 把表格/标题压成纯文本，导致侧栏无法排版。
   */
  function richMarkdownFromElement(root) {
    if (!root) return '';

    function cellText(el) {
      return String((el && (el.innerText || el.textContent)) || '')
        .replace(/\u00a0/g, ' ')
        .replace(/\s+/g, ' ')
        .replace(/\|/g, '\\|')
        .trim();
    }

    function tableToMd(table) {
      var trs = qsa('tr', table);
      if (!trs.length) return '';
      var rows = trs.map(function (tr) {
        return qsa('th,td', tr).map(cellText);
      }).filter(function (r) {
        return r.length > 0;
      });
      if (!rows.length) return '';
      var width = 0;
      rows.forEach(function (r) {
        if (r.length > width) width = r.length;
      });
      rows = rows.map(function (r) {
        var copy = r.slice();
        while (copy.length < width) copy.push('');
        return copy;
      });
      var lines = [];
      lines.push('| ' + rows[0].join(' | ') + ' |');
      lines.push('| ' + rows[0].map(function () { return '---'; }).join(' | ') + ' |');
      for (var i = 1; i < rows.length; i++) {
        lines.push('| ' + rows[i].join(' | ') + ' |');
      }
      return lines.join('\n') + '\n\n';
    }

    function walk(node, acc) {
      if (!node) return;
      var type = node.nodeType;
      if (type === 3) {
        // TEXT
        var t = String(node.nodeValue || '').replace(/\u00a0/g, ' ');
        if (t) acc.push(t);
        return;
      }
      if (type !== 1) return; // ELEMENT
      var tag = (node.tagName || '').toLowerCase();
      if (tag === 'script' || tag === 'style' || tag === 'svg' || tag === 'noscript' ||
          tag === 'button' || tag === 'textarea' || tag === 'input') {
        return;
      }
      // 常见「引用/复制」工具条
      var cls = String(node.className || '');
      if (/ds-icon-button|copy-button|toolbar|citation/i.test(cls) && tag !== 'table') {
        // 仍允许内含正文的容器继续；纯工具条跳过
        if (!qsa('p,h1,h2,h3,h4,li,table,pre', node).length) return;
      }

      if (/^h[1-6]$/.test(tag)) {
        var level = Number(tag.charAt(1)) || 1;
        var hashes = '######'.slice(0, level);
        var title = cellText(node);
        if (title) acc.push('\n\n' + hashes + ' ' + title + '\n\n');
        return;
      }
      if (tag === 'br') {
        acc.push('\n');
        return;
      }
      if (tag === 'hr') {
        acc.push('\n\n---\n\n');
        return;
      }
      if (tag === 'table') {
        acc.push('\n\n' + tableToMd(node));
        return;
      }
      if (tag === 'pre') {
        var codeEl = qs('code', node) || node;
        var code = String(codeEl.textContent || '').replace(/\n$/, '');
        acc.push('\n\n```\n' + code + '\n```\n\n');
        return;
      }
      if (tag === 'code') {
        // 行内 code（pre>code 已在 pre 处理）
        if (node.parentElement && (node.parentElement.tagName || '').toLowerCase() === 'pre') return;
        acc.push('`' + String(node.textContent || '').replace(/`/g, '\\`') + '`');
        return;
      }
      if (tag === 'strong' || tag === 'b') {
        acc.push('**');
        Array.prototype.forEach.call(node.childNodes, function (c) { walk(c, acc); });
        acc.push('**');
        return;
      }
      if (tag === 'em' || tag === 'i') {
        acc.push('*');
        Array.prototype.forEach.call(node.childNodes, function (c) { walk(c, acc); });
        acc.push('*');
        return;
      }
      if (tag === 'a') {
        var href = node.getAttribute('href') || '';
        var labelAcc = [];
        Array.prototype.forEach.call(node.childNodes, function (c) { walk(c, labelAcc); });
        var label = labelAcc.join('').trim() || href;
        if (href && /^https?:/i.test(href)) {
          acc.push('[' + label + '](' + href + ')');
        } else {
          acc.push(label);
        }
        return;
      }
      if (tag === 'blockquote') {
        var bq = [];
        Array.prototype.forEach.call(node.childNodes, function (c) { walk(c, bq); });
        var bqt = bq.join('').trim().split(/\n/).map(function (ln) {
          return '> ' + ln;
        }).join('\n');
        if (bqt) acc.push('\n\n' + bqt + '\n\n');
        return;
      }
      if (tag === 'ul' || tag === 'ol') {
        var ordered = tag === 'ol';
        var items = Array.prototype.filter.call(node.children || [], function (c) {
          return (c.tagName || '').toLowerCase() === 'li';
        });
        if (!items.length) items = qsa('li', node);
        var lines = [];
        items.forEach(function (li, idx) {
          var ia = [];
          Array.prototype.forEach.call(li.childNodes, function (c) { walk(c, ia); });
          var it = ia.join('').replace(/\s+/g, ' ').trim();
          if (!it) return;
          lines.push((ordered ? idx + 1 + '. ' : '- ') + it);
        });
        if (lines.length) acc.push('\n\n' + lines.join('\n') + '\n\n');
        return;
      }
      if (tag === 'li') {
        // 由 ul/ol 处理
        Array.prototype.forEach.call(node.childNodes, function (c) { walk(c, acc); });
        return;
      }
      if (tag === 'p' || tag === 'div' || tag === 'section' || tag === 'article') {
        var before = acc.length;
        Array.prototype.forEach.call(node.childNodes, function (c) { walk(c, acc); });
        if (acc.length > before) {
          // 块级后补空行
          var last = acc[acc.length - 1];
          if (last && !/\n\n$/.test(last)) acc.push('\n\n');
        }
        return;
      }

      Array.prototype.forEach.call(node.childNodes, function (c) { walk(c, acc); });
    }

    var parts = [];
    walk(root, parts);
    return parts
      .join('')
      .replace(/[ \t]+\n/g, '\n')
      .replace(/\n{3,}/g, '\n\n')
      .trim();
  }

  global.AIBridgeRuntime = {
    install: install,
    nativeSetValue: nativeSetValue,
    qs: qs,
    qsa: qsa,
    richMarkdownFromElement: richMarkdownFromElement
  };
})(typeof window !== 'undefined' ? window : this);
