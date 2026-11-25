# 微信读书网页版正文导出为 Markdown

把 `https://weread.qq.com/web/reader/...` 阅读页里的整本书按章抓下来，合并成一个 Markdown 文件。

## 原理

微信读书网页版是 SPA，阅读器有两种渲染模式：

| 模式 | 正文位置 | 取文方式 |
| --- | --- | --- |
| 双栏 / 翻页（默认） | **画在 `<canvas>` 上**，DOM 里没有文字 | hook `CanvasRenderingContext2D.fillText` / `clearRect`，记录每一笔绘制，按坐标还原成页面文本 |
| 上下滚动 / 旧版 | DOM 里的 `.passage-content` | 直接读 `innerText` |

脚本流程：**点目录跳章 → 逐页翻页 → 每页取文 → 按章拼接 → 断点存 localStorage → 下载 `<书名>.md`**。

> 早期版本只读 DOM，在双栏模式下每章只能拿到章节标题几个字。现在默认拦截 canvas 绘制，两种模式都能取到正文。

> 翻页默认走**键盘事件**（`PAGER: 'keyboard'`）。实测页面里的风控脚本会把合成的鼠标点击记成 `unTrustedClick` 上报，键盘翻页不会被记；目录跳章仍需要一次点击，但每章只有一次。

不请求接口、不解密、不绕过付费，只读取当前账号有权阅读的内容。导出内容仅供个人阅读/笔记使用，请遵守微信读书用户协议和著作权法。

## 前提

- 桌面端 Chrome / Edge（Safari 也能跑，但下载体验略差）
- 已登录，且这本书是「会员卡可读」或已购买对应章节；没解锁的内容抓不到
- 导出期间保持标签页在前台可见

## 使用步骤

1. 打开书的阅读页，例如
   `https://weread.qq.com/web/reader/61d32fd059b1ee61d68a68fkc81322c012c81e728d9d180`
2. 点一次左下角「目录」，确认目录能正常展开（脚本也会尝试自动点开）
3. `F12` → Console，Chrome 首次粘贴先输入 `allow pasting`
4. 粘贴 `weread-export.console.js` 全文并回车
5. 自动逐章抓取，结束后自动下载 `<书名>.md`

**建议先试跑一章**，确认取文正常再全量：

```js
__wereadExport.config.AUTO_RUN = false   // 如果你已经粘贴并自动开始了，先 stop()
__wereadExport.stop()
__wereadExport.testChapter(3)            // 只跑目录第 3 章，打印页数/字数/前 400 字
```

## 可用命令

```js
__wereadExport.run()          // 开始 / 继续（默认粘贴后自动开始）
__wereadExport.stop()         // 尽快停止
__wereadExport.testChapter(n) // 只跑第 n 章（不写进度、不下载），用于验证
__wereadExport.download()     // 用已抓到的章节重新生成并下载 md
__wereadExport.toMarkdown()   // 直接拿到 Markdown 字符串
__wereadExport.toc()          // 打印解析到的目录
__wereadExport.canvasPages()  // 当前 canvas 还原出的页面文本
__wereadExport.pageText()     // 当前 DOM 文本
__wereadExport.diagnose()     // 诊断：模式、canvas 页数、DOM 字数、可见弹窗
__wereadExport.debugNav(n)    // 排查：打印第 n 章点击前后的 URL / 目录高亮 / 正文签名
__wereadExport.reset()        // 清除本书的断点进度
__wereadExport.state          // 运行状态、已抓章节、失败/跳过清单
```

## 参数

脚本顶部 `CONFIG`：

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `AUTO_RUN` | `true` | 粘贴后自动开始 |
| `TOC_LEVEL` | `0` | 以目录的哪一层作为「章」；`0` 表示自动取最浅一层 |
| `PAGE_TURN_MIN_MS` / `PAGE_TURN_MAX_MS` | `1000` / `2500` | 每次翻页后的随机等待区间（毫秒） |
| `CHAPTER_DELAY_MIN_MS` / `CHAPTER_DELAY_MAX_MS` | `2500` / `6000` | 每章之间的随机等待区间 |
| `LONG_PAUSE_EVERY` | `15` | 每翻 N 页多歇一次（`0` 关闭） |
| `LONG_PAUSE_MIN_MS` / `LONG_PAUSE_MAX_MS` | `8000` / `16000` | 长休息的随机区间 |
| `STUCK_WAIT_MS` | `12000` | 翻页后页面一直加载中时，最多再等多久 |
| `RETRY_PER_CHAPTER` | `2` | 单章加载异常时的重试次数 |
| `RETRY_WAIT_MIN_MS` / `RETRY_WAIT_MAX_MS` | `8000` / `20000` | 重试前的随机等待区间 |
| `MAX_PAGES` | `400` | 单章最多翻页次数，防止死循环 |
| `MAX_WAIT_MS` | `25000` | 单章首次加载最长等待 |
| `RESUME` | `true` | 断点续跑（每章写入 localStorage） |
| `SKIP_LOCKED` | `true` | 跳过目录里带锁的章节 |
| `LIMIT` | `0` | `>0` 时只导出前 N 章 |
| `DEBUG` | `false` | 打印每页字数、章间间隔等信息 |
| `PAGER` | `'keyboard'` | 翻页方式：`'keyboard'`（默认，风控不记合成鼠标点击）/ `'button'`（点下一页按钮） |

