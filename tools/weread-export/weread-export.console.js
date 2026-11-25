/*
 * 微信读书网页版 · 整本书导出 Markdown
 * ---------------------------------------------------------------------------
 * 用法：
 *   1. Chrome / Edge 打开 https://weread.qq.com/web/reader/... 阅读页并登录
 *      （会员卡书籍 / 已购章节才能导出）
 *   2. F12 → Console，粘贴本文件全部内容并回车
 *      Chrome 首次粘贴可能要求先手动输入 allow pasting
 *   3. 脚本会：点目录 → 逐页翻页 → 抓取每页正文 → 拼成整章 → 完成后下载 <书名>.md
 *   4. 中途想停：__wereadExport.stop()
 *
 * 原理（两种渲染模式都支持）：
 *   - 双栏 / 翻页模式：正文是画在 <canvas> 上的，DOM 里没有文字。
 *     脚本 hook CanvasRenderingContext2D.fillText / clearRect，
 *     记录每一笔绘制（文本 + 坐标），按 y 分行、按 x 排序还原成页面文本。
 *   - 上下滚动模式：正文是 DOM 里的 .passage-content，直接读 innerText。
 *
 * 不请求接口、不解密、不绕过付费，只读取当前账号有权阅读的内容。
 * 导出内容仅供个人阅读/笔记使用，请遵守微信读书用户协议与著作权法。
 */

