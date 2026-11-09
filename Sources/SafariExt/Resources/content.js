// M3U8 Grab — Safari 扩展内容脚本（document_start，全 frame 注入）
// 1) 钩 fetch / XHR / media.src / setAttribute / MutationObserver / performance 嗅探 m3u8
// 2) 嗅到之后在页面右下角浮出一个圆球（对齐原 App 的悬浮窗体验）
// 3) 点圆球 → 用 m3u8grab:// 深链跳转本体 App 去下载
(function () {
  'use strict';
  if (window.__m3u8grabExtInstalled) { return; }
  window.__m3u8grabExtInstalled = true;

  var api = (typeof browser !== 'undefined' && browser.runtime) ? browser : chrome;
  var HLS_RE = /\.m3u8(\?|#|$)/i;
  var FILE_RE = /\.(mp4|m4v|mov|ts)(\?|#|$)/i;
  var seen = Object.create(null);

  // 本页嗅到的 m3u8（最新的在前，最多 30 条）
  var hits = [];
  var MAX_HITS = 30;
  var isTop = (function () {
    try { return window.top === window; } catch (e) { return false; }
  })();

  function absolute(raw) {
    if (!raw || typeof raw !== 'string') { return null; }
    raw = raw.trim();
    if (!raw || raw.indexOf('data:') === 0 || raw.indexOf('blob:') === 0) { return null; }
    var abs;
    try { abs = new URL(raw, location.href).href; } catch (e) { return null; }
    if (!/^https?:/i.test(abs)) { return null; }
    return abs;
  }

  function report(raw) {
    var abs = absolute(raw);
    if (!abs) { return; }
    var kind = HLS_RE.test(abs) ? 'hls' : (FILE_RE.test(abs) ? 'file' : null);
    if (!kind) { return; }
    if (seen[abs]) { return; }
    seen[abs] = 1;

    if (kind === 'hls') { pushHit(abs); }

    try {
      api.runtime.sendMessage({
        type: 'found',
        url: abs,
        kind: kind,
        pageURL: location.href,
        pageTitle: document.title || ''
      }, function () { /* 背景页可能未就绪，忽略回执 */ });
    } catch (e) { /* 忽略 */ }
  }

  // ---------------------------------------------------------------- 悬浮球

  function shortName(u) {
    try {
      var url = new URL(u);
      var seg = url.pathname.split('/').filter(Boolean).pop() || url.host;
      return seg.length > 28 ? seg.slice(0, 26) + '…' : seg;
    } catch (e) { return u.slice(0, 28); }
  }

  function pushHit(abs) {
    var idx = hits.indexOf(abs);
    if (idx >= 0) { hits.splice(idx, 1); }
    hits.unshift(abs);
    if (hits.length > MAX_HITS) { hits.length = MAX_HITS; }
    ensureBall();
    updateBall();
  }

  function openApp(streamURL) {
    var link = 'm3u8grab://open?url=' + encodeURIComponent(streamURL)
      + '&page=' + encodeURIComponent(location.href)
      + '&title=' + encodeURIComponent(document.title || '');
    try {
      var a = document.createElement('a');
      a.href = link;
      a.style.display = 'none';
      (document.body || document.documentElement).appendChild(a);
      a.click();
      setTimeout(function () {
        try { a.parentNode.removeChild(a); } catch (e) { /* 忽略 */ }
      }, 1200);
      return true;
    } catch (e) {
      return false;
    }
  }

  var ball = null;
  var panel = null;
  var badge = null;

  function styleBall(el) {
    el.style.cssText = [
      'position:fixed', 'right:14px', 'bottom:110px', 'width:52px', 'height:52px',
      'border-radius:26px', 'z-index:2147483647', 'display:flex',
      'align-items:center', 'justify-content:center', 'box-sizing:border-box',
      'background:linear-gradient(135deg,#0A84FF,#5B5BF0)',
      'box-shadow:0 6px 18px rgba(10,132,255,.45)',
      'border:1px solid rgba(255,255,255,.35)', 'cursor:pointer',
      'touch-action:none', 'user-select:none', '-webkit-user-select:none',
      'transition:transform .16s ease', 'transform:scale(1)'
    ].join(';');
  }

  function ensureBall() {
    if (!isTop) { return; }
    if (ball && ball.parentNode) { return; }
    if (!document.body) {
      document.addEventListener('DOMContentLoaded', ensureBall, { once: true });
      return;
    }

    ball = document.createElement('div');
    ball.id = '__m3u8grab_ball';
    styleBall(ball);
    ball.setAttribute('role', 'button');
    ball.setAttribute('aria-label', 'M3U8 Grab');
    ball.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="26" height="26">'
      + '<path fill="#fff" d="M9.2 6.8v10.4L18 12z"/>'
      + '<path fill="rgba(255,255,255,.55)" d="M4.6 8.2a5.6 5.6 0 0 0 0 7.6" stroke="rgba(255,255,255,.55)" stroke-width="1.6" fill="none" stroke-linecap="round"/>'
      + '</svg>';

    badge = document.createElement('div');
    badge.style.cssText = [
      'position:absolute', 'top:-4px', 'right:-4px', 'min-width:20px', 'height:20px',
      'border-radius:10px', 'background:#FF3B30', 'color:#fff',
      'font:600 11px/20px -apple-system,system-ui,sans-serif',
      'text-align:center', 'padding:0 5px', 'box-sizing:border-box',
      'box-shadow:0 2px 6px rgba(0,0,0,.3)'
    ].join(';');
    badge.textContent = '1';
    ball.appendChild(badge);

    // 拖动 + 点击（拖动阈值 8px，避免误触）
    var startX = 0, startY = 0, dragging = false, moved = false;
    ball.addEventListener('touchstart', function (e) {
      var t = e.touches[0];
      startX = t.clientX; startY = t.clientY;
      dragging = true; moved = false;
      ball.style.transition = 'none';
    }, { passive: true });

    ball.addEventListener('touchmove', function (e) {
      if (!dragging) { return; }
      var t = e.touches[0];
      var dx = t.clientX - startX;
      var dy = t.clientY - startY;
      if (Math.abs(dx) > 8 || Math.abs(dy) > 8) { moved = true; }
      if (!moved) { return; }
      var rect = ball.getBoundingClientRect();
      var left = Math.min(Math.max(4, rect.left + dx), window.innerWidth - rect.width - 4);
      var top = Math.min(Math.max(4, rect.top + dy), window.innerHeight - rect.height - 4);
      ball.style.left = left + 'px';
      ball.style.top = top + 'px';
      ball.style.right = 'auto';
      ball.style.bottom = 'auto';
      startX = t.clientX; startY = t.clientY;
      e.preventDefault();
    }, { passive: false });

    ball.addEventListener('touchend', function (e) {
      dragging = false;
      ball.style.transition = 'transform .16s ease';
      if (!moved) {
        e.preventDefault();
        togglePanel();
      } else {
        try {
          localStorage.setItem('__m3u8grab_ball_pos',
            JSON.stringify({ left: ball.style.left, top: ball.style.top }));
        } catch (err) { /* 忽略 */ }
      }
    }, { passive: false });

    ball.addEventListener('click', function (e) {
      e.preventDefault();
      e.stopPropagation();
      if (!moved) { togglePanel(); }
    });

    try {
      var saved = JSON.parse(localStorage.getItem('__m3u8grab_ball_pos') || 'null');
      if (saved && saved.left && saved.top) {
        ball.style.left = saved.left;
        ball.style.top = saved.top;
        ball.style.right = 'auto';
        ball.style.bottom = 'auto';
      }
    } catch (err) { /* 忽略 */ }

    document.body.appendChild(ball);
  }

  function updateBall() {
    if (!badge) { return; }
    badge.textContent = String(hits.length);
    badge.style.display = hits.length > 0 ? 'block' : 'none';
  }

  function closePanel() {
    if (panel && panel.parentNode) { panel.parentNode.removeChild(panel); }
    panel = null;
  }

  function togglePanel() {
    if (panel) { closePanel(); return; }
    if (!hits.length || !document.body) { return; }

    panel = document.createElement('div');
    panel.id = '__m3u8grab_panel';
    panel.style.cssText = [
      'position:fixed', 'right:12px', 'bottom:174px', 'width:250px',
      'max-height:46vh', 'overflow:auto', 'box-sizing:border-box',
      'background:rgba(28,28,30,.97)', 'color:#fff', 'border-radius:14px',
      'padding:10px 10px 6px', 'z-index:2147483647',
      'box-shadow:0 10px 30px rgba(0,0,0,.45)',
      'font:13px/1.4 -apple-system,system-ui,sans-serif',
      'border:1px solid rgba(255,255,255,.14)'
    ].join(';');

    var head = document.createElement('div');
    head.style.cssText = 'display:flex;align-items:center;justify-content:space-between;margin-bottom:8px';
    head.innerHTML = '<span style="font-weight:600">M3U8 Grab · ' + hits.length + ' 个</span>'
      + '<span data-act="close" style="cursor:pointer;opacity:.6;padding:0 4px">✕</span>';
    panel.appendChild(head);

    hits.slice(0, 10).forEach(function (u) {
      var row = document.createElement('div');
      row.setAttribute('data-url', u);
      row.style.cssText = 'padding:8px;border-radius:9px;background:rgba(255,255,255,.08);'
        + 'margin-bottom:6px;cursor:pointer;overflow:hidden';
      var host = '';
      try { host = new URL(u).host; } catch (e) { host = ''; }
      row.innerHTML = '<div style="font-weight:600;white-space:nowrap;overflow:hidden;'
        + 'text-overflow:ellipsis">' + shortName(u) + '</div>'
        + '<div style="opacity:.55;font-size:11px;white-space:nowrap;overflow:hidden;'
        + 'text-overflow:ellipsis">' + host + '</div>';
      panel.appendChild(row);
    });

    var tip = document.createElement('div');
    tip.style.cssText = 'opacity:.5;font-size:11px;padding:2px 2px 6px';
    tip.textContent = '点条目 → 交给 App 下载';
    panel.appendChild(tip);

    panel.addEventListener('click', function (e) {
      var target = e.target;
      while (target && target !== panel) {
        if (target.getAttribute && target.getAttribute('data-act') === 'close') {
          closePanel();
          return;
        }
        var u = target.getAttribute && target.getAttribute('data-url');
        if (u) {
          if (!openApp(u)) {
            try { navigator.clipboard.writeText(u); } catch (err) { /* 忽略 */ }
          }
          closePanel();
          return;
        }
        target = target.parentNode;
      }
    });

    document.body.appendChild(panel);
  }

  // ---------------------------------------------------------------- 钩子

  var nativeFetch = window.fetch;
  if (typeof nativeFetch === 'function') {
    window.fetch = function (input) {
      try {
        if (typeof input === 'string') { report(input); }
        else if (input && input.url) { report(input.url); }
      } catch (e) { /* 忽略 */ }
      var p = nativeFetch.apply(this, arguments);
      try {
        p.then(function (response) {
          if (response && response.url) { report(response.url); }
        }, function () {});
      } catch (e) { /* 忽略 */ }
      return p;
    };
  }

  var XHR = window.XMLHttpRequest;
  if (XHR && XHR.prototype) {
    var nativeOpen = XHR.prototype.open;
    XHR.prototype.open = function (method, url) {
      try { report(url); } catch (e) { /* 忽略 */ }
      return nativeOpen.apply(this, arguments);
    };
    var nativeSend = XHR.prototype.send;
    XHR.prototype.send = function () {
      var self = this;
      try {
        self.addEventListener('load', function () {
          if (self.responseURL) { report(self.responseURL); }
          if (typeof self.responseText === 'string' && self.responseText.indexOf('#EXTM3U') >= 0) {
            var re = /https?:\/\/[^\s"'\\<>()]+?\.m3u8[^\s"'\\<>()]*/gi;
            var m;
            while ((m = re.exec(self.responseText)) !== null) { report(m[0]); }
          }
        });
      } catch (e) { /* 忽略 */ }
      return nativeSend.apply(this, arguments);
    };
  }

  try {
    var proto = window.HTMLMediaElement && window.HTMLMediaElement.prototype;
    var desc = proto ? Object.getOwnPropertyDescriptor(proto, 'src') : null;
    if (desc && desc.set && desc.configurable) {
      Object.defineProperty(proto, 'src', {
        configurable: true,
        enumerable: desc.enumerable,
        get: desc.get,
        set: function (value) {
          try { report(value); } catch (e) { /* 忽略 */ }
          return desc.set.call(this, value);
        }
      });
    }
    var nativeSetAttribute = Element.prototype.setAttribute;
    Element.prototype.setAttribute = function (name, value) {
      try {
        if (typeof name === 'string') {
          var lower = name.toLowerCase();
          if (lower === 'src' || lower === 'data-src') { report(value); }
        }
      } catch (e) { /* 忽略 */ }
      return nativeSetAttribute.apply(this, arguments);
    };
  } catch (e) { /* 忽略 */ }

  function scan() {
    var nodes = document.querySelectorAll('video, audio, source, a[href]');
    for (var i = 0; i < nodes.length; i++) {
      try {
        if (nodes[i].src) { report(nodes[i].src); }
        if (nodes[i].currentSrc) { report(nodes[i].currentSrc); }
        if (nodes[i].tagName === 'A' && nodes[i].href) { report(nodes[i].href); }
      } catch (e) { /* 忽略 */ }
    }
    try {
      var entries = performance.getEntriesByType('resource') || [];
      for (var j = 0; j < entries.length; j++) { report(entries[j].name); }
    } catch (e) { /* 忽略 */ }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', scan);
  } else {
    scan();
  }

  try {
    var observer = new MutationObserver(function () { scan(); });
    observer.observe(document.documentElement || document, { childList: true, subtree: true });
  } catch (e) { /* 忽略 */ }

  var ticks = 0;
  var timer = setInterval(function () {
    ticks += 1;
    scan();
    if (ticks > 60) { clearInterval(timer); }
  }, 1500);
})();
