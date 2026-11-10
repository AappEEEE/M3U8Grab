// M3U8 Grab — 注入嗅探脚本
// 在每个页面 documentStart 阶段注入，钩住所有可能拿到 m3u8 / 直链媒体的通道：
//   fetch / XMLHttpRequest / HTMLMediaElement.src / setAttribute / <source> / performance resource timing
// 一旦发现，通过 webkit.messageHandlers.m3u8grab 回传给原生层，做去重后进入「已嗅探」列表。
(function () {
  'use strict';
  if (window.__m3u8grabInstalled) { return; }
  window.__m3u8grabInstalled = true;

  var HANDLER = 'm3u8grab';
  var seen = Object.create(null);
  var HLS_RE = /\.(m3u8|m3u)(\?|#|$)/i;
  var DASH_RE = /\.mpd(\?|#|$)/i;
  var FILE_RE = /\.(mp4|m4v|mov|ts|flv|mkv|webm|mp3|m4a|aac|ogg|wav|opus)(\?|#|$)/i;

  function handlerAvailable() {
    return !!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[HANDLER]);
  }

  function classify(url) {
    if (HLS_RE.test(url)) { return 'hls'; }
    if (DASH_RE.test(url)) { return 'dash'; }
    if (FILE_RE.test(url)) { return 'file'; }
    return null;
  }

  function absolute(raw) {
    if (!raw) { return null; }
    if (typeof raw !== 'string') {
      try { raw = String(raw); } catch (e) { return null; }
    }
    raw = raw.trim();
    if (!raw || raw.indexOf('data:') === 0 || raw.indexOf('blob:') === 0) { return null; }
    var abs;
    try { abs = new URL(raw, location.href).href; } catch (e) { return null; }
    if (!/^https?:/i.test(abs)) { return null; }
    return abs;
  }

  function report(raw, hintKind) {
    var abs = absolute(raw);
    if (!abs) { return; }
    var kind = classify(abs) || hintKind;
    if (!kind) { return; }
    if (seen[abs]) { return; }
    seen[abs] = 1;
    if (!handlerAvailable()) { return; }
    try {
      window.webkit.messageHandlers[HANDLER].postMessage({
        type: 'stream',
        url: abs,
        kind: kind,
        pageURL: location.href,
        pageTitle: document.title || ''
      });
    } catch (e) { /* 忽略 */ }
  }

  function scanText(text) {
    if (!text || text.length > 4000000) { return; }
    // 有些站点把 playlist 地址拼在 JSON / 内联脚本里，用宽松匹配兜住
    var re = /https?:\/\/[^\s"'\\<>()]+?\.(m3u8|m3u|mpd)[^\s"'\\<>()]*/gi;
    var m;
    while ((m = re.exec(text)) !== null) { report(m[0]); }
  }

  // ---------- fetch ----------
  var nativeFetch = window.fetch;
  if (typeof nativeFetch === 'function') {
    window.fetch = function (input, init) {
      var url = null;
      try {
        if (typeof input === 'string') { url = input; }
        else if (input && input.url) { url = input.url; }
      } catch (e) { /* 忽略 */ }
      if (url) { report(url); }

      var promise = nativeFetch.apply(this, arguments);
      try {
        promise.then(function (response) {
          try {
            if (response && response.url) { report(response.url); }
            var ct = response && response.headers ? (response.headers.get('content-type') || '') : '';
            if (/mpegurl|octet-stream|text\/plain/i.test(ct) && response.clone) {
              response.clone().text().then(scanText, function () {});
            }
          } catch (e) { /* 忽略 */ }
        }, function () {});
      } catch (e) { /* 忽略 */ }
      return promise;
    };
  }

  // ---------- XMLHttpRequest ----------
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
          try {
            if (self.responseURL) { report(self.responseURL); }
            if (typeof self.responseText === 'string' && self.responseText.indexOf('#EXTM3U') >= 0) {
              scanText(self.responseText);
            }
          } catch (e) { /* 忽略 */ }
        });
      } catch (e) { /* 忽略 */ }
      return nativeSend.apply(this, arguments);
    };
  }

  // ---------- HTMLMediaElement.src ----------
  function hookMediaSource(proto) {
    if (!proto) { return; }
    try {
      var desc = Object.getOwnPropertyDescriptor(proto, 'src');
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
            if (lower === 'src' || lower === 'data-src' || lower === 'href') {
              report(value);
            }
          }
        } catch (e) { /* 忽略 */ }
        return nativeSetAttribute.apply(this, arguments);
      };
    } catch (e) { /* 忽略 */ }
  }
  hookMediaSource(window.HTMLMediaElement && window.HTMLMediaElement.prototype);

  // ---------- 媒体元素扫描 ----------
  function scanMedia() {
    var nodes = document.querySelectorAll('video, audio, source, track, a[href], link[href], [data-url], [data-video]');
    for (var i = 0; i < nodes.length; i++) {
      var el = nodes[i];
      try {
        if (el.src) { report(el.src); }
        if (el.currentSrc) { report(el.currentSrc); }
        var ds = el.getAttribute && el.getAttribute('data-src');
        if (ds) { report(ds); }
        var du = el.getAttribute && el.getAttribute('data-url');
        if (du) { report(du); }
        var dv = el.getAttribute && el.getAttribute('data-video');
        if (dv) { report(dv); }
        var href = el.getAttribute && el.getAttribute('href');
        if (href) { report(href, null); }
      } catch (e) { /* 忽略 */ }
    }
  }

  // ---------- performance timing ----------
  function scanPerformance() {
    try {
      var entries = performance.getEntriesByType('resource') || [];
      for (var i = 0; i < entries.length; i++) {
        report(entries[i].name);
      }
    } catch (e) { /* 忽略 */ }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', scanMedia);
  } else {
    scanMedia();
  }

  try {
    var observer = new MutationObserver(function (records) {
      for (var i = 0; i < records.length; i++) {
        var added = records[i].addedNodes;
        for (var j = 0; j < added.length; j++) {
          var node = added[j];
          if (node && node.nodeType === 1) {
            try {
              if (node.src) { report(node.src); }
              if (node.querySelectorAll) {
                var inner = node.querySelectorAll('video, source, a[href]');
                for (var k = 0; k < inner.length; k++) {
                  if (inner[k].src) { report(inner[k].src); }
                }
              }
            } catch (e) { /* 忽略 */ }
          }
        }
      }
    });
    observer.observe(document.documentElement || document, { childList: true, subtree: true });
  } catch (e) { /* 忽略 */ }

  var ticks = 0;
  var timer = setInterval(function () {
    ticks += 1;
    scanPerformance();
    if (ticks % 3 === 0) { scanMedia(); }
    if (ticks > 200) { clearInterval(timer); }
  }, 1200);
})();
