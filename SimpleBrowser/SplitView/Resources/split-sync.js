(function(){
  if (window.__meoSyncInstalled) return;
  window.__meoSyncInstalled = true;
  window.__meoSyncFP = null;
  window.__meoSyncMaster = false;

  function fingerprint(el){
    if(!el) return null;
    var path = '';
    try {
      var e = el, parts = [];
      while(e && e.nodeType===1 && parts.length<6){
        var s = e.tagName.toLowerCase();
        if(e.id){ s += '#'+e.id; parts.unshift(s); break; }
        var cls = (e.className&&e.className.baseVal!==undefined)?'':(e.className||'');
        if(typeof cls==='string'&&cls) s += '.'+cls.trim().split(/\s+/).slice(0,2).join('.');
        if(e.name) s += '[name="'+e.name+'"]';
        var sib=e, idx=1;
        while((sib=sib.previousElementSibling)!=null){ if(sib.tagName===e.tagName) idx++; }
        s += ':nth('+idx+')';
        parts.unshift(s);
        e=e.parentElement;
      }
      path = parts.join('>');
    } catch(err){}
    return { tag:(el.tagName||'').toLowerCase(), id:el.id||'', name:el.name||'',
      type:el.type||'', css:window.__meoSyncFP&&window.__meoSyncFP.css||'', xpath:path };
  }
  function findByFP(fp){
    if(!fp) return null;
    try{
      if(fp.id){ var el=document.getElementById(fp.id); if(el) return el; }
      if(fp.css){ var q=document.querySelector(fp.css); if(q) return q; }
      var sels=['input','textarea','select','[contenteditable="true"]'];
      var cands=[];
      sels.forEach(function(s){ document.querySelectorAll(s).forEach(function(e){cands.push(e);}); });
      var byName=cands.filter(function(e){return (e.name||'')===(fp.name||'')&&(e.tagName||'').toLowerCase()===(fp.tag||'');});
      if(byName.length===1) return byName[0];
      if(cands.length && fp.index!=null && cands[fp.index]) return cands[fp.index];
      if(cands.length===1) return cands[0];
    }catch(err){}
    return null;
  }
  function setNativeValue(el,v){
    try{
      var proto=null;
      var tag=(el.tagName||'').toUpperCase();
      if(tag==='TEXTAREA') proto=window.HTMLTextAreaElement.prototype;
      else if(tag==='SELECT') proto=window.HTMLSelectElement.prototype;
      else proto=window.HTMLInputElement.prototype;
      var desc=Object.getOwnPropertyDescriptor(proto,'value');
      if(!desc||!desc.set){
        // textarea 在部分站点原型链异常时,退回通用查找
        desc=Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype,'value')
            ||Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value');
      }
      if(desc&&desc.set) desc.set.call(el,v); else el.value=v;
    }catch(err){ try{el.value=v;}catch(e2){} }
    window.__meoSyncApplying=true;
    try{
      // data 只给增量语义会让 deepseek 这类站把全量当增量再拼一次(空格翻倍);全量同步一律不带 data
      try{ el.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText'})); }
      catch(err2){ el.dispatchEvent(new Event('input',{bubbles:true})); }
      el.dispatchEvent(new Event('change',{bubbles:true}));
    }finally{
      // 下一拍再放开,确保本次派发的 input 事件被 guard 吃掉(防回声风暴)
      setTimeout(function(){ window.__meoSyncApplying=false; },0);
    }
    // React 15/16:同时触发 tracker,确保受控组件更新
    try{
      var tracker=el._valueTracker;
      if(tracker&&tracker.setValue) tracker.setValue('');
    }catch(err3){}
  }
  // 富编辑器写入:ProseMirror/Quill/tiptap 通用——聚焦+选区+insertText,失败回退 innerText
  function setRichEditorValue(el,v){
    // 若从栏正在被用户聚焦打字,不抢焦点(只在后台默写),避免 ChatGPT 输入法卡死
    var hadFocus=false;
    try{ hadFocus=(document.activeElement===el)||el.contains(document.activeElement); }catch(err0){}
    if(!hadFocus){ try{ el.focus(); }catch(err){} }
    window.__meoSyncApplying=true;
    try{
      var sel=window.getSelection();
      var range=document.createRange();
      // 全量替换:全选后 insertText(ProseMirror/Quill 监听 beforeinput,execCommand 最稳)
      range.selectNodeContents(el);
      sel.removeAllRanges(); sel.addRange(range);
      var ok=false;
      try{ ok=document.execCommand('insertText',false,v); }catch(errA){ ok=false; }
      if(ok){
        try{ el.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText'})); }
        catch(errB){ el.dispatchEvent(new Event('input',{bubbles:true})); }
        return true;
      }
    }catch(err){} finally{
      setTimeout(function(){ window.__meoSyncApplying=false; },0);
    }
    try{
      // 回退:直接写 innerText + 派发事件(ProseMirror 会从 DOM 读回,但需 blur/focus 触发解析)
      if(el.tagName==='TEXTAREA'||('value' in el)){ setNativeValue(el,v); }
      else{
        el.innerText=v;
        el.dispatchEvent(new InputEvent('input',{bubbles:true,data:v,inputType:'insertText'}));
        el.dispatchEvent(new Event('change',{bubbles:true}));
      }
      return 'fallback-innertext';
    }catch(err2){ return false; }
  }
  window.meoSyncPickOnce=function(){
    return new Promise(function(res){
      function h(e){
        e.preventDefault(); e.stopPropagation();
        document.removeEventListener('click',h,true);
        var el=e.target.closest('input,textarea,select,[contenteditable]');
        if(!el){ res(null); return; }
        var all=Array.prototype.slice.call(document.querySelectorAll('input,textarea,select'));
        var fp=fingerprint(el); fp.index=all.indexOf(el);
        try{ fp.css=''; }catch(err){}
        window.__meoSyncFP=fp;
        res(fp);
      }
      document.addEventListener('click',h,true);
    });
  };
  window.meoSyncSetFingerprint=function(fp){ window.__meoSyncFP=fp; };
  function firstVisibleEditor(){
    var sels=['textarea','div[contenteditable="true"]','div[contenteditable=""]','[role="textbox"]','input[type="text"]','input:not([type])','input[type="search"]'];
    for(var i=0;i<sels.length;i++){
      var list=document.querySelectorAll(sels[i]);
      for(var j=0;j<list.length;j++){
        var e=list[j];
        if(e.disabled||e.readOnly) continue;
        var r=null; try{ r=e.getBoundingClientRect(); }catch(err){ continue; }
        if(r&&r.width>40&&r.height>10&&r.bottom>0&&r.right>0) return e;
      }
    }
    return null;
  }
  window.meoSyncApplyValue=function(v,fp){
    var el=findByFP(fp||window.__meoSyncFP);
    var fb='';
    if(!el){ el=firstVisibleEditor(); fb=el?'+fallback':''; if(!el) return 'notfound'; }
    if(/password|otp|one-time|captcha/i.test((el.name||'')+' '+(el.id||'')+' '+(el.type||''))) return 'skipped-sensitive';
    if(/password|otp|one-time|captcha|verify/i.test((el.name||'')+' '+(el.id||'')+' '+(el.type||''))) return 'skipped-sensitive';
    if(el.isContentEditable) {
      var r=setRichEditorValue(el,v);
      if(r===false) return 'edit-failed';
      if(r==='fallback-innertext') fb+='+innertext';
    }
    else setNativeValue(el,v);
    try{ el.focus(); }catch(err){}
    return 'ok'+fb;
  };
  window.meoSyncSubmit=function(fp){
    var el=findByFP(fp||window.__meoSyncFP);
    if(!el){ el=firstVisibleEditor(); if(!el) return 'notfound'; }
    var f=el.form;
    if(f){ try{ if(f.requestSubmit) f.requestSubmit(); else f.submit(); return 'submitted'; }catch(err){} }
    // 真 Enter 三件套(ProseMirror/Quill/tiptap 监听 keydown 发送)
    window.__meoSyncApplying=true;
    try{
      try{ el.focus(); }catch(errF){}
      var init={key:'Enter',code:'Enter',keyCode:13,which:13,bubbles:true,cancelable:true};
      el.dispatchEvent(new KeyboardEvent('keydown',init));
      el.dispatchEvent(new KeyboardEvent('keypress',init));
      el.dispatchEvent(new KeyboardEvent('keyup',init));
    }catch(errK){}
    setTimeout(function(){ window.__meoSyncApplying=false; },0);
    // 兜底:点发送按钮(各站 data-testid / aria-label 启发式)
    try{
      var btn=document.querySelector('[data-testid="send-button"],[data-testid="composer-send-button"],button[aria-label*="Send"],button[aria-label*="发送"],button[type="submit"]');
      if(btn&&!btn.disabled){ btn.click(); return 'enter-sent+btn'; }
    }catch(errB){}
    return 'enter-sent';
  };
  // 回声/组字保护:自己写入触发的 input 不上报;IME 组字中不上报,组字结束才报一次
  window.__meoSyncComposing=false;
  window.__meoSyncApplying=false;
  document.addEventListener('compositionstart',function(){ window.__meoSyncComposing=true; },true);
  document.addEventListener('compositionend',function(e){
    window.__meoSyncComposing=false;
    if(!window.__meoSyncOn||window.__meoSyncApplying) return;
    var el=e.target;
    if(!el||!el.tagName) return;
    var v=(el.isContentEditable?el.innerText:(('value' in el)?el.value:(el.innerText||'')));
    try{ window.webkit.messageHandlers.meoSync.postMessage({type:'input',value:String(v)}); }catch(err){}
  },true);
  // 上报:同步态下任意栏输入都上报(不再依赖 master 标记,标记在 SPA 跳转/重挂后易丢失)
  document.addEventListener('input',function(e){
    if(!window.__meoSyncOn) return;
    if(window.__meoSyncApplying) return;
    if(window.__meoSyncComposing||e.isComposing) return;
    var el=e.target;
    if(!el||!el.tagName) return;
    var v=(el.isContentEditable?el.innerText:(('value' in el)?el.value:(el.innerText||'')));
    try{ window.webkit.messageHandlers.meoSync.postMessage({type:'input',value:v}); }catch(err){}
  },true);
  document.addEventListener('keydown',function(e){
    if(!window.__meoSyncOn) return;
    if(window.__meoSyncApplying) return;
    if(e.key!=='Enter'||e.shiftKey||e.isComposing) return;
    var el=e.target;
    if(!el||!el.tagName) return;
    // form 内回车 / 富编辑器 plain Enter / 单行 input 回车:一律视为发送
    try{ window.webkit.messageHandlers.meoSync.postMessage({type:'submit'}); }catch(err){}
  },true);
})();
