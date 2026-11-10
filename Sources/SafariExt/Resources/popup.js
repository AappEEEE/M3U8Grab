// M3U8 Grab — 扩展弹窗
(function () {
  'use strict';
  var api = (typeof browser !== 'undefined' && browser.runtime) ? browser : chrome;

  var listEl = document.getElementById('list');
  var emptyEl = document.getElementById('empty');
  var hintEl = document.getElementById('hint');
  var clearEl = document.getElementById('clear');
  var currentTabId = -1;

  function fileName(url) {
    try {
      var u = new URL(url);
      var last = u.pathname.split('/').filter(Boolean).pop();
      return last ? decodeURIComponent(last) : u.host;
    } catch (e) {
      return url;
    }
  }

  function copy(text, button) {
    function done() {
      button.textContent = '已复制';
      button.classList.add('copied');
      setTimeout(function () {
        button.textContent = '复制';
        button.classList.remove('copied');
      }, 1400);
    }

    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(done, fallback);
    } else {
      fallback();
    }

    function fallback() {
      try {
        var area = document.createElement('textarea');
        area.value = text;
        area.style.position = 'fixed';
        area.style.opacity = '0';
        document.body.appendChild(area);
        area.select();
        document.execCommand('copy');
        document.body.removeChild(area);
        done();
      } catch (e) { /* 忽略 */ }
    }
  }

  // 深链跳转本体 App：m3u8grab://open?url=...&page=...&title=...
  function openInApp(url, pageURL, title) {
    var link = 'm3u8grab://open?url=' + encodeURIComponent(url)
      + '&page=' + encodeURIComponent(pageURL || '')
      + '&title=' + encodeURIComponent(title || '');
    try {
      var a = document.createElement('a');
      a.href = link;
      a.style.display = 'none';
      document.body.appendChild(a);
      a.click();
      setTimeout(function () {
        try { document.body.removeChild(a); } catch (e) { /* 忽略 */ }
      }, 800);
    } catch (e) { /* 忽略 */ }
  }

  function render(items) {
    listEl.innerHTML = '';
    hintEl.classList.add('hidden');

    if (!items || items.length === 0) {
      emptyEl.classList.remove('hidden');
      return;
    }
    emptyEl.classList.add('hidden');

    items.forEach(function (item) {
      var li = document.createElement('li');

      var row = document.createElement('div');
      row.className = 'row';

      var badge = document.createElement('span');
      badge.className = 'badge';
      badge.textContent = item.kind === 'hls' ? 'M3U8' : (item.kind === 'dash' ? 'DASH' : '文件');

      var name = document.createElement('span');
      name.className = 'name';
      name.textContent = fileName(item.url);
      name.title = item.url;

      row.appendChild(badge);
      row.appendChild(name);

      var urlLine = document.createElement('p');
      urlLine.className = 'url';
      urlLine.textContent = item.url;

      var actions = document.createElement('div');
      actions.className = 'actions';

      var copyBtn = document.createElement('button');
      copyBtn.className = 'act';
      copyBtn.textContent = '复制';
      copyBtn.addEventListener('click', function () { copy(item.url, copyBtn); });

      var pageBtn = document.createElement('button');
      pageBtn.className = 'act';
      pageBtn.textContent = '打开页面';
      pageBtn.addEventListener('click', function () {
        if (item.pageURL) { api.tabs.create({ url: item.pageURL }); }
      });

      var appBtn = document.createElement('button');
      appBtn.className = 'act primary';
      appBtn.textContent = '在 App 打开';
      appBtn.addEventListener('click', function () {
        openInApp(item.url, item.pageURL, item.pageTitle);
      });

      actions.appendChild(appBtn);
      actions.appendChild(copyBtn);
      actions.appendChild(pageBtn);

      li.appendChild(row);
      li.appendChild(urlLine);
      li.appendChild(actions);
      listEl.appendChild(li);
    });
  }

  function load() {
    hintEl.classList.remove('hidden');
    api.tabs.query({ active: true, currentWindow: true }, function (tabs) {
      currentTabId = (tabs && tabs[0] && typeof tabs[0].id === 'number') ? tabs[0].id : -1;
      api.runtime.sendMessage({ type: 'list', tabId: currentTabId }, function (response) {
        render((response && response.items) || []);
      });
    });
  }

  clearEl.addEventListener('click', function () {
    api.runtime.sendMessage({ type: 'clear', tabId: currentTabId }, function () {
      listEl.innerHTML = '';
      emptyEl.classList.remove('hidden');
    });
  });

  load();
})();
