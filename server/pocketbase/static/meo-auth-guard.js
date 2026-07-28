/**
 * PocketBase Admin UI：登录/管理员 token 失效时自动退回登录页，
 * 避免底部长期显示 “Something went wrong while processing your request.”
 * 由 http-inject-proxy 注入到 /_/ 页面。
 */
(function () {
  if (window.__meoPbAuthGuard) return;
  window.__meoPbAuthGuard = true;

  function clearAuthStorage() {
    try {
      var keys = [];
      for (var i = 0; i < localStorage.length; i++) {
        var k = localStorage.key(i);
        if (!k) continue;
        var lower = k.toLowerCase();
        if (
          lower.indexOf("pocketbase") !== -1 ||
          lower.indexOf("pb_auth") !== -1 ||
          lower.indexOf("auth") !== -1 && lower.indexOf("pb") !== -1
        ) {
          keys.push(k);
        }
      }
      keys.forEach(function (k) {
        localStorage.removeItem(k);
      });
    } catch (e) {}
    try {
      sessionStorage.clear();
    } catch (e2) {}
  }

  function hideGenericErrorToasts() {
    try {
      var nodes = document.querySelectorAll("body *");
      for (var i = 0; i < nodes.length; i++) {
        var el = nodes[i];
        if (!el || !el.childNodes || el.childNodes.length === 0) continue;
        var text = (el.textContent || "").trim();
        if (text === "Something went wrong while processing your request.") {
          var box = el.closest ? el.closest("[class],aside,section,div") : el.parentElement;
          if (box) box.style.display = "none";
          else el.style.display = "none";
        }
      }
    } catch (e) {}
  }

  function goLogin() {
    if (window.__meoPbAuthRedirecting) return;
    window.__meoPbAuthRedirecting = true;
    window.__meoPbAuthExpired = true;
    clearAuthStorage();
    hideGenericErrorToasts();
    // 清掉内存态：整页回 /_/，未登录时 PocketBase 会展示登录表单
    try {
      location.replace("/_/");
    } catch (e) {
      location.href = "/_/";
    }
  }

  function looksLikeAuthFailure(status, bodyText) {
    if (status === 401) return true;
    if (status !== 403 && status !== 400) return false;
    if (!bodyText) return status === 403;
    var lower = String(bodyText).toLowerCase();
    return (
      lower.indexOf("authorization") !== -1 ||
      lower.indexOf("valid admin") !== -1 ||
      lower.indexOf("requires valid") !== -1 ||
      lower.indexOf("expired") !== -1 ||
      lower.indexOf("invalid token") !== -1 ||
      lower.indexOf("not authorized") !== -1 ||
      lower.indexOf("auth record") !== -1 && lower.indexOf("token") !== -1
    );
  }

  // fetch
  if (typeof window.fetch === "function") {
    var origFetch = window.fetch;
    window.fetch = function () {
      return origFetch.apply(this, arguments).then(function (res) {
        if (!looksLikeAuthFailure(res.status)) return res;
        return res
          .clone()
          .text()
          .then(function (text) {
            if (looksLikeAuthFailure(res.status, text)) goLogin();
            return res;
          })
          .catch(function () {
            if (res.status === 401 || res.status === 403) goLogin();
            return res;
          });
      });
    };
  }

  // XHR（部分旧路径）
  if (window.XMLHttpRequest && XMLHttpRequest.prototype) {
    var origSend = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.send = function () {
      var xhr = this;
      xhr.addEventListener("load", function () {
        if (looksLikeAuthFailure(xhr.status, xhr.responseText)) goLogin();
      });
      return origSend.apply(this, arguments);
    };
  }

  // 若已失效但仍停在后台页，周期性探测一次 auth-refresh
  function probe() {
    if (window.__meoPbAuthRedirecting) return;
    if (!location.pathname || location.pathname.indexOf("/_/") !== 0) return;
    var hasAuth = false;
    try {
      for (var i = 0; i < localStorage.length; i++) {
        var k = localStorage.key(i) || "";
        if (k.toLowerCase().indexOf("pocketbase") !== -1) {
          hasAuth = true;
          break;
        }
      }
    } catch (e) {}
    if (!hasAuth) return;
    // 任意需鉴权的轻量请求：列出 collections
    fetch("/api/collections?page=1&perPage=1", {
      headers: (function () {
        var h = {};
        try {
          // PocketBase Admin 把 token 放在 Authorization；SDK 会自动带，这里尽量从 storage 取出
          for (var i = 0; i < localStorage.length; i++) {
            var key = localStorage.key(i);
            if (!key) continue;
            var raw = localStorage.getItem(key);
            if (!raw || raw.indexOf("token") === -1) continue;
            try {
              var obj = JSON.parse(raw);
              var token = obj && (obj.token || (obj.model && obj.token));
              if (typeof token === "string" && token.length > 20) {
                h["Authorization"] = token;
                break;
              }
            } catch (err) {}
          }
        } catch (e2) {}
        return h;
      })(),
    }).catch(function () {});
  }

  setTimeout(probe, 1500);

  // 隐藏已出现的通用错误条
  var obs = new MutationObserver(function () {
    if (window.__meoPbAuthExpired) hideGenericErrorToasts();
  });
  function startObs() {
    if (document.body) obs.observe(document.body, { childList: true, subtree: true });
  }
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", startObs);
  } else {
    startObs();
  }
})();
