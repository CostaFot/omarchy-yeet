// The Instagram home feed gives the background page nothing yt-dlp can use:
// the video src is a blob: URL and pageUrl is the bare feed. Record the
// permalink of the post under each right-click so the background can ask for
// it on menu click. The reels viewer needs none of this — Instagram rewrites
// the URL to /reels/<id>/ as you scroll, so pageUrl already names the reel.

let lastPostUrl = null;

// Post shortcodes live under /p/, /reel/, /reels/, or /tv/; /reels/audio/ is
// an audio page, not a post.
const SHORTCODE = /\/(?:p|reels?|tv)\/(?!audio\/)([\w-]+)/;

function postUrlFrom(href) {
  const m = href && href.match(SHORTCODE);
  return m ? 'https://www.instagram.com/p/' + m[1] + '/' : null;
}

document.addEventListener('contextmenu', (e) => {
  lastPostUrl = null;
  if (!(e.target instanceof Element)) return;

  // Profile/explore grids wrap each thumbnail in its permalink anchor.
  const anchor = e.target.closest('a[href]');
  lastPostUrl = postUrlFrom(anchor && anchor.getAttribute('href'));
  if (lastPostUrl) return;

  // Feed posts: the timestamp link is the canonical permalink. The bare-href
  // fallback also matches /liked_by/ links, but those still carry the
  // shortcode, which is all we take from them.
  const article = e.target.closest('article');
  if (!article) return;
  const link = article.querySelector('a[href*="/p/"]:has(time), a[href*="/reel/"]:has(time)')
    || article.querySelector('a[href*="/p/"], a[href*="/reel/"]');
  lastPostUrl = postUrlFrom(link && link.getAttribute('href'));
}, true);

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg && msg.type === 'get-post-url') sendResponse({ url: lastPostUrl });
});
