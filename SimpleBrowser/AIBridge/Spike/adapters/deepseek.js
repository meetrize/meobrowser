/**
 * DeepSeek web chat adapter (chat.deepseek.com)
 * Revised 2026-10-28 after live probe on logged-in session.
 * Attachments 2026-10-29: DataTransfer → React onChange；就绪以 upload_file 为准。
 *
 * Findings:
 * - Composer: textarea / .aaff8b8f
 * - Send control: DIV.ds-button--primary (not <button>, often no aria-label)
 * - Assistant bubble: .ds-markdown.ds-assistant-message-main-content (inside .ds-message)
 * - File input: input[type=file][multiple] inside composer (hidden)
 * - WKWebView 下勿依赖哈希 class 芯片；主信号 = POST /api/v0/file/upload_file ok
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

  // 主就绪信号：钩住官方 upload_file（WK 上哈希 class / 芯片文本不可靠）
  var uploadHook = window.__MeoAIBridgeUploadHook;
  if (!uploadHook) {
    uploadHook = { okCount: 0, lastAt: 0, installed: false };
    window.__MeoAIBridgeUploadHook = uploadHook;
  }

  function noteUploadOk() {
    uploadHook.okCount += 1;
    uploadHook.lastAt = Date.now();
  }

  function installUploadHook() {
    if (uploadHook.installed) return;
    uploadHook.installed = true;
    try {
      var origFetch = window.fetch;
      if (typeof origFetch === 'function') {
        window.fetch = function (input) {
          var url = '';
          try {
            url = typeof input === 'string' ? input : (input && input.url) || '';
          } catch (e1) {}
          var p = origFetch.apply(this, arguments);
          if (/\/api\/v0\/file\/upload_file/.test(url)) {
            return Promise.resolve(p).then(function (res) {
              if (res && res.ok) noteUploadOk();
              return res;
            });
          }
          return p;
        };
      }
    } catch (e2) {}
    try {
      var XO = window.XMLHttpRequest;
      if (XO && XO.prototype) {
        var open = XO.prototype.open;
        var send = XO.prototype.send;
        XO.prototype.open = function (method, url) {
          try {
            this.__meoUpload = /\/api\/v0\/file\/upload_file/.test(String(url || ''));
          } catch (e3) {
            this.__meoUpload = false;
          }
          return open.apply(this, arguments);
        };
        XO.prototype.send = function () {
          if (this.__meoUpload) {
            this.addEventListener('load', function () {
              if (this.status >= 200 && this.status < 300) noteUploadOk();
            });
          }
          return send.apply(this, arguments);
        };
      }
    } catch (e4) {}
  }
  installUploadHook();

  function looksUploading() {
    var root = composerRoot(findInput());
    if (!root) return false;
    return /上传中|uploading|解析中/i.test((root.innerText || '') + '');
  }

  function composerMentionsName(name) {
    if (!name) return false;
    var root = composerRoot(findInput());
    var text = ((root && root.innerText) || '') + '';
    if (text.indexOf(name) !== -1) return true;
    var dot = name.lastIndexOf('.');
    if (dot > 0 && text.indexOf(name.slice(0, dot)) !== -1) return true;
    return false;
  }

  function recentUploadOk(sinceCount) {
    return uploadHook.okCount > sinceCount;
  }

  function attachmentReady(name) {
    if (looksUploading()) return false;
    if (uploadHook.okCount > 0 && Date.now() - uploadHook.lastAt < 20000) return true;
    return composerMentionsName(name);
  }

  function setInputFilesOnly(fileList) {
    var fi = findFileInput();
    if (!fi) return { ok: false, error: 'file input not found' };
    var dt = new DataTransfer();
    for (var i = 0; i < fileList.length; i++) dt.items.add(fileList[i]);
    try {
      fi.files = dt.files;
    } catch (e) {
      return { ok: false, error: 'cannot assign files' };
    }
    return { ok: true, input: fi };
  }

  function fireFileInput(file) {
    var r = setInputFilesOnly([file]);
    if (!r.ok) return false;
    if (invokeReactChange(r.input)) return true;
    try {
      r.input.dispatchEvent(new Event('change', { bubbles: true }));
    } catch (e) {}
    var p = r.input.parentElement;
    for (var d = 0; d < 6 && p; d++, p = p.parentElement) {
      if (invokeReactChange(p)) return true;
    }
    return !!(r.input.files && r.input.files.length);
  }

  async function waitUploadOrChip(fileName, beforeUploads, timeoutMs) {
    var start = Date.now();
    while (Date.now() - start < timeoutMs) {
      if (recentUploadOk(beforeUploads)) {
        await sleep(300);
        return { ok: true, via: 'upload_api' };
      }
      if (composerMentionsName(fileName) && !looksUploading()) {
        return { ok: true, via: 'dom' };
      }
      await sleep(150);
    }
    return { ok: false, uploads: uploadHook.okCount - beforeUploads };
  }

  /** 主路径：React file input；仅未打到 upload_file 时才 drop，避免叠传 */
  async function assignOneFileWithVerify(file, fileName) {
    installUploadHook();

    async function tryOnce(id, runFn) {
      var beforeUploads = uploadHook.okCount;
      var fired = false;
      try {
        fired = !!runFn();
      } catch (e) {
        fired = false;
      }
      if (!fired) return { ok: false, fired: false, uploadDelta: 0 };
      var waited = await waitUploadOrChip(fileName, beforeUploads, 12000);
      if (waited.ok) {
        return { ok: true, strategy: id + '/' + waited.via, uploadDelta: uploadHook.okCount - beforeUploads };
      }
      return { ok: false, fired: true, uploadDelta: uploadHook.okCount - beforeUploads };
    }

    var primary = await tryOnce('react-input', function () {
      return fireFileInput(file);
    });
    if (primary.ok || primary.uploadDelta > 0) {
      return primary.ok
        ? primary
        : { ok: true, strategy: 'react-input/upload_api-late' };
    }

    if (primary.fired) {
      await apiClearAttachmentsSync();
      await sleep(200);
    }

    var secondary = await tryOnce('drop', function () {
      return dropFilesOnComposer([file]);
    });
    if (secondary.ok || secondary.uploadDelta > 0) {
      return secondary.ok ? secondary : { ok: true, strategy: 'drop/upload_api-late' };
    }

    return { ok: false, error: 'attach_failed', detail: 'upload_file not observed' };
  }

  async function apiClearAttachmentsSync() {
    var root = composerRoot(findInput());
    if (!root) return { ok: false, cleared: 0 };
    var n = 0;
    for (var round = 0; round < 8; round++) {
      var closes = root.querySelectorAll(
        'div._8402d8c, [class*="8402"], button[aria-label*="删除"], button[aria-label*="移除"]'
      );
      if (!closes.length) break;
      for (var i = 0; i < closes.length; i++) {
        try {
          closes[i].click();
          n += 1;
        } catch (e) {}
      }
      await sleep(100);
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
          detail: r.detail || null,
          accepted: i,
          strategies: strategies
        };
      }
      strategies.push(r.strategy || 'ok');
      if (i + 1 < list.length) await sleep(350);
    }
    return { ok: true, accepted: list.length, strategies: strategies };
  };

  api.attachmentsState = function (expectedNames) {
    var names = expectedNames || [];
    var uploading = looksUploading();
    var items = names.map(function (name) {
      var ready = attachmentReady(name);
      return { name: name, ready: ready, error: null };
    });
    var allReady =
      names.length > 0 &&
      items.every(function (it) {
        return it.ready;
      });
    return { items: items, allReady: allReady, uploading: uploading };
  };

  api.waitAttachmentsReady = async function (expectedNames, opts) {
    opts = opts || {};
    var timeoutMs = opts.timeoutMs != null ? opts.timeoutMs : 15000;
    var names = expectedNames || [];
    var start = Date.now();
    var last = null;
    while (Date.now() - start < timeoutMs) {
      last = api.attachmentsState(names);
      if (last.allReady && !last.uploading) return { ok: true, items: last.items };
      await sleep(200);
    }
    return { ok: false, error: 'attach_timeout', items: last ? last.items : [] };
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
      await sleep(150);

      jobProgress('attach', 'uploading ' + names.join(','));
      var attached = await api.attachFiles(list);
      if (!attached.ok) {
        return {
          ok: false,
          phase: 'attach',
          error: attached.error || 'attach_failed',
          detail: attached.detail,
          strategies: attached.strategies
        };
      }
      // attachFiles 已等 upload；此处只等「上传中」消失
      jobProgress('attach', 'waiting settle');
      var settleDeadline = Date.now() + (opts.attachTimeoutMs != null ? opts.attachTimeoutMs : 10000);
      while (Date.now() < settleDeadline && looksUploading()) await sleep(200);
      if (looksUploading()) {
        return {
          ok: false,
          phase: 'attach',
          error: 'attach_timeout',
          strategies: attached.strategies,
          detail: '仍在上传中'
        };
      }
      await sleep(200);
    }

    var body = text == null ? '' : String(text);
    if (!body.trim() && names.length) body = '请查看附件';
    jobProgress('send', 'set input');

    if (!findInput()) return { ok: false, phase: 'send', error: 'input not found' };

    function fillPrompt() {
      var el = findInput();
      if (!el) return false;
      var ok = AIBridgeRuntime.nativeSetValue(el, body);
      try {
        invokeReactChange(el);
      } catch (e) {}
      return ok;
    }

    if (!fillPrompt()) return { ok: false, phase: 'send', error: 'setInput failed' };
    await sleep(300);
    var peek = ((findInput() && findInput().value) || '').trim();
    var needle = body.trim().slice(0, Math.min(12, body.trim().length));
    if (needle && peek.indexOf(needle) === -1) {
      fillPrompt();
      await sleep(200);
      peek = ((findInput() && findInput().value) || '').trim();
      if (peek.indexOf(needle) === -1) {
        return { ok: false, phase: 'send', error: 'setInput not sticky' };
      }
    }

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
      var el2 = findInput();
      if (el2) {
        try {
          el2.focus();
          var keyOpts = { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true };
          el2.dispatchEvent(new KeyboardEvent('keydown', keyOpts));
          el2.dispatchEvent(new KeyboardEvent('keyup', keyOpts));
          clicked = true;
        } catch (e) {}
      }
    }
    if (!clicked) return { ok: false, phase: 'send', error: 'send button not ready' };

    jobProgress('wait', null);
    // 已点击发送：复用 sendAndWait 的等待逻辑（跳过再次 setInput）
    var timeoutMs = opts.timeoutMs != null ? opts.timeoutMs : 120000;
    var stableMs = opts.stableMs != null ? opts.stableMs : 1000;
    var baseline = readLastAssistant();
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