(() => {
  'use strict';

  /* =========================== 可调参数 =========================== */

  const CONFIG = {
    AUTO_RUN: true,          // 粘贴后是否立刻开始
    TOC_LEVEL: 0,            // 以目录的哪一层作为「章」。0 = 自动取最浅一层
    MAX_PAGES: 400,          // 单章最多翻页次数（防止死循环）
    MAX_WAIT_MS: 25000,      // 单章首次加载最长等待
    RESUME: true,            // 读取 localStorage 上次进度
    SKIP_LOCKED: true,       // 跳过目录里带锁的章节
    LIMIT: 0,                // >0 时只导出前 N 章，建议先 LIMIT: 2 试跑
    DEBUG: false,            // 打印每页字数 / 前 60 字
    PAGER: 'keyboard',       // 翻页方式：'keyboard'（默认，风控不记鼠标点击）或 'button'

    // —— 节奏控制：都在区间内随机，模拟人工，降低被限流/卡死的概率 ——
    PAGE_TURN_MIN_MS: 1000,      // 每次翻页后至少等多久
    PAGE_TURN_MAX_MS: 2500,      // 每次翻页后最多等多久
    CHAPTER_DELAY_MIN_MS: 2500,  // 每章之间至少等多久
    CHAPTER_DELAY_MAX_MS: 6000,
    LONG_PAUSE_EVERY: 15,        // 每翻 N 页多歇一次
    LONG_PAUSE_MIN_MS: 8000,
    LONG_PAUSE_MAX_MS: 16000,

    // —— 异常处理 ——
    STUCK_WAIT_MS: 12000,        // 翻页后一直没变化 / 一直 loading 的最长等待
    RETRY_PER_CHAPTER: 2,        // 单章加载异常时的重试次数
    RETRY_WAIT_MIN_MS: 8000,     // 重试前等待（随机区间）
    RETRY_WAIT_MAX_MS: 20000,
  };

  const TOC_ROOT = '.readerCatalog_list';
  const TOC_ITEM = '.readerCatalog_list_item';
  const TOC_TITLE = '.readerCatalog_list_item_title_text';

  const NEXT_PAGE_BTN = '.renderTarget_pager_button_right';
  const CANVAS_SCOPE = '.wr_canvasContainer canvas';

  const NOISE_LINES = new Set([
    '上一页', '下一页', '上一章', '下一章', '目录', '加入书架', '登录',
    '点评本书', '写想法', '复制', '划线', '查询', '确定', '取消', '关闭',
    '全书完', '开启书友想法', '上下滚动阅读',
  ]);

  /* ============================= 工具 ============================= */

  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const log = (...a) => console.log('%c[weread]', 'color:#0a84ff;font-weight:bold', ...a);
  const warn = (...a) => console.warn('%c[weread]', 'color:#ff9f0a;font-weight:bold', ...a);

  // 区间随机
  const rand = (min, max) => Math.round(min + Math.random() * Math.max(0, max - min));
  const pagePause = () => rand(CONFIG.PAGE_TURN_MIN_MS, CONFIG.PAGE_TURN_MAX_MS);
  const chapterPause = () => rand(CONFIG.CHAPTER_DELAY_MIN_MS, CONFIG.CHAPTER_DELAY_MAX_MS);

  // 微信读书的目录项点击处理器要求 event.clientX && event.clientY，
  // element.click() 的坐标是 0,0 会被直接忽略，所以自己派发带坐标的鼠标事件。
  function realClick(el) {
    if (!el) return false;
    let x = 1;
    let y = 1;
    try {
      const r = el.getBoundingClientRect();
      if (r && r.width > 0 && r.height > 0) {
        x = Math.round(r.left + r.width / 2);
        y = Math.round(r.top + r.height / 2);
      }
    } catch (_) {}
    const opts = {
      bubbles: true,
      cancelable: true,
      composed: true,
      view: window,
      detail: 1,
      button: 0,
      buttons: 0,
      clientX: x,
      clientY: y,
      screenX: x,
      screenY: y,
    };
    // 只派发 click：目录/翻页都是 @click 绑定，避免 mousedown 被正文的划词逻辑误当拖选
    try {
      el.dispatchEvent(new MouseEvent('click', opts));
    } catch (_) {}
    return true;
  }

  const state = {
    running: false,
    stop: false,
    chapters: [],
    failed: [],
    skipped: [],
    bookTitle: '',
    author: '',
    pageCount: 0,
    engine: '',
    needPay: false,
    retries: 0,
    fatalProblem: '',
    crossedBoundary: false,
  };

  const bookId = (location.pathname.match(/\/web\/reader\/([0-9a-z]+)/i) || [])[1] || 'default';
  // v2：旧版（只读 DOM）的进度里有残缺章节，换 key 避免误用
  const storeKey = 'weread-export:v2:' + bookId;

  /* ============================= 目录 ============================= */

  function tocItems() {
    return Array.from(document.querySelectorAll(`${TOC_ROOT} ${TOC_ITEM}`));
  }

  function readToc() {
    return tocItems()
      .map((li, index) => {
        const inner = li.querySelector('.readerCatalog_list_item_inner') || li;
        const titleEl = li.querySelector(TOC_TITLE);
        const m = (inner.className || '').match(/readerCatalog_list_item_level_(\d+)/);
        return {
          index,
          title: (titleEl ? titleEl.textContent : '').trim(),
          level: m ? Number(m[1]) : 1,
          locked:
            li.classList.contains('readerCatalog_list_item_disabled') ||
            !!li.querySelector('.readerCatalog_list_item_lock'),
        };
      })
      .filter((x) => x.title);
  }

  function selectedTitle() {
    const el = document.querySelector(`${TOC_ROOT} .readerCatalog_list_item_selected ${TOC_TITLE}`);
    return el ? el.textContent.trim() : '';
  }

  async function ensureToc() {
    if (tocItems().length) return;
    const btn = Array.from(document.querySelectorAll('div,span,button,a')).find((el) => {
      const t = (el.textContent || '').trim();
      return t === '目录' && el.offsetParent !== null;
    });
    if (btn) realClick(btn);
    for (let i = 0; i < 25 && !tocItems().length; i++) await sleep(200);
  }

  function currentChapterKey() {
    return location.pathname;
  }

  /* ====================== canvas 文字捕获（核心） ====================== */

  const CAP = {
    installed: false,
    frames: new WeakMap(), // canvas -> { items: [{t,x,y,font,alpha,fill}] }
  };

  function installCanvasHook() {
    if (CAP.installed) return true;
    const P = window.CanvasRenderingContext2D && window.CanvasRenderingContext2D.prototype;
    if (!P || typeof P.fillText !== 'function') return false;

    const origFillText = P.fillText;
    const origClearRect = P.clearRect;

    P.clearRect = function (x, y, w, h) {
      try {
        const c = this.canvas;
        // 清掉大半张画布 = 新的一页开始绘制；局部清空（高亮重绘）不算
        if (c && x <= 0 && y <= 0 && w >= c.width * 0.6 && h >= c.height * 0.6) {
          CAP.frames.set(c, { items: [], startedAt: performance.now() });
        }
      } catch (_) {}
      return origClearRect.apply(this, arguments);
    };

    P.fillText = function (text, x, y) {
      try {
        const s = text == null ? '' : String(text);
        if (s.trim()) {
          const c = this.canvas;
          if (c) {
            let f = CAP.frames.get(c);
            if (!f) {
              f = { items: [], startedAt: performance.now() };
              CAP.frames.set(c, f);
            }
            f.items.push({
              t: s,
              x: Number(x) || 0,
              y: Number(y) || 0,
              font: this.font,
              alpha: typeof this.globalAlpha === 'number' ? this.globalAlpha : 1,
              fill: String(this.fillStyle || ''),
            });
          }
        }
      } catch (_) {}
      return origFillText.apply(this, arguments);
    };

    // 有的代码用 canvas.width = ... 清空画布，也会开新的一页
    try {
      const descW = Object.getOwnPropertyDescriptor(HTMLCanvasElement.prototype, 'width');
      if (descW && descW.set) {
        Object.defineProperty(HTMLCanvasElement.prototype, 'width', {
          configurable: true,
          get: descW.get,
          set(v) {
            descW.set.call(this, v);
            CAP.frames.set(this, { items: [], startedAt: performance.now() });
          },
        });
      }
      const descH = Object.getOwnPropertyDescriptor(HTMLCanvasElement.prototype, 'height');
      if (descH && descH.set) {
        Object.defineProperty(HTMLCanvasElement.prototype, 'height', {
          configurable: true,
          get: descH.get,
          set(v) {
            descH.set.call(this, v);
            CAP.frames.set(this, { items: [], startedAt: performance.now() });
          },
        });
      }
    } catch (_) {}

    CAP.installed = true;
    return true;
  }

  // 防截屏水印：数字串 / 低透明度
  function isWatermark(it) {
    const compact = it.t.replace(/\s+/g, '');
    if (compact.length >= 6 && /^[\d·:.\/\-]+$/.test(compact)) return true;
    if (it.alpha < 0.95) return true;
    const m = /^rgba?\([^)]*,\s*([\d.]+)\s*\)$/.exec(it.fill);
    if (m && Number(m[1]) < 0.9) return true;
    return false;
  }

  function fontPx(font) {
    const m = /(\d+(?:\.\d+)?)px/.exec(font || '');
    return m ? parseFloat(m[1]) : 16;
  }

  // 一帧绘制 -> 若干行文本
  function frameToLines(frame) {
    if (!frame || !frame.items.length) return [];
    const items = frame.items.filter((it) => !isWatermark(it));
    if (!items.length) return [];

    const lines = [];
    for (const it of items) {
      const tol = Math.max(3, fontPx(it.font) * 0.35);
      let line = lines.find((l) => Math.abs(l.y - it.y) <= tol);
      if (!line) {
        line = { y: it.y, parts: [] };
        lines.push(line);
      }
      line.parts.push(it);
    }

    lines.sort((a, b) => a.y - b.y);
    const out = [];
    for (const line of lines) {
      const seen = new Set();
      let s = '';
      for (const p of line.parts.sort((a, b) => a.x - b.x)) {
        const key = `${Math.round(p.x)}|${p.t}`;
        if (seen.has(key)) continue;
        seen.add(key);
        s += p.t;
      }
      s = s.replace(/[\u200b-\u200f\u2060\ufeff]/g, '').replace(/\u00a0/g, ' ').trimEnd();
      if (s.trim()) out.push(s);
    }
    return out;
  }

  function canvasPages(since = 0) {
    const canvases = Array.from(document.querySelectorAll(CANVAS_SCOPE));
    if (!canvases.length) return [];
    const ordered = canvases
      .map((c) => {
        let left = 0;
        try {
          left = c.getBoundingClientRect().left;
        } catch (_) {}
        return { c, left };
      })
      .sort((a, b) => a.left - b.left);

    const pages = [];
    for (const { c } of ordered) {
      const frame = CAP.frames.get(c);
      if (!frame || (since && frame.startedAt < since)) continue;
      const lines = frameToLines(frame);
      if (lines.length) pages.push(lines.join('\n'));
    }
    return pages;
  }

  /* ======================= DOM 文本（滚动模式） ======================= */

  function domPageText() {
    const passages = Array.from(document.querySelectorAll('.renderTargetContainer .passage-content'));
    if (passages.length) {
      return passages.map((n) => n.innerText || n.textContent || '').join('\n');
    }
    const rt = document.querySelector('.renderTargetContainer');
    if (rt && (rt.innerText || '').trim()) return rt.innerText;
    const cc = document.querySelector('.readerChapterContent');
    return cc ? cc.innerText || '' : '';
  }

  function cleanPageText(text) {
    return text
      .replace(/\r/g, '')
      .replace(/[\u200b-\u200f\u2060\ufeff]/g, '')
      .replace(/\u00a0/g, ' ')
      .split('\n')
      .map((s) => s.trim())
      .filter((s) => s && !NOISE_LINES.has(s))
      .join('\n');
  }

  // 当前视图 -> 页面文本数组（since: 只接受该时间之后重绘的 canvas 页）
  function extractView(since = 0) {
    const cp = canvasPages(since);
    const canvasLen = cp.join('').length;
    const dom = cleanPageText(domPageText());
    if (canvasLen >= Math.max(10, dom.length)) return { pages: cp, engine: 'canvas' };
    return { pages: dom ? [dom] : [], engine: 'dom' };
  }

  function viewSignature(view) {
    return view.pages.join('\u0000');
  }

  const TERMINAL = /[。！？…；：”’」』）】.!?;:"')\]]$/;

  function stitchPages(pages, chapterTitle, bookTitle) {
    let result = '';
    for (const page of pages) {
      const lines = page
        .split('\n')
        .map((s) => s.trim())
        .filter((s) => s && s !== chapterTitle && s !== bookTitle);
      for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        if (i === 0 && result && !TERMINAL.test(result)) {
          result += line; // 上一页把同一段切断了，直接接上
        } else {
          result += (result ? '\n' : '') + line;
        }
      }
    }
    return result.replace(/\n{3,}/g, '\n\n').trim();
  }

  function promoteSubTitles(text, subTitleLevels) {
    return text
      .split('\n')
      .map((line) => {
        const level = subTitleLevels.get(line.trim());
        return level ? `${'#'.repeat(Math.min(6, 1 + level))} ${line.trim()}` : line;
      })
      .join('\n');
  }

  /* =========================== 翻页 / 跳章 =========================== */

  function pressNextPage() {
    if (CONFIG.PAGER === 'button') {
      const btn = document.querySelector(NEXT_PAGE_BTN);
      if (btn) {
        realClick(btn);
        return 'button';
      }
    }
    const ev = new KeyboardEvent('keydown', {
      key: 'ArrowRight',
      code: 'ArrowRight',
      keyCode: 39,
      which: 39,
      bubbles: true,
      cancelable: true,
    });
    try {
      Object.defineProperty(ev, 'keyCode', { get: () => 39 });
      Object.defineProperty(ev, 'which', { get: () => 39 });
    } catch (_) {}
    document.dispatchEvent(ev);
    return 'key';
  }

  function visibleDialogText() {
    const nodes = document.querySelectorAll(
      '.wr_dialog, .wr_dialog_mask, .reader_common_dialog, .payDialog, .readerLoginGuide, [class*="readerLoginGuide"]'
    );
    const parts = [];
    nodes.forEach((n) => {
      if (n.offsetParent !== null) {
        const t = (n.innerText || '').trim();
        if (t) parts.push(t);
      }
    });
    return parts.join(' ');
  }

  const PAYWALL_TEXT = /仅支持付费会员使用|付费会员专享|扫码开通付费会员|开通会员|购买本章|购买本书|试读结束|登录后/;

  function paywallDialogText() {
    const t = visibleDialogText();
    return /付费会员专享|开通会员|会员卡|购买本章|购买本书|试读结束|扫码登录/.test(t) ? t : '';
  }

  function paywallHint() {
    const t = paywallDialogText();
    if (t) return `（页面提示：${t.slice(0, 60).replace(/\s+/g, ' ')}）`;
    if (!document.querySelector(CANVAS_SCOPE) && !document.querySelector('.passage-content')) {
      return '（未发现正文容器，可能还在加载）';
    }
    return '';
  }

  // 付费/未解锁页面会被当成“正文”抓下来，这里尽量拦住
  function looksLikePaywall(text) {
    return text.length < 300 && PAYWALL_TEXT.test(text);
  }

  // 阅读器自己的错误层（下架 / 版权限制 / 加载失败）
  function problemLayerText() {
    const el = document.querySelector('.readerErrorLayer');
    return el ? (el.innerText || '').trim() : '';
  }

  function isFatalProblem(text) {
    return /下架|版权原因|不支持在网页端阅读/.test(text);
  }

  function isLoadingLayer() {
    return !!document.querySelector('.readerChapterContentLoading');
  }

  function forceRepaint() {
    try {
      window.dispatchEvent(new Event('resize'));
    } catch (_) {}
  }

  async function gotoChapter(entry) {
    const atBoundary = state.crossedBoundary;
    state.crossedBoundary = false;
    const beforeKey = currentChapterKey();
    const beforeSelected = selectedTitle();
    const sameChapterBefore = beforeSelected === entry.title;
    const beforeSig = viewSignature(extractView());

    const li = tocItems()[entry.index];
    if (!li) throw new Error('目录项已失效（目录被重新渲染了）');
    const target = li.querySelector('.readerCatalog_list_item_inner') || li;
    if (target.scrollIntoView) target.scrollIntoView({ block: 'nearest' });
    const since = performance.now();
    realClick(target);

    const navDeadline = Date.now() + 8000;
    let navigated = false;
    let clickedAgain = false;
    let sigChecked = false;
    const clickAt = Date.now();
    while (Date.now() < navDeadline && !state.stop) {
      if (selectedTitle() === entry.title || currentChapterKey() !== beforeKey) {
        navigated = true;
        break;
      }
      // 目录项与当前章节同属一章时，阅读器不会改 URL，只会滚到对应位置：
      // 此时正文签名会变，也算跳章成功
      if (!sigChecked && Date.now() - clickAt > 1200) {
        sigChecked = true;
        const sigNow = viewSignature(extractView());
        if (sigNow && sigNow !== beforeSig) {
          navigated = true;
          break;
        }
      }
      // 一次不成功再补一次（面板未开/刚加载完时偶尔会漏）
      if (!clickedAgain && Date.now() - clickAt > 2500) {
        clickedAgain = true;
        realClick(target);
      }
      await sleep(rand(140, 220));
    }
    if (!navigated) {
      if (state.stop) return null;
      // 上一章是“翻页翻到底”结束的，说明我们现在就站在本章第一页
      if (atBoundary) {
        const v = extractView();
        if (v.pages.length) {
          log(`已在上一章末尾翻到「${entry.title}」开头，直接取当前页`);
          return v;
        }
      }
      throw new Error('目录点击没有反应' + paywallHint());
    }

    // 等正文稳定（且与跳章前不同）
    const deadline = Date.now() + CONFIG.MAX_WAIT_MS;
    let prevSig = null;
    let stable = 0;
    let last = null;
    while (Date.now() < deadline && !state.stop) {
      const prob = problemLayerText();
      if (prob && isFatalProblem(prob)) throw new Error('阅读器提示：' + prob.slice(0, 60));

      const view = extractView(since);
      const sig = viewSignature(view);
      if (sig) {
        if (sig === prevSig) {
          if (++stable >= 2) {
            // 内容跟跳章前一样，且不是「本来就在这一章」：可能还是上一章的残影
            if (sig === beforeSig && !sameChapterBefore) {
              stable = 0;
              prevSig = null;
            } else {
              return view;
            }
          }
        } else {
          stable = 0;
          prevSig = sig;
        }
        last = view;
      }
      await sleep(250);
    }
    if (last && viewSignature(last) === beforeSig && !sameChapterBefore) return null;
    return last;
  }

  /* =========================== 收集整章 =========================== */

  async function collectChapter(entry, nextEntryTitle, chapterTitles) {
    const first = await gotoChapter(entry);
    if (state.stop) return { pages: [], ended: false, stopped: true };
    if (!first || !first.pages.length) throw new Error('正文为空' + paywallHint());

    state.engine = state.engine || first.engine;
    const chKey = currentChapterKey();
    const startIdx = chapterTitles.indexOf(entry.title);
    const pages = [];
    const seen = new Set();
    const add = (list) => {
      for (const t of list) {
        if (t && !seen.has(t)) {
          seen.add(t);
          pages.push(t);
          if (CONFIG.DEBUG) log(`  + ${t.length} 字：${t.slice(0, 60).replace(/\n/g, ' / ')}`);
        }
      }
    };
    add(first.pages);

    let same = 0;
    let lastSig = viewSignature(first);
    let ended = false;

    for (let i = 0; i < CONFIG.MAX_PAGES; i++) {
      if (state.stop) return { pages, ended: false, stopped: true };

      const since = performance.now();
      pressNextPage();
      await sleep(pagePause());

      // 等这一页画完 / 跳到下一章；键盘没生效时自动退回点翻页按钮
      let softDeadline = Date.now() + 3000;
      const hardLimit = () => softDeadline + CONFIG.STUCK_WAIT_MS;
      let buttonTried = CONFIG.PAGER === 'button';
      let view = null;
      let sig = '';
      let turned = false;
      for (;;) {
        if (state.stop) break;
        if (chKey && currentChapterKey() !== chKey) {
          ended = true;
          state.crossedBoundary = true;
          break;
        }
        if (startIdx >= 0) {
          const selIdx = chapterTitles.indexOf(selectedTitle());
          if (selIdx > startIdx) {
            ended = true;
            state.crossedBoundary = true;
            break;
          }
        }
        view = extractView(since);
        sig = viewSignature(view);
        if (sig && sig !== lastSig) {
          turned = true;
          break;
        }

        // 页面报错：抛出，交给上层重试
        const prob = problemLayerText();
        if (prob) {
          state.fatalProblem = isFatalProblem(prob) ? prob : '';
          throw new Error('阅读器提示：' + prob.slice(0, 60));
        }

        // 键盘翻页没反应，退回点按钮（只试一次）
        if (!buttonTried && Date.now() > softDeadline) {
          buttonTried = true;
          const btn = document.querySelector(NEXT_PAGE_BTN);
          if (btn) {
            realClick(btn);
            softDeadline = Date.now() + 3000;
            continue;
          }
        }

        if (isLoadingLayer()) {
          // 还在加载，多等一会（可能是被限流）
          if (Date.now() > hardLimit()) throw new Error('加载超时（页面一直显示加载中）');
        } else if (Date.now() > softDeadline) {
          break;
        }
        await sleep(rand(180, 320));
      }
      if (state.stop) return { pages, ended: false, stopped: true };
      if (ended) break;

      if (!turned) {
        // 翻不动了：最后一章 / 单页模式 / 渲染没跟上
        if (++same >= 2) break;
        continue;
      }

      // 兜底：新一页开头就是下一章标题
      if (nextEntryTitle && view.pages.length) {
        const firstLine = view.pages[0].split('\n')[0].trim();
        if (firstLine === nextEntryTitle || firstLine.startsWith(nextEntryTitle)) {
          ended = true;
          state.crossedBoundary = true;
          break;
        }
      }

      same = 0;
      lastSig = sig;
      state.pageCount++;
      add(view.pages);

      // 隔一阵子多歇一会
      if (
        CONFIG.LONG_PAUSE_EVERY > 0 &&
        state.pageCount % CONFIG.LONG_PAUSE_EVERY === 0 &&
        CONFIG.LONG_PAUSE_MAX_MS > 0
      ) {
        const p = rand(CONFIG.LONG_PAUSE_MIN_MS, CONFIG.LONG_PAUSE_MAX_MS);
        log(`已翻 ${state.pageCount} 页，休息 ${Math.round(p / 1000)}s（降低被限流风险）`);
        await sleep(p);
      }
    }

    return { pages, ended, stopped: false };
  }

  /* =========================== 进度存储 =========================== */

  function loadProgress() {
    if (!CONFIG.RESUME) return {};
    try {
      return JSON.parse(localStorage.getItem(storeKey) || '{}') || {};
    } catch (_) {
      return {};
    }
  }

  function saveProgress() {
    try {
      const obj = {};
      state.chapters.forEach((c) => {
        if (c) obj[c.index] = { index: c.index, title: c.title, level: c.level, text: c.text };
      });
      localStorage.setItem(storeKey, JSON.stringify(obj));
    } catch (e) {
      warn('进度保存失败（可能超出 localStorage 容量），最终仍会下载', e);
    }
  }

  /* ============================= 输出 ============================= */

  function bookMeta() {
    const titleEl = document.querySelector('.readerCatalog_bookInfo_title_txt');
    const authorEl = document.querySelector('.readerCatalog_bookInfo_author');
    const title = ((titleEl && titleEl.textContent) || document.title || '')
      .replace(/\s*[-–—]\s*微信读书.*$/, '')
      .trim();
    const author = ((authorEl && authorEl.textContent) || '').trim();
    return { title, author };
  }

  function toMarkdown() {
    const meta = bookMeta();
    const lines = [];
    lines.push(`# ${meta.title || state.bookTitle || '未命名'}`);
    lines.push('');
    if (meta.author || state.author) lines.push(`> ${meta.author || state.author}`);
    lines.push(`> 来源：${location.origin}${location.pathname}`);
    lines.push('');
    lines.push('---');
    lines.push('');

    state.chapters
      .slice()
      .sort((a, b) => a.index - b.index)
      .forEach((c) => {
        lines.push(`${'#'.repeat(Math.min(6, 1 + (c.level || 1)))} ${c.title}`);
        lines.push('');
        if (c.text) {
          lines.push(c.text);
          lines.push('');
        }
      });

    if (state.skipped.length) {
      lines.push('---', '', '## 未导出（跳过：封面 / 未解锁 / 无法单独跳转）', '');
      state.skipped.forEach((t) => lines.push(`- ${t}`));
      lines.push('');
    }
    if (state.failed.length) {
      lines.push('## 未导出（抓取失败）', '');
      state.failed.forEach((t) => lines.push(`- ${t}`));
      lines.push('');
    }
    return lines.join('\n');
  }

  function download(filename) {
    const md = toMarkdown();
    const base = (filename || state.bookTitle || bookMeta().title || 'weread-book')
      .replace(/[\\/:*?"<>|]+/g, '_')
      .slice(0, 80);
    const blob = new Blob([md], { type: 'text/markdown;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${base}.md`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 10000);
    log(`已生成 ${base}.md（${md.length} 字符）`);
  }

  /* ============================= 主流程 ============================= */

  async function run() {
    if (state.running) {
      warn('已经在运行中，等待它结束，或先执行 __wereadExport.stop()');
      return;
    }
    state.running = true;
    state.stop = false;
    state.chapters = [];
    state.failed = [];
    state.skipped = [];
    state.pageCount = 0;
    state.engine = '';
    state.needPay = false;

    const meta = bookMeta();
    state.bookTitle = meta.title;
    state.author = meta.author;

    try {
      installCanvasHook();
      forceRepaint();
      await sleep(300);
      await ensureToc();
      const toc = readToc();
      if (!toc.length) {
        warn('没有找到目录。请先点开一次「目录」面板，再执行 __wereadExport.run()');
        return;
      }

      const chapterLevel =
        CONFIG.TOC_LEVEL > 0
          ? CONFIG.TOC_LEVEL
          : toc.reduce((min, x) => Math.min(min, x.level), Infinity);
      const chapters = toc.filter((x) => x.level === chapterLevel);
      const chapterTitles = chapters.map((x) => x.title);
      const subTitleLevels = new Map(
        toc.filter((x) => x.level > chapterLevel).map((x) => [x.title, x.level])
      );

      const progress = loadProgress();
      const validCached = (c) => c && typeof c.text === 'string' && c.text.length >= 50 && !looksLikePaywall(c.text);
      const cachedCount = Object.values(progress).filter(validCached).length;
      log(
        `《${state.bookTitle || '未知书名'}》目录 ${toc.length} 项，按第 ${chapterLevel} 层导出 ${chapters.length} 章` +
          (cachedCount ? `；发现上次进度 ${cachedCount} 章，将跳过` : '')
      );
      log(
        document.querySelector(CANVAS_SCOPE)
          ? '检测到双栏/翻页模式（canvas 渲染），将用绘制拦截取文。'
          : '未检测到 canvas 阅读器，按 DOM 取文。'
      );
      log('请保持这个标签页在前台可见。');

      let consecutiveFail = 0;
      let noReactionSkips = 0;
      const todo = CONFIG.LIMIT > 0 ? chapters.slice(0, CONFIG.LIMIT) : chapters;

      for (let ci = 0; ci < todo.length; ci++) {
        const entry = todo[ci];
        if (state.stop) {
          warn('已手动停止');
          break;
        }

        if (entry.locked && CONFIG.SKIP_LOCKED) {
          state.skipped.push(entry.title);
          continue;
        }

        const cached = progress[entry.index];
        if (validCached(cached)) {
          state.chapters.push(cached);
          continue;
        }

        state.fatalProblem = '';
        const nextTitle = todo[ci + 1] ? todo[ci + 1].title : '';
        let saved = false;
        let attempt = 0;
        let lastErr = '';
        let abort = false;
        let stopped = false;
        let skippedItem = false;

        while (!saved) {
          try {
            const r = await collectChapter(entry, nextTitle, chapterTitles);
            if (r.stopped) {
              stopped = true;
              break;
            }
            let text = stitchPages(r.pages, entry.title, state.bookTitle);
            text = promoteSubTitles(text, subTitleLevels);
            if (!text || text.length < 5) throw new Error('正文为空' + paywallHint());
            if (looksLikePaywall(text)) throw new Error('该章需要会员/购买才能阅读' + paywallHint());

            state.chapters.push({ index: entry.index, title: entry.title, level: entry.level, text });
            consecutiveFail = 0;
            noReactionSkips = 0;
            saveProgress();
            log(
              `✔ [${ci + 1}/${todo.length}] ${entry.title}（${r.pages.length} 页 / ${text.length} 字）` +
                (r.ended || ci === todo.length - 1 ? '' : ' ⚠ 可能未翻到章末')
            );
            saved = true;
          } catch (e) {
            lastErr = e.message;
            if (state.stop) {
              stopped = true;
              break;
            }

            const dlg = paywallDialogText();
            if (dlg) {
              state.needPay = true;
              warn(`检测到付费/登录弹窗（${dlg.slice(0, 40).replace(/\s+/g, ' ')}），已停止。请确认当前账号已开通会员卡或已购买这本书。`);
              abort = true;
              break;
            }
            if (state.fatalProblem) {
              warn(`阅读器提示：${state.fatalProblem}，已停止。`);
              abort = true;
              break;
            }

            // 「目录点击没反应」/「正文为空」多数不是真错：
            // 目录项和当前章节同属一章时阅读器会 no-op；扉页/封面类页面本来就没文字。
            const noReaction = lastErr.indexOf('目录点击没有反应') === 0;
            const emptyChapter = lastErr.indexOf('正文为空') === 0;
            if (noReaction && attempt === 0) {
              attempt++;
              const wait = rand(1500, 3000);
              warn(`… 目录没反应，${Math.round(wait / 1000)}s 后再点一次：${lastErr}`);
              await sleep(wait);
              continue;
            }
            if (noReaction || emptyChapter) {
              noReactionSkips++;
              skippedItem = true;
              state.skipped.push(entry.title);
              warn(
                emptyChapter
                  ? `⚠ ${entry.title}：没有正文（封面/图片页？），已跳过`
                  : `⚠ ${entry.title}：点击目录后没有跳转（可能与前一项同属一个章节），已跳过`
              );
              if (noReactionSkips >= 6) {
                warn('连续多章取不到正文，已停止。先执行 __wereadExport.debugNav(2) 排查。');
                abort = true;
              }
              break;
            }

            if (attempt < CONFIG.RETRY_PER_CHAPTER) {
              attempt++;
              state.retries++;
              const wait = rand(CONFIG.RETRY_WAIT_MIN_MS, CONFIG.RETRY_WAIT_MAX_MS);
              warn(`… 第 ${attempt} 次重试（先等 ${Math.round(wait / 1000)}s）：${lastErr}`);
              await sleep(wait);
              if (state.stop) {
                stopped = true;
                break;
              }
              if (!tocItems().length) {
                warn('页面阅读器已不可用，请刷新页面后重新粘贴脚本（进度已保存）。');
                abort = true;
                break;
              }
              continue;
            }
            break;
          }
        }

        if (stopped) {
          warn('已停止，本章未保存');
          break;
        }
        if (abort) break;
        if (skippedItem) {
          await sleep(chapterPause());
          continue;
        }
        if (!saved) {
          consecutiveFail++;
          state.failed.push(entry.title);
          warn(`✖ [${ci + 1}/${todo.length}] ${entry.title}：${lastErr}`);
          if (consecutiveFail >= 3) {
            warn('连续 3 章没有正文，已停止。先执行 __wereadExport.diagnose() 看当前页面状态。');
            break;
          }
        }

        const cp = chapterPause();
        if (CONFIG.DEBUG) log(`章间间隔 ${Math.round(cp / 1000)}s`);
        await sleep(cp);
      }

      log(
        `完成：成功 ${state.chapters.length} 章 / ${state.pageCount} 页，跳过 ${state.skipped.length} 章，失败 ${state.failed.length} 章` +
          (state.retries ? `，重试 ${state.retries} 次` : '')
      );
      if (state.failed.length) warn('失败章节：', state.failed);

      const ok = state.chapters.length;
      const bad = state.failed.length + state.skipped.length;
      if (ok === 0 || (bad > ok && ok < 3)) {
        warn('导出结果过少，已跳过自动下载。数据仍保留在内存/localStorage，确认无误后可执行 __wereadExport.download()。');
      } else {
        download();
      }
    } catch (e) {
      warn('运行出错：', e);
    } finally {
      state.running = false;
    }
  }

  /* ============================= 诊断 ============================= */

  // 只跑第 n 章（1 起），不写进度、不下载，用于快速验证
  async function testChapter(n = 1) {
    installCanvasHook();
    forceRepaint();
    await sleep(300);
    await ensureToc();
    const toc = readToc();
    if (!toc.length) {
      warn('没有找到目录，请先点开一次「目录」面板');
      return null;
    }
    const level = toc.reduce((m, x) => Math.min(m, x.level), Infinity);
    const chapters = toc.filter((x) => x.level === level);
    const entry = chapters[Math.max(0, (n | 0) - 1)];
    if (!entry) {
      warn(`没有第 ${n} 章`);
      return null;
    }

    log(`试跑：${entry.title} …`);
    try {
      const nextTitle = chapters[chapters.indexOf(entry) + 1]?.title || '';
      const r = await collectChapter(entry, nextTitle, chapters.map((x) => x.title));
      const text = stitchPages(r.pages, entry.title, state.bookTitle);
      log(`结果：${r.pages.length} 页 / ${text.length} 字，ended=${r.ended}，引擎=${state.engine || '?'}`);
      if (text) log('前 400 字：\n' + text.slice(0, 400));
      else warn('没抓到文本' + paywallHint());
      return { title: entry.title, pages: r.pages, text };
    } catch (e) {
      warn('试跑失败：' + e.message);
      return null;
    }
  }

  function diagnose() {
    const toc = readToc();
    const chapterLevel = toc.length ? toc.reduce((m, x) => Math.min(m, x.level), Infinity) : 0;
    log(`目录项 ${toc.length}，最浅层级 ${chapterLevel}，带锁 ${toc.filter((x) => x.locked).length}`);
    log(`当前选中：${selectedTitle() || '（无）'}；URL：${currentChapterKey()}`);
    log(`canvas hook：${CAP.installed ? '已安装' : '未安装'}；canvas 数量：${document.querySelectorAll(CANVAS_SCOPE).length}`);
    console.table(toc.slice(0, 8).map(({ index, title, level, locked }) => ({ index, title, level, locked })));

    const cp = canvasPages();
    log(`canvas 还原页数：${cp.length}，共 ${cp.join('').length} 字`);
    if (cp.length) log('canvas 文本片段：', cp[0].slice(0, 200));

    const dom = cleanPageText(domPageText());
    log(`DOM 文本：${dom.length} 字`, dom.slice(0, 120));

    const v = extractView();
    log(`当前取文引擎：${v.engine}，页数 ${v.pages.length}`);
    log(`下一页按钮：${document.querySelector(NEXT_PAGE_BTN) ? '存在' : '不存在'}`);
    log(`加载层：${isLoadingLayer() ? '正在加载' : '无'}；错误层：${problemLayerText() ? problemLayerText().slice(0, 80) : '无'}`);
    const dlg = visibleDialogText();
    if (dlg) log('可见弹窗：', dlg.slice(0, 200));
    log('提示：若 canvas 页数为 0，先翻一页或点一下目录让页面重绘，再执行 diagnose()。');
  }

  /* ============================= 暴露 API ============================= */

  // 专门排查「点目录没反应」：打印点击前后的 URL / 选中项 / 正文签名
  async function debugNav(n = 2) {
    installCanvasHook();
    await ensureToc();
    const toc = readToc();
    if (!toc.length) {
      warn('没有找到目录，请先点开一次「目录」面板');
      return null;
    }
    const level = toc.reduce((m, x) => Math.min(m, x.level), Infinity);
    const chapters = toc.filter((x) => x.level === level);
    const entry = chapters[Math.max(0, (n | 0) - 1)];
    if (!entry) {
      warn(`没有第 ${n} 章`);
      return null;
    }
    const li = tocItems()[entry.index];
    if (!li) {
      warn('目录项不存在');
      return null;
    }
    const target = li.querySelector('.readerCatalog_list_item_inner') || li;
    const snap = () => ({
      url: location.pathname,
      selected: selectedTitle(),
      selectedIndex: tocItems().findIndex((x) => x.classList.contains('readerCatalog_list_item_selected')),
      sig: viewSignature(extractView()).slice(0, 60),
      canvasPages: canvasPages().length,
      loading: isLoadingLayer(),
      problem: problemLayerText().slice(0, 40),
      dialog: visibleDialogText().slice(0, 60),
    });

    const before = snap();
    log(`目标：#${entry.index + 1} ${entry.title}（level ${entry.level}）`);
    log('点击前：', before);
    realClick(target);
    await sleep(2500);
    const after = snap();
    log('点击后：', after);

    const hit = after.url !== before.url || after.selected === entry.title;
    log(hit ? '→ 点击有效' : '→ 点击无效（URL 与目录高亮都没变）');
    return { entry, before, after, hit };
  }

  window.__wereadExport = {
    config: CONFIG,
    state,
    run,
    stop: () => {
      state.stop = true;
      log('将尽快停止');
    },
    download,
    toMarkdown,
    toc: readToc,
    pageText: domPageText,
    canvasPages,
    installCanvasHook,
    testChapter,
    debugNav,
    diagnose,
    reset: () => {
      localStorage.removeItem(storeKey);
      log('已清除本书导出进度');
    },
    _internal: { stitchPages, promoteSubTitles, cleanPageText, frameToLines, extractView, pressNextPage, realClick },
  };

  installCanvasHook();
  log('已注入（canvas 拦截已就绪）。开始：__wereadExport.run() ｜ 停止：__wereadExport.stop() ｜ 诊断：__wereadExport.diagnose()');

  if (CONFIG.AUTO_RUN) {
    setTimeout(() => {
      if (CONFIG.AUTO_RUN) run();
    }, 500);
  }
})();
