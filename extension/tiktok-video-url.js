// TikTok gives the background page nothing yt-dlp can use on the home feed:
// the video src is a blob: URL and pageUrl stays bare tiktok.com/ (never
// rewritten while scrolling). Feed items carry no permalink anchor either —
// but the player wrapper id embeds the video id (xgwrapper-<n>-<videoid>) and
// the article's author link supplies the username. Record the reconstructed
// URL under each right-click so the background can ask for it on menu click.
// yt-dlp resolves by id alone, so a placeholder user covers a missing author.
//
// TikTok also replaces the native context menu on its player with its own
// (Speed/Quality/Download video/Share), which would hide our menu items
// entirely. Same trick as X: a capture-phase stopImmediatePropagation at
// document level keeps TikTok's handler from firing, so the native menu (and
// our items) shows instead.

let lastVideoUrl = null;

const VIDEO_HREF = /tiktok\.com\/(@[\w.-]+)\/video\/(\d+)/;

document.addEventListener('contextmenu', (e) => {
  lastVideoUrl = null;
  if (!(e.target instanceof Element)) return;

  // Explore/profile grids wrap each card in its permalink anchor.
  const anchor = e.target.closest('a[href]');
  if (anchor) {
    const m = new URL(anchor.getAttribute('href'), location.origin).href.match(VIDEO_HREF);
    if (m) lastVideoUrl = 'https://www.tiktok.com/' + m[1] + '/video/' + m[2];
  }

  // Feed articles: reconstruct the permalink from wrapper id + author link.
  if (!lastVideoUrl) {
    const article = e.target.closest('article');
    const wrapper = e.target.closest('[id^="xgwrapper-"]')
      || (article && article.querySelector('[id^="xgwrapper-"]'));
    const id = wrapper && wrapper.id.match(/^xgwrapper-\d+-(\d+)$/);
    if (id) {
      const author = article && article.querySelector('a[href*="/@"]');
      const user = author
        && new URL(author.getAttribute('href'), location.origin).pathname.match(/^\/(@[\w.-]+)/);
      lastVideoUrl = 'https://www.tiktok.com/' + (user ? user[1] : '@_') + '/video/' + id[1];
    }
  }

  // Keep TikTok's custom menu off the player so the native one appears.
  if (e.target.closest('[id^="xgwrapper-"], video, [data-e2e="feed-video"]')) {
    e.stopImmediatePropagation();
  }
}, true);

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg && msg.type === 'get-tiktok-url') sendResponse({ url: lastVideoUrl });
});
