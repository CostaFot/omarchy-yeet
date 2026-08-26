// Bump the numeric suffix (and the manifest reference) when editing this file:
// Chromium can keep serving a cached service worker under the old name.

const HOST = 'com.costa.messenger_share';

// The native host owns all desktop notifications, so we hand off and ignore the reply.
function send(msg) {
  chrome.runtime.sendNativeMessage(HOST, msg, () => {
    void chrome.runtime.lastError;
  });
}

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({ id: 'tg', title: 'Share to Telegram', contexts: ['link', 'image', 'selection', 'page'] });
    chrome.contextMenus.create({ id: 'vb', title: 'Share to Viber', contexts: ['link', 'image', 'selection', 'page'] });
    chrome.contextMenus.create({ id: 'tg-video', title: 'Download video → Telegram', contexts: ['page', 'video'] });
    chrome.contextMenus.create({ id: 'vb-video', title: 'Download video → Viber', contexts: ['page', 'video'] });
  });
});

chrome.contextMenus.onClicked.addListener((info, tab) => {
  const app = info.menuItemId.startsWith('tg') ? 'telegram' : 'viber';

  if (String(info.menuItemId).endsWith('-video')) {
    shareVideo(app, info, tab);
  } else if (info.mediaType === 'image' && info.srcUrl) {
    fetchAndShare(app, info.srcUrl);
  } else if (info.linkUrl) {
    send({ app, kind: 'text', text: info.linkUrl });
  } else if (info.selectionText) {
    send({ app, kind: 'text', text: info.selectionText });
  } else {
    send({ app, kind: 'text', text: info.pageUrl });
  }
});

async function shareVideo(app, info, tab) {
  // Prefer a directly fetchable media URL; YouTube-style blob: sources fall
  // back to the page URL, which yt-dlp resolves itself.
  const direct = info.srcUrl && /^https?:/i.test(info.srcUrl) ? info.srcUrl : null;
  let url = direct || info.pageUrl;

  // On X the page URL only works when already on the tweet's own page; on a
  // timeline (/home, a profile) ask the content script which tweet was under
  // the right-click. Direct src URLs there are low-res previews — the status
  // URL through yt-dlp always wins.
  if (/^https:\/\/(x|twitter)\.com\//.test(info.pageUrl)) {
    const status = info.pageUrl.match(/^https:\/\/(?:x|twitter)\.com\/[^/]+\/status\/\d+/);
    url = status ? status[0] : null;
    if (!url && tab && tab.id != null) {
      url = await chrome.tabs.sendMessage(tab.id, { type: 'get-tweet-url' })
        .then((resp) => resp && resp.url)
        .catch(() => null);
    }
    if (!url) {
      send({ app, kind: 'error', message: 'Could not find the tweet for this video' });
      return;
    }
  }

  send({ app, kind: 'video', url });
}

// Images are fetched by the extension itself (with the page's cookies, thanks
// to host_permissions) and handed to the host as base64. This deliberately
// bypasses chrome.downloads: Brave's "ask where to save each file" setting
// forces a save dialog there even with saveAs: false.
async function fetchAndShare(app, url) {
  try {
    const resp = await fetch(url, { credentials: 'include' });
    if (!resp.ok) throw new Error('HTTP ' + resp.status);
    const blob = await resp.blob();
    const bytes = new Uint8Array(await blob.arrayBuffer());
    let binary = '';
    for (let i = 0; i < bytes.length; i += 0x8000) {
      binary += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
    }
    send({
      app,
      kind: 'blob',
      name: filenameFrom(url, blob.type),
      data: btoa(binary),
    });
  } catch (e) {
    send({ app, kind: 'error', message: 'Image fetch failed: ' + e.message });
  }
}

function filenameFrom(url, mime) {
  let name = '';
  try {
    name = decodeURIComponent(new URL(url).pathname.split('/').pop() || '');
  } catch (e) { /* data: URLs etc. */ }
  name = name.replace(/[^\w.\-]+/g, '_').slice(-80);
  if (!/\.[a-z0-9]{2,5}$/i.test(name)) {
    const ext = (mime || '').split('/')[1] || 'bin';
    name = (name || 'image') + '.' + ext.replace(/[^a-z0-9]/gi, '');
  }
  return name;
}
