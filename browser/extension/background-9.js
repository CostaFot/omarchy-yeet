// Bump the numeric suffix (and the manifest reference) when editing this file:
// Chromium can keep serving a cached service worker under the old name.

const HOST = 'com.costa.yeet';

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
    // Instagram wraps feed videos in their permalink anchor, and TikTok's
    // explore/profile grids wrap each card the same way — a 'link' context,
    // where the page/video items above never show. These link-scoped twins
    // appear only on post/reel/video hrefs.
    const postLinks = [
      'https://www.instagram.com/p/*', 'https://www.instagram.com/reel/*', 'https://www.instagram.com/reels/*',
      'https://www.tiktok.com/*/video/*',
    ];
    chrome.contextMenus.create({ id: 'tg-video-link', title: 'Download video → Telegram', contexts: ['link'], targetUrlPatterns: postLinks });
    chrome.contextMenus.create({ id: 'vb-video-link', title: 'Download video → Viber', contexts: ['link'], targetUrlPatterns: postLinks });
  });
});

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  const app = info.menuItemId.startsWith('tg') ? 'telegram' : 'viber';

  if (String(info.menuItemId).includes('-video')) {
    shareVideo(app, info, tab);
  } else if (info.mediaType === 'image' && info.srcUrl) {
    fetchAndShare(app, info.srcUrl);
  } else if (info.linkUrl) {
    send({ app, kind: 'text', text: info.linkUrl });
  } else if (info.selectionText) {
    send({ app, kind: 'text', text: info.selectionText });
  } else {
    send({ app, kind: 'text', text: (await feedPostUrl(info, tab)) || info.pageUrl });
  }
});

// Feed surfaces make pageUrl useless for a plain page share — an X timeline
// is /home, TikTok's For You is bare tiktok.com/ — but the content scripts
// already track the post under each right-click for the video path. Ask them;
// returns null off these sites or when no post was under the click, and the
// caller falls back to pageUrl (correct on detail pages and profiles).
async function feedPostUrl(info, tab) {
  const query =
    /^https:\/\/(x|twitter)\.com\//.test(info.pageUrl) ? 'get-tweet-url' :
    /^https:\/\/(?:www\.)?instagram\.com\//.test(info.pageUrl) ? 'get-post-url' :
    /^https:\/\/(?:www\.)?tiktok\.com\//.test(info.pageUrl) ? 'get-tiktok-url' :
    null;
  if (!query || !tab || tab.id == null) return null;
  return chrome.tabs.sendMessage(tab.id, { type: query })
    .then((resp) => resp && resp.url)
    .catch(() => null);
}

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

  // Instagram: same story — feed videos are blob: sources on a pageUrl of
  // just instagram.com/. The reels viewer rewrites pageUrl to /reels/<id>/
  // as you scroll, so try that first, then ask the content script which post
  // was under the right-click. Everything is normalized to /p/<shortcode>/,
  // which yt-dlp resolves anonymously for posts and reels alike.
  if (/^https:\/\/(?:www\.)?instagram\.com\//.test(info.pageUrl)) {
    // Feed videos sit inside their permalink anchor, so linkUrl (when the
    // click came from a link-context item) is the most precise source.
    const post = (info.linkUrl || '').match(/\/(?:p|reels?|tv)\/(?!audio\/)([\w-]+)/)
      || info.pageUrl.match(/\/(?:p|reels?|tv)\/(?!audio\/)([\w-]+)/);
    url = post ? 'https://www.instagram.com/p/' + post[1] + '/' : null;
    if (!url && tab && tab.id != null) {
      url = await chrome.tabs.sendMessage(tab.id, { type: 'get-post-url' })
        .then((resp) => resp && resp.url)
        .catch(() => null);
    }
    if (!url) {
      send({ app, kind: 'error', message: 'Could not find the Instagram post for this video' });
      return;
    }
  }

  // TikTok: feed videos are blob: sources on a bare tiktok.com/ pageUrl.
  // Detail pages already name the video in pageUrl, and grid cards carry it
  // in linkUrl; only the home feed needs the content script, which
  // reconstructs the permalink from the player wrapper id + author link.
  if (/^https:\/\/(?:www\.)?tiktok\.com\//.test(info.pageUrl)) {
    const TIKTOK_VIDEO = /tiktok\.com\/(@[\w.-]+)\/video\/(\d+)/;
    const post = (info.linkUrl || '').match(TIKTOK_VIDEO) || info.pageUrl.match(TIKTOK_VIDEO);
    url = post ? 'https://www.tiktok.com/' + post[1] + '/video/' + post[2] : null;
    if (!url && tab && tab.id != null) {
      url = await chrome.tabs.sendMessage(tab.id, { type: 'get-tiktok-url' })
        .then((resp) => resp && resp.url)
        .catch(() => null);
    }
    if (!url) {
      send({ app, kind: 'error', message: 'Could not find the TikTok video' });
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
