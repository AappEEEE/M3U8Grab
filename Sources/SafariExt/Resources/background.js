// M3U8 Grab — Safari 扩展后台页：按标签页聚合嗅探结果
(function () {
  'use strict';
  var api = (typeof browser !== 'undefined' && browser.runtime) ? browser : chrome;
  var buckets = {};   // tabId -> [{url, kind, pageURL, pageTitle, at}]
  var MAX_PER_TAB = 40;

  function badge(tabId, count) {
    try {
      api.browserAction.setBadgeText({ tabId: tabId, text: count > 0 ? String(count) : '' });
      api.browserAction.setBadgeBackgroundColor({ tabId: tabId, color: '#0A84FF' });
    } catch (e) { /* 忽略 */ }
  }

  function persist() {
    try {
      api.storage.local.set({ buckets: buckets });
    } catch (e) { /* 忽略 */ }
  }

  try {
    api.storage.local.get(['buckets'], function (data) {
      if (data && data.buckets) { buckets = data.buckets; }
    });
  } catch (e) { /* 忽略 */ }

  function add(tabId, item) {
    if (tabId === undefined || tabId === null || tabId < 0) { tabId = -1; }
    var list = buckets[tabId] || (buckets[tabId] = []);
    for (var i = 0; i < list.length; i++) {
      if (list[i].url === item.url) { return; }
    }
    list.unshift(item);
    if (list.length > MAX_PER_TAB) { list.length = MAX_PER_TAB; }
    buckets[tabId] = list;
    badge(tabId, list.length);
    persist();
  }

  api.runtime.onMessage.addListener(function (message, sender, sendResponse) {
    if (!message || !message.type) { return; }

    if (message.type === 'found') {
      var tabId = sender && sender.tab ? sender.tab.id : -1;
      add(tabId, {
        url: message.url,
        kind: message.kind || 'hls',
        pageURL: message.pageURL || '',
        pageTitle: message.pageTitle || '',
        at: Date.now()
      });
      if (sendResponse) { sendResponse({ ok: true }); }
      return true;
    }

    if (message.type === 'list') {
      var key = message.tabId;
      var lists = buckets[key] || [];
      var all = [];
      for (var bucketKey in buckets) {
        if (!Object.prototype.hasOwnProperty.call(buckets, bucketKey)) { continue; }
        all = all.concat(buckets[bucketKey]);
      }
      // 当前标签页的排前面，其余作为「最近」补充
      var current = lists.slice();
      for (var i = 0; i < all.length && current.length < MAX_PER_TAB; i++) {
        var exists = false;
        for (var j = 0; j < current.length; j++) {
          if (current[j].url === all[i].url) { exists = true; break; }
        }
        if (!exists) { current.push(all[i]); }
      }
      if (sendResponse) { sendResponse({ items: current }); }
      return true;
    }

    if (message.type === 'clear') {
      var target = message.tabId;
      if (target === undefined || target === null) {
        buckets = {};
      } else {
        buckets[target] = [];
        badge(target, 0);
      }
      persist();
      if (sendResponse) { sendResponse({ ok: true }); }
      return true;
    }

    if (message.type === 'count') {
      var count = (buckets[message.tabId] || []).length;
      if (sendResponse) { sendResponse({ count: count }); }
      return true;
    }

    return false;
  });

  api.tabs.onUpdated.addListener(function (tabId, changeInfo) {
    if (changeInfo && changeInfo.status === 'loading' && changeInfo.url) {
      buckets[tabId] = [];
      badge(tabId, 0);
      persist();
    }
  });

  api.tabs.onRemoved.addListener(function (tabId) {
    delete buckets[tabId];
    persist();
  });
})();