## 输出格式

```markdown
# 书名

> 作者
> 来源：https://weread.qq.com/web/reader/...

---

## 第 1 章 神秘的庄家

正文……

#### 一、庄家的定义

正文……
```

- 章标题取自目录的层级（一级 → `##`），更深层的小节标题会还原成 `###` / `####`
- 跨页被切断的段落会自动接回同一行
- canvas 模式下的「防截屏水印」（低透明度数字串）会被过滤
- 文末附「未导出（跳过）」和「未导出（抓取失败）」清单

## 常见问题

**控制台出现 `suspiciousAction` / `unTrustedClick`**
- 那是微信读书自己的风控上报，看到你用的是合成点击。脚本已经把翻页改成键盘（`PAGER: 'keyboard'`）并放慢节奏，只剩每章一次目录点击。
- 如果页面因此限流/白屏：刷新阅读页，重新粘贴脚本会从断点继续；仍不行的就把节奏再调慢（见上一条）。

**点目录没反应 / 某章被跳过**
- 微信读书的目录项点击处理里有 `event.clientX && event.clientY` 判断，旧的 `element.click()` 坐标是 `0,0` 会被忽略。新版已改成派发带坐标的真实鼠标事件。
- 如果某章提示「点击目录后没有跳转（可能与前一项同属一个章节）」：这是阅读器的正常行为——比如「扉页」「版权信息」可能属于同一个阅读章节，无法单独跳转，脚本会跳过它以免重复或中断。
- 仍想排查时：`__wereadExport.debugNav(2)` 会打印点击前后的 URL、目录高亮、正文签名。

**某章只有几个字 / 正文为空**
1. 先 `__wereadExport.diagnose()`：
   - `canvas 还原页数` 为 0 且 `canvas 数量 > 0`：说明还没触发重绘，翻一页或点一下目录后再看；
   - `可见弹窗` 里出现「付费会员专享 / 开通会员 / 购买本章」：说明这章没解锁，需要会员卡或购买；
2. 再 `__wereadExport.testChapter(3)` 看单章结果。

**提示「检测到付费/登录弹窗」后停止**
- 说明当前账号对这本书没有阅读权限（会员卡过期、未购买、登录态失效）。脚本不会绕过付费，换有权限的账号或先开通会员。

**连续 3 章失败后脚本停了，也没有下载**
- 这是有意的：结果过少时不再自动生成 md，避免产出残缺文件。数据仍在内存和 localStorage，确认后用 `__wereadExport.download()` 手动导出。

**`diagnose()` 显示 canvas 页数一直是 0，但页面上明明有字**
- 可能是 PDF / 扫描版（文字是图片，不是 `fillText` 绘制的），这种书不支持导出。
- 也可以试试在阅读设置里切到「上下滚动阅读」，脚本会自动改用 DOM 取文。

**每章只抓到一页**
- `PAGE_TURN_MIN_MS`/`MAX_MS` 调大，确认阅读器点「下一页」能正常翻页；
- 上下滚动模式下整章一次性在 DOM 里，一页抓完是正常的。

**跑到一半页面加载异常 / 提示「阅读器提示」**
- 新版会随机间隔翻页，并在识别到「加载中卡住 / 阅读器错误层」时暂停；单章会等待 8~20 秒后重试 2 次。
- 如果依然失败且控制台提示「页面阅读器已不可用」：手动刷新阅读页，重新粘贴脚本即可——进度按章保存在 localStorage，会从断点继续。
- 想更慢，不用改源码，直接在 Console 调参数后再 `run()`：
  ```js
  Object.assign(__wereadExport.config, {
    PAGE_TURN_MIN_MS: 2000, PAGE_TURN_MAX_MS: 4500,
    CHAPTER_DELAY_MIN_MS: 4000, CHAPTER_DELAY_MAX_MS: 9000,
    LONG_PAUSE_EVERY: 10, LONG_PAUSE_MIN_MS: 10000, LONG_PAUSE_MAX_MS: 20000,
  });
  __wereadExport.run();
  ```

**跑到一半停了**
- 可能是限流：调大 `PAGE_TURN_*` / `CHAPTER_DELAY_*` / `RETRY_WAIT_*`，重新粘贴脚本会读取断点继续。

**会不会影响我的阅读进度**
- 会。脚本是真实翻章的，本书「已读到」会停在最后导出的章节。

**为什么不用 Playwright / 直接调接口**
- 接口响应加密、解码逻辑在混淆过的 bundle 里，生产包也拿不到 Vuex 实例；正文又被画进 canvas。拦截绘制比破解接口简单可靠，且不用装依赖。
- 需要无人值守批量导出时，可以把同一套逻辑搬到 Playwright（连接已登录的 Chrome 用户目录）。
