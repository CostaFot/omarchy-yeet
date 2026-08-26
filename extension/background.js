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

chrome.contextMenus.onClicked.addListener((info) => {
  const app = info.menuItemId.startsWith('tg') ? 'telegram' : 'viber';

  if (String(info.menuItemId).endsWith('-video')) {
    // Prefer a directly fetchable media URL; YouTube-style blob: sources fall
    // back to the page URL, which yt-dlp resolves itself.
    const direct = info.srcUrl && /^https?:/i.test(info.srcUrl) ? info.srcUrl : null;
    send({ app, kind: 'video', url: direct || info.pageUrl });
  } else if (info.mediaType === 'image' && info.srcUrl) {
    downloadThenShare(app, info.srcUrl);
  } else if (info.linkUrl) {
    send({ app, kind: 'text', text: info.linkUrl });
  } else if (info.selectionText) {
    send({ app, kind: 'text', text: info.selectionText });
  } else {
    send({ app, kind: 'text', text: info.pageUrl });
  }
});

// Images go through chrome.downloads (browser session/cookies, handles data:
// URLs, uniquified names in ~/Downloads); the host is told the final path.
// The pending {downloadId: app} map lives in session storage so it survives
// service-worker eviction between download start and completion.
async function downloadThenShare(app, url) {
  try {
    const id = await chrome.downloads.download({ url, conflictAction: 'uniquify' });
    const { pending = {} } = await chrome.storage.session.get('pending');
    pending[id] = app;
    await chrome.storage.session.set({ pending });
  } catch (e) {
    send({ app, kind: 'error', message: 'Image download failed to start' });
  }
}

chrome.downloads.onChanged.addListener(async (delta) => {
  if (!delta.state) return;
  const { pending = {} } = await chrome.storage.session.get('pending');
  const app = pending[delta.id];
  if (!app) return;

  if (delta.state.current === 'complete') {
    const [item] = await chrome.downloads.search({ id: delta.id });
    if (item && item.filename) {
      send({ app, kind: 'file', path: item.filename });
    }
  } else if (delta.state.current === 'interrupted') {
    send({ app, kind: 'error', message: 'Image download failed' });
  } else {
    return;
  }

  delete pending[delta.id];
  await chrome.storage.session.set({ pending });
});
