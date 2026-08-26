// X/Twitter timelines give the background page nothing yt-dlp can use: the
// video src is a blob: URL and pageUrl is /home. Record the status URL of the
// tweet under each right-click so the background can ask for it on menu click.
//
// X also replaces the native context menu on its video player with its own,
// which would hide our menu items entirely. This runs at document_start with a
// capture-phase listener, so it sees the event before X's handlers and can
// stop it inside the player — the browser menu (and our items) shows instead.

let lastTweetUrl = null;

document.addEventListener('contextmenu', (e) => {
  lastTweetUrl = null;
  if (!(e.target instanceof Element)) return;

  const article = e.target.closest('article');
  if (article) {
    // The timestamp link is the one canonical /status/ link (quoted tweets
    // and "analytics" links also match on href alone).
    const link = article.querySelector('a[href*="/status/"]:has(time)')
      || article.querySelector('a[href*="/status/"]');
    if (link) {
      const m = new URL(link.getAttribute('href'), location.origin).href
        .match(/^https:\/\/(?:x|twitter)\.com\/[^/]+\/status\/\d+/);
      if (m) lastTweetUrl = m[0];
    }
  }

  // Keep X's custom menu off the video player so the native one appears.
  if (e.target.closest('[data-testid="videoPlayer"], [data-testid="videoComponent"], video')) {
    e.stopImmediatePropagation();
  }
}, true);

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg && msg.type === 'get-tweet-url') sendResponse({ url: lastTweetUrl });
});
