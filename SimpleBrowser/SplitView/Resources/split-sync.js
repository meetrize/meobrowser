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
      if(el.tagName==='TEXTAREA') proto=window.HTMLTextAreaElement.prototype;
      else if(el.tagName==='SELECT') proto=window.HTMLSelectElement.prototype;
      else proto=window.HTMLInputElement.prototype;
      var desc=Object.getOwnPropertyDescriptor(proto,'value');
      if(desc&&desc.set) desc.set.call(el,v); else el.value=v;
    }catch(err){ el.value=v; }
    el.dispatchEvent(new Event('input',{bubbles:true}));
    el.dispatchEvent(new Event('change',{bubbles:true}));
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
  window.meoSyncApplyValue=function(v,fp){
    var el=findByFP(fp||window.__meoSyncFP);
    if(!el) return 'notfound';
    if(/password|otp|one-time|captcha|verify/i.test((el.name||'')+' '+(el.id||'')+' '+(el.type||''))) return 'skipped-sensitive';
    if(el.isContentEditable) { el.focus(); document.execCommand('selectAll',false,null); document.execCommand('insertText',false,v); }
    else setNativeValue(el,v);
    return 'ok';
  };
  window.meoSyncSubmit=function(fp){
    var el=findByFP(fp||window.__meoSyncFP);
    if(!el) return 'notfound';
    var f=el.form;
    if(f){ if(f.requestSubmit) f.requestSubmit(); else f.submit(); return 'submitted'; }
    el.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',code:'Enter',keyCode:13,bubbles:true}));
    return 'enter-sent';
  };
  // master 监听:输入即上报
  document.addEventListener('input',function(e){
    if(!window.__meoSyncMaster) return;
    var el=e.target;
    if(!el||!/INPUT|TEXTAREA/.test(el.tagName)) return;
    var v=el.isContentEditable?el.innerText:el.value;
    try{ window.webkit.messageHandlers.meoSync.postMessage({type:'input',value:v}); }catch(err){}
  },true);
  document.addEventListener('keydown',function(e){
    if(!window.__meoSyncMaster) return;
    if(e.key==='Enter'&&((e.metaKey)||(!e.shiftKey&&e.key==='Enter'&&e.target&&e.target.form))){
      try{ window.webkit.messageHandlers.meoSync.postMessage({type:'submit'}); }catch(err){}
    }
  },true);
})();
