const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

let current = null;
let busy = false;
let sends = 0;
const answer = '收到，测试正常。有什么需要帮忙的吗？';
const rect = () => ({width: 50, height: 30});
const input = {tagName: 'TEXTAREA', value: '', getBoundingClientRect: rect,
  closest: () => root, focus() {}, dispatchEvent() {}, getAttribute: () => null};
const send = {get className() { return 'ds-button--primary ds-button--filled ds-button--circle' + (busy || input.value ? '' : ' ds-button--disabled'); },
  getBoundingClientRect: rect, getAttribute: () => null,
  click() {
    sends++;
    input.value = '';
    busy = true;
    current = message('收到');
    setTimeout(() => { current.innerText = current.textContent = answer; }, 1100);
    setTimeout(() => { busy = false; }, 1400);
  }};
const root = {querySelector: sel => sel.includes('ds-button--circle') ? send : null,
  querySelectorAll: () => []};
function message(text) {
  return {innerText: text, textContent: text, className: 'ds-assistant-message-main-content',
    closest: () => null, querySelectorAll: () => [], getAttribute: () => null};
}
const document = {readyState: 'complete', querySelector: () => null,
  querySelectorAll(sel) {
    if (sel.includes('textarea')) return [input];
    return [];
  }};
const runtime = {install(cfg) { window.__MeoAIBridge = {isBusy: cfg.isBusy, abort() {}}; },
  nativeSetValue(el, value) { el.value = value; return true; },
  richMarkdownFromElement(el) { return el.textContent; },
  qsa(sel) {
    if (sel.includes('ds-assistant-message-main-content')) return current ? [current] : [];
    if (sel === '.ds-button, [role="button"], button') return [send];
    if (sel === '.ds-button--primary, .ds-button--filled') return [send];
    return [];
  }};
const window = {AIBridgeRuntime: runtime};
const context = {window, document, AIBridgeRuntime: runtime, location: {hostname: 'chat.deepseek.com', href: ''},
  console, setTimeout, Date, WeakSet, Promise};
vm.runInNewContext(fs.readFileSync('SimpleBrowser/AIBridge/Spike/adapters/deepseek.js', 'utf8'), context);
(async () => {
  for (let i = 0; i < 2; i++) {
    const result = await window.__MeoAIBridge.sendAndWait('test', {timeoutMs: 5000, stableMs: 200});
    assert.equal(result.ok, true);
    assert.equal(result.text, answer);
    assert.equal(busy, false, 'must wait for generation to finish');
  }
  assert.equal(sends, 2);
  console.log('DeepSeek adapter returns both complete identical replies');
})().catch(error => { console.error(error); process.exitCode = 1; });
