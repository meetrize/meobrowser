/**
 * DeepSeek web chat adapter (chat.deepseek.com)
 * Revised 2026-10-28 after live probe on logged-in session.
 * Attachments 2026-10-29: hidden input[type=file] + DataTransfer injection.
 *
 * Findings:
 * - Composer: textarea / .aaff8b8f
 * - Send control: DIV.ds-button--primary (not <button>, often no aria-label)
 * - Assistant bubble: .ds-markdown.ds-assistant-message-main-content (inside .ds-message)
 * - File input: input[type=file][multiple] inside composer (hidden)
 * - Attach chip: filename node + meta (e.g. "TXT 73B"); upload hits /api/v0/file/upload_file
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
    if (!input) input = findInput();
    if (!input) return document;
    return (
      input.closest('.aaff8b8f') ||
      input.closest('[class*="composer"]') ||
      (input.parentElement &&
        input.parentElement.parentElement &&
        input.parentElement.parentElement.parentElement) ||
      document
    );
  }

  function isDisabledControl(el) {
    if (!el) return true;
    var cls = String(el.className || '');
    if (/disabled|ds-button--disabled/i.test(cls)) return true;
    if (el.getAttribute && el.getAttribute('aria-disabled') === 'true') return true;
    if (el.disabled) return true;
    return false;
  }

  function findSendButton() {
    var input = findInput();
    var root = composerRoot(input);
    var cands = AIBridgeRuntime.qsa('.ds-button--primary, .ds-button--filled', root);
    for (var i = 0; i < cands.length; i++) {
      var b = cands[i];
      if (isDisabledControl(b)) continue;
      var r = b.getBoundingClientRect();
      if (r.width > 0 && r.height > 0) return b;
    }
    if (input && input.parentElement) {
      var near = input.parentElement.parentElement || input.parentElement;
      var all = near.querySelectorAll('.ds-button, [role="button"]');
      for (var j = all.length - 1; j >= 0; j--) {
        var el = all[j];
        if (isDisabledControl(el)) continue;
        var rr = el.getBoundingClientRect();
        if (rr.width > 20 && rr.height > 20) return el;
      }
    }
    return null;
  }

  function findBusy() {
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

  function findFileInput() {
    var root = composerRoot(findInput());
    var local = root.querySelector && root.querySelector('input[type="file"]');
    if (local) return local;
    return document.querySelector('input[type="file"]');
  }

  function assistantNodes() {
    return AIBridgeRuntime.qsa(
      '.ds-markdown.ds-assistant-message-main-content, .ds-message .ds-markdown.ds-assistant-message-main-content'
    ).filter(function (el) {
      return ((el.innerText || '').trim().length > 0);
    });
  }

  function extractAssistantMarkdown(el) {
    if (!el) return '';
    var md =
      (AIBridgeRuntime.richMarkdownFromElement && AIBridgeRuntime.richMarkdownFromElement(el)) ||
      '';
    if (md && md.trim()) return md.trim();
    return ((el.innerText || el.textContent || '') + '').trim();
  }

  function readLastAssistant() {
    var list = assistantNodes();
    var el = list.length ? list[list.length - 1] : null;
    return {
      text: extractAssistantMarkdown(el),
      count: list.length,
      messageId: null
    };
  }

  function sleep(ms) {
    return new Promise(function (resolve) {
      setTimeout(resolve, ms);
    });
  }

  function base64ToUint8Array(b64) {
    var bin = atob(b64 || '');
    var len = bin.length;
    var out = new Uint8Array(len);
    for (var i = 0; i < len; i++) out[i] = bin.charCodeAt(i);
    return out;
  }

  function fileFromSpec(spec) {
    if (!spec || !spec.name) return null;
    var bytes;
    if (spec.base64) {
      bytes = base64ToUint8Array(spec.base64);
    } else if (spec.chunks && spec.chunks.length) {
      bytes = base64ToUint8Array(spec.chunks.join(''));
    } else {
      return null;
    }
    var mime = spec.mime || 'application/octet-stream';
    // WKWebView: prefer a precise ArrayBuffer slice for File()
    var ab = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
    try {
      return new File([ab], spec.name, { type: mime, lastModified: Date.now() });
    } catch (e1) {
      try {
        return new File([bytes], spec.name, { type: mime });
      } catch (e2) {
        return null;
      }
    }
  }

  function reactPropsKey(el) {
    if (!el) return null;
    var keys = Object.keys(el);
    for (var i = 0; i < keys.length; i++) {
      if (keys[i].indexOf('__reactProps$') === 0 || keys[i].indexOf('__reactEventHandlers$') === 0) {
        return keys[i];
      }
    }
    return null;
  }

  function invokeReactChange(el) {
    if (!el) return false;
    var key = reactPropsKey(el);
    if (!key || !el[key] || typeof el[key].onChange !== 'function') return false;
    try {
      el[key].onChange({
        target: el,
        currentTarget: el,
        type: 'change',
        bubbles: true,
        preventDefault: function () {},
        stopPropagation: function () {}
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  function dropFilesOnComposer(fileList) {
    var root = composerRoot(findInput());
    if (!root || !fileList || !fileList.length) return false;
    try {
      var dt = new DataTransfer();
      for (var i = 0; i < fileList.length; i++) dt.items.add(fileList[i]);
      ['dragenter', 'dragover', 'drop'].forEach(function (type) {
        var ev;
        try {
          ev = new DragEvent(type, { bubbles: true, cancelable: true, dataTransfer: dt });
        } catch (e) {
          ev = document.createEvent('DragEvent');
          ev.initEvent(type, true, true);
          try {
            Object.defineProperty(ev, 'dataTransfer', { value: dt });
          } catch (e2) {}
        }
        root.dispatchEvent(ev);
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  // 钩住官方上传：WK 上 DOM 芯片检测易漏，以 upload_file 成功为准
  var uploadHook = window.__MeoAIBridgeUploadHook;
  if (!uploadHook) {
    uploadHook = { okCount: 0, failCount: 0, lastAt: 0, lastName: '', installed: false };
    window.__MeoAIBridgeUploadHook = uploadHook;
  }

  function noteUploadOk(hint) {
    uploadHook.okCount += 1;
    uploadHook.lastAt = Date.now();
    if (hint) uploadHook.lastName = String(hint);
  }

  function installUploadHook() {
    if (uploadHook.installed) return;
    uploadHook.installed = true;
    try {
      var origFetch = window.fetch;
      if (typeof origFetch === 'function') {
        window.fetch = function (input, init) {
          var url = '';
          try {
            url = typeof input === 'string' ? input : (input && input.url) || '';
          } catch (e1) {}
          var p = origFetch.apply(this, arguments);
          if (/\/api\/v0\/file\/upload_file/.test(url)) {
            return Promise.resolve(p).then(
              function (res) {
                try {
                  if (res && res.ok) noteUploadOk('fetch');
                  else uploadHook.failCount += 1;
                } catch (e2) {}
                return res;
              },
              function (err) {
                uploadHook.failCount += 1;
                throw err;
              }
            );
          }
          return p;
        };
      }
    } catch (e3) {}
    try {
      var XO = window.XMLHttpRequest;
      if (XO && XO.prototype) {
        var open = XO.prototype.open;
        var send = XO.prototype.send;
        XO.prototype.open = function (method, url) {
          try {
            this.__meoUpload = /\/api\/v0\/file\/upload_file/.test(String(url || ''));
          } catch (e4) {
            this.__meoUpload = false;
          }
          return open.apply(this, arguments);
        };
        XO.prototype.send = function () {
          if (this.__meoUpload) {
            this.addEventListener('load', function () {
              try {
                if (this.status >= 200 && this.status < 300) noteUploadOk('xhr');
                else uploadHook.failCount += 1;
              } catch (e5) {}
            });
            this.addEventListener('error', function () {
              uploadHook.failCount += 1;
            });
          }
          return send.apply(this, arguments);
        };
      }
    } catch (e6) {}
  }
  installUploadHook();

  function attachScanRoot() {
    var input = findInput();
    if (!input) return document.body || document.documentElement;
    // 上溯几层：芯片有时在 .aaff8b8f 外的兄弟条带
    var el = composerRoot(input);
    var p = input;
    for (var i = 0; i < 8 && p; i++) {
      if (p.querySelector && p.querySelector('input[type="file"]')) el = p;
      p = p.parentElement;
    }
    return el || document.body || document.documentElement;
  }

  function composerText() {
    var root = attachScanRoot();
    return ((root && root.innerText) || '').trim();
  }

  function looksUploading(root) {
    if (!root) root = attachScanRoot();
    if (!root) return false;
    var text = ((root.innerText || '') + '').toLowerCase();
    if (/上传中|uploading|解析中/.test(text)) return true;
    var meta = root.querySelectorAll('[class*="7103"], [class*="progress"], [class*="loading"]');
    for (var i = 0; i < meta.length; i++) {
      var t = ((meta[i].innerText || '') + '').trim().toLowerCase();
      if (/上传中|uploading|解析中|%/.test(t)) return true;
    }
    return false;
  }

  function nameVariants(name) {
    var n = String(name || '');
    var out = [];
    if (!n) return out;
    out.push(n);
    // 去扩展名（DeepSeek 偶发只显示 stem）
    var dot = n.lastIndexOf('.');
    if (dot > 0) out.push(n.slice(0, dot));
    // 超长名截断常见
    if (n.length > 24) out.push(n.slice(0, 20));
    if (n.length > 32) out.push(n.slice(0, 28));
    return out;
  }

  function textMentionsName(text, name) {
    if (!text || !name) return false;
    var vars = nameVariants(name);
    for (var i = 0; i < vars.length; i++) {
      if (vars[i] && text.indexOf(vars[i]) !== -1) return true;
    }
    return false;
  }

  /** 叶节点精确匹配文件名（不依赖哈希 class） */
  function countFilenameLeafNodes(name) {
    if (!name) return 0;
    var root = attachScanRoot();
    if (!root || !root.querySelectorAll) return 0;
    var vars = nameVariants(name);
    var n = 0;
    var nodes = root.querySelectorAll('div, span, p');
    for (var i = 0; i < nodes.length; i++) {
      var el = nodes[i];
      if (el.childElementCount > 0) continue;
      var t = ((el.textContent || '') + '').trim();
      if (!t || t.length > 240) continue;
      for (var v = 0; v < vars.length; v++) {
        if (vars[v] && t === vars[v]) {
          n += 1;
          break;
        }
        if (vars[v] && t.indexOf(vars[v]) !== -1 && t.length < vars[v].length + 8) {
          n += 1;
          break;
        }
      }
    }
    return n;
  }

  /** 结构卡：含文件名 + 类型/大小元信息 */
  function countAttachmentCards(name) {
    var root = attachScanRoot();
    if (!root) return 0;
    var n = 0;
    var cards = root.querySelectorAll(
      'div._25c7358, div.dafb6286, div[class*="25c735"], div[class*="dafb62"], div[class*="7780"], div[class*="158cea"]'
    );
    if (!cards.length) {
      // 回退：小块文本含「扩展名 + 数字B/K/M」
      cards = root.querySelectorAll('div');
    }
    var seen = [];
    for (var i = 0; i < cards.length; i++) {
      var el = cards[i];
      var t = ((el.innerText || '') + '').trim();
      if (!t || t.length > 180) continue;
      if (!textMentionsName(t, name)) continue;
      if (!/\b(TXT|PDF|PNG|JPG|JPEG|GIF|WEBP|DOC|DOCX|XLS|XLSX|PPT|PPTX|MD|CSV|JSON|ZIP|MP3|MP4|WAV)\b/i.test(t) &&
          !/\d+(\.\d+)?\s*[BKMGT]B?\b/i.test(t)) {
        continue;
      }
      // 去重嵌套父节点
      var dup = false;
      for (var s = 0; s < seen.length; s++) {
        if (seen[s].contains(el) || el.contains(seen[s])) {
          dup = true;
          break;
        }
      }
      if (dup) continue;
      seen.push(el);
      n += 1;
    }
    return n;
  }

  function countAttachmentSignals(name) {
    var leaf = countFilenameLeafNodes(name);
    if (leaf > 0) return leaf;
    var cards = countAttachmentCards(name);
    if (cards > 0) return cards;
    // 最宽：扫描根文本出现次数（可能把历史消息算上，仅作兜底）
    var text = composerText();
    if (!textMentionsName(text, name)) {
      var body = ((document.body && document.body.innerText) || '');
      if (textMentionsName(body, name)) return 1;
      return 0;
    }
    return 1;
  }

  function attachmentItemsForNames(names) {
    var root = attachScanRoot();
    var uploading = looksUploading(root);
    var items = [];
    for (var i = 0; i < (names || []).length; i++) {
      var name = names[i];
      var count = countAttachmentSignals(name);
      var uploadRecent =
        uploadHook.okCount > 0 && Date.now() - uploadHook.lastAt < 20000;
      items.push({
        name: name,
        count: count,
        metaText: '',
        ready: (count > 0 || uploadRecent) && !uploading,
        error: null
      });
    }
    return items;
  }

  function setInputFilesOnly(fileList) {
    var fi = findFileInput();
    if (!fi) return { ok: false, error: 'file input not found' };
    var dt = new DataTransfer();
    for (var i = 0; i < fileList.length; i++) dt.items.add(fileList[i]);
    try {
      fi.files = dt.files;
    } catch (e) {
      return { ok: false, error: 'cannot assign files: ' + (e && e.message) };
    }
    return { ok: true, input: fi };
  }

  async function waitAttachSuccess(fileName, beforeSignals, beforeUploads, timeoutMs) {
    var start = Date.now();
    while (Date.now() - start < timeoutMs) {
      var afterSignals = countAttachmentSignals(fileName);
      if (afterSignals > beforeSignals) {
        return { ok: true, via: 'dom', after: afterSignals, uploads: uploadHook.okCount };
      }
      if (uploadHook.okCount > beforeUploads) {
        // 网络已成功：再稍等 DOM，有没有都算成功
        await sleep(400);
        return {
          ok: true,
          via: 'upload_api',
          after: countAttachmentSignals(fileName),
          uploads: uploadHook.okCount
        };
      }
      await sleep(150);
    }
    return {
      ok: false,
      after: countAttachmentSignals(fileName),
      uploads: uploadHook.okCount,
      rootHas: textMentionsName(composerText(), fileName),
      bodyHas: textMentionsName(((document.body && document.body.innerText) || ''), fileName)
    };
  }

  /**
   * 主策略 react-input；仅当未触发上传 API 时才试 drop。
   * 成功条件：DOM 芯片信号增加 或 upload_file 返回 ok。
   */
  async function assignOneFileWithVerify(file, fileName) {
    installUploadHook();

    async function tryOnce(id, runFn) {
      var beforeSignals = countAttachmentSignals(fileName);
      var beforeUploads = uploadHook.okCount;
      var fired = false;
      try {
        fired = !!runFn();
      } catch (e) {
        fired = false;
      }
      if (!fired) return { ok: false, fired: false, id: id };
      var waited = await waitAttachSuccess(fileName, beforeSignals, beforeUploads, 12000);
      if (waited.ok) {
        return {
          ok: true,
          strategy: id + '/' + waited.via,
          before: beforeSignals,
          after: waited.after,
          uploads: waited.uploads
        };
      }
      return {
        ok: false,
        fired: true,
        id: id,
        detail: waited,
        uploadDelta: uploadHook.okCount - beforeUploads
      };
    }

    var primary = await tryOnce('react-input', function () {
      var r = setInputFilesOnly([file]);
      if (!r.ok) return false;
      if (invokeReactChange(r.input)) return true;
      // 原生 change 兜底（Chromium / 部分 WebKit）
      try {
        r.input.dispatchEvent(new Event('change', { bubbles: true }));
        r.input.dispatchEvent(new Event('input', { bubbles: true }));
      } catch (e) {}
      var p = r.input.parentElement;
      for (var d = 0; d < 6 && p; d++, p = p.parentElement) {
        if (invokeReactChange(p)) return true;
      }
      // 只要 files 赋上了就视为已触发（等 upload / DOM）
      return !!(r.input.files && r.input.files.length);
    });
    if (primary.ok) return primary;

    // 已打到上传 API：绝不再 drop，避免叠传
    if (primary.uploadDelta > 0) {
      return {
        ok: true,
        strategy: 'react-input/upload_api-late',
        before: 0,
        after: countAttachmentSignals(fileName),
        uploads: uploadHook.okCount
      };
    }

    // 主策略已触发但无上传：清一下再 drop
    if (primary.fired) {
      await apiClearAttachmentsSync();
      await sleep(250);
    }

    var secondary = await tryOnce('drop', function () {
      return dropFilesOnComposer([file]);
    });
    if (secondary.ok) return secondary;

    return {
      ok: false,
      error: 'attach_failed',
      detail: 'no strategy produced attachment chip',
      debug: {
        primary: primary,
        secondary: secondary,
        signals: countAttachmentSignals(fileName),
        uploads: uploadHook.okCount,
        rootHas: textMentionsName(composerText(), fileName),
        bodyHas: textMentionsName(((document.body && document.body.innerText) || ''), fileName),
        fileName: fileName
      }
    };
  }

  async function apiClearAttachmentsSync() {
    var root = composerRoot(findInput());
    if (!root) return { ok: false, cleared: 0 };
    var n = 0;
    for (var round = 0; round < 10; round++) {
      var closes = root.querySelectorAll(
        'div._8402d8c, [class*="8402"], button[aria-label*="删除"], button[aria-label*="移除"]'
      );
      // 也点附件卡右上角可聚焦的小叉
      if (!closes.length) {
        var cards = root.querySelectorAll('[class*="25c7358"], [class*="dafb6286"]');
        for (var c = 0; c < cards.length; c++) {
          var btns = cards[c].querySelectorAll('[tabindex], [role="button"], .ds-icon');
          if (btns.length) closes = btns;
        }
      }
      if (!closes.length) break;
      for (var i = 0; i < closes.length; i++) {
        try {
          closes[i].click();
          n += 1;
        } catch (e) {}
      }
      await sleep(120);
    }
    return { ok: true, cleared: n };
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

  api.probeAttachments = function () {
    var fi = findFileInput();
    var input = findInput();
    return {
      ok: !!(fi && input),
      supported: !!fi,
      hasFileInput: !!fi,
      accept: fi ? String(fi.accept || '') : '',
      multiple: !!(fi && fi.multiple),
      detail: !input ? 'input not found' : !fi ? 'file input not found' : 'ok'
    };
  };

  api.attachFiles = async function (specs) {
    var list = Array.isArray(specs) ? specs : [];
    if (!list.length) return { ok: false, error: 'empty files' };
    var strategies = [];
    for (var i = 0; i < list.length; i++) {
      var f = fileFromSpec(list[i]);
      if (!f) {
        return { ok: false, error: 'bad file spec: ' + ((list[i] && list[i].name) || i) };
      }
      var r = await assignOneFileWithVerify(f, f.name);
      if (!r.ok) {
        return {
          ok: false,
          error: r.error || 'attach_failed',
          detail: r.detail,
          debug: r.debug || null,
          accepted: i,
          strategies: strategies
        };
      }
      strategies.push(r.strategy);
      // 多文件之间稍等，避免 DeepSeek 合并/竞态
      if (i + 1 < list.length) await sleep(350);
    }
    return { ok: true, accepted: list.length, strategies: strategies };
  };

  api.attachmentsState = function (expectedNames) {
    var names = expectedNames || [];
    var items = attachmentItemsForNames(names);
    var allReady =
      names.length > 0 &&
      items.length === names.length &&
      items.every(function (it) {
        return it.ready;
      });
    return {
      items: items,
      allReady: allReady,
      uploading: looksUploading(composerRoot(findInput()))
    };
  };

  api.waitAttachmentsReady = async function (expectedNames, opts) {
    opts = opts || {};
    var timeoutMs = opts.timeoutMs != null ? opts.timeoutMs : 30000;
    var names = expectedNames || [];
    var start = Date.now();
    var last = null;
    while (Date.now() - start < timeoutMs) {
      last = api.attachmentsState(names);
      if (last.allReady && !last.uploading) {
        return { ok: true, items: last.items };
      }
      await sleep(200);
    }
    return {
      ok: false,
      error: 'attach_timeout',
      items: last ? last.items : []
    };
  };

  api.clearAttachments = async function () {
    return apiClearAttachmentsSync();
  };

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
      await sleep(250);
    }
    return {
      ok: false,
      error: 'timeout',
      text: readLastAssistant().text,
      sawBusy: sawBusy,
      count: readLastAssistant().count
    };
  };

  api.attachAndSendAndWait = async function (text, specs, opts) {
    opts = opts || {};
    var probe = api.probeAttachments();
    if (!probe.supported) {
      return { ok: false, phase: 'attach', error: 'attachments_unsupported', detail: probe.detail };
    }
    var list = Array.isArray(specs) ? specs : [];
    var names = list.map(function (s) {
      return s && s.name ? String(s.name) : '';
    }).filter(Boolean);

    function jobProgress(phase, detail) {
      try {
        if (window.__MeoAIBridgeJob && window.__MeoAIBridgeJob.status === 'running') {
          window.__MeoAIBridgeJob.phase = phase;
          window.__MeoAIBridgeJob.detail = detail || null;
        }
      } catch (e) {}
    }

    if (list.length) {
      jobProgress('attach', 'clear previous');
      await api.clearAttachments();
      await sleep(200);

      jobProgress('attach', 'uploading ' + names.join(','));
      var attached = await api.attachFiles(list);
      if (!attached.ok) {
        return {
          ok: false,
          phase: 'attach',
          error: attached.error || 'attach_failed',
          detail: attached.detail,
          debug: attached.debug || null,
          strategies: attached.strategies
        };
      }
      // attachFiles 已等芯片出现；再确认非「上传中」
      jobProgress('attach', 'waiting settle');
      var ready = await api.waitAttachmentsReady(names, {
        timeoutMs: opts.attachTimeoutMs != null ? opts.attachTimeoutMs : 15000
      });
      if (!ready.ok) {
        return {
          ok: false,
          phase: 'attach',
          error: ready.error || 'attach_timeout',
          items: ready.items,
          strategies: attached.strategies,
          detail: '附件芯片未就绪'
        };
      }
      await sleep(300);
    }

    var body = (text == null ? '' : String(text));
    if (!body.trim() && names.length) {
      body = '请查看附件';
    }
    jobProgress('send', 'set input');

    // 附件就绪后再填字；发送按钮可能短暂 disabled，轮询可点
    var input = findInput();
    if (!input) return { ok: false, phase: 'send', error: 'input not found' };

    function fillPrompt() {
      var el = findInput();
      if (!el) return false;
      var ok = AIBridgeRuntime.nativeSetValue(el, body);
      // 再捅一次 React onChange，防止受控组件吞值
      try {
        invokeReactChange(el);
      } catch (e) {}
      return ok;
    }

    if (!fillPrompt()) {
      return { ok: false, phase: 'send', error: 'setInput failed' };
    }
    await sleep(350);
    var curVal = ((findInput() && findInput().value) || '').trim();
    if (body.trim() && curVal.indexOf(body.trim().slice(0, Math.min(12, body.trim().length))) === -1) {
      fillPrompt();
      await sleep(250);
      curVal = ((findInput() && findInput().value) || '').trim();
      if (body.trim() && curVal.indexOf(body.trim().slice(0, Math.min(12, body.trim().length))) === -1) {
        return {
          ok: false,
          phase: 'send',
          error: 'setInput not sticky',
          detail: 'textarea value="' + curVal.slice(0, 40) + '"'
        };
      }
    }

    var baseline = readLastAssistant();
    var clicked = false;
    for (var s = 0; s < 30; s++) {
      var btn = findSendButton();
      if (btn) {
        btn.click();
        clicked = true;
        break;
      }
      await sleep(150);
    }
    if (!clicked) {
      // 回车兜底
      var el2 = findInput();
      if (el2) {
        try {
          el2.focus();
          var opts = { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true };
          el2.dispatchEvent(new KeyboardEvent('keydown', opts));
          el2.dispatchEvent(new KeyboardEvent('keypress', opts));
          el2.dispatchEvent(new KeyboardEvent('keyup', opts));
          clicked = true;
        } catch (e) {}
      }
    }
    if (!clicked) {
      return { ok: false, phase: 'send', error: 'send button not ready' };
    }

    jobProgress('wait', null);
    var timeoutMs = opts.timeoutMs != null ? opts.timeoutMs : 120000;
    var stableMs = opts.stableMs != null ? opts.stableMs : 1000;
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
      await sleep(250);
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
    var att = api.probeAttachments();
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
      attachmentsSupported: !!att.supported,
      hasFileInput: !!att.hasFileInput,
      href: location.href || '',
      detail: !hostOk ? 'host mismatch' : !input ? 'input not found (login?)' : 'ok'
    };
  };

  console.info('[AIBridge] deepseek adapter installed', api.probe());
})();
