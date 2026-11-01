# Drag mode

`<cv-stage input="drag">`: one scene per screen; the reader drags up or down and the finger scrubs
the scene change (the leaving scene's exits and the arriving scene's entrances). Release past the
threshold commits; otherwise it springs back. Made for phones and immersive sequences.

## G1 A drag page

```html
<cv-stage id="story" input="drag" design-width="750" transition-duration="720" threshold="0.32 0.15 1200">
  <cv-scene id="open">
    <cv-animate fx="rise(soft)" duration="600" exit="opacity:0; y:-40" exit-duration="400" ease="linear">
      <h1>Cineview</h1>
    </cv-animate>
    <cv-animate fx="fade" duration="500" after="title" ease="linear"><p>Hold and drag up</p></cv-animate>
  </cv-scene>
  <cv-scene id="count">
    <cv-animate fx="count" duration="900" ease="linear"><span class="big">41</span></cv-animate>
  </cv-scene>
  <cv-scene id="end" theme="night">...</cv-scene>
</cv-stage>
```

- `ease="linear"` on drag lanes: the finger's position maps straight to the frame (easing makes
  the scrub feel late at the start and rushed at the end).
- Each scene fills the screen: design at `design-width="750"` (a phone), large type (title 80u+,
  body 30u+), one composition per scene, 3 to 6 scenes.
- Give every element an `exit`, so a scene clears as it leaves.
- No native scrollers or snap strips inside a scene: the finger is for the scene change.

## G2 Embed a drag page in a scroll page (a phone demo)

The scroll page shows a phone (L17) holding the drag page in an iframe. Both pages are on the same
origin and talk with `postMessage` (strings).

| From | Message | Meaning |
|---|---|---|
| drag page | `cineview-embed-ready` | loaded (also after a reload); the host decides to activate |
| host | `cineview-activate` | the act is on screen: start (leave the dark shell, unpause) |
| host | `cineview-freeze` | the act left the screen: pause everything, including canvas loops |
| drag page | `cineview-embed-finished` / `-unfinished` | the reader reached / left the last scene |
| drag page | `cineview-embed-lang:xx` | the phone's own language toggle was used |

Drag page side (`?deferred` in its URL):

```js
const embedded = window.parent !== window;
const post = (m) => embedded && window.parent.postMessage(m, location.origin);
if (new URLSearchParams(location.search).has('deferred') && embedded) {
  stage.setAttribute('paused', ''); document.documentElement.classList.add('deferred'); // dark shell
  addEventListener('message', (e) => {
    if (e.origin !== location.origin) return;
    if (e.data === 'cineview-activate') { document.documentElement.classList.remove('deferred'); stage.removeAttribute('paused'); }
    if (e.data === 'cineview-freeze') stage.setAttribute('paused', '');
  });
  addEventListener('wheel', (e) => window.parent.scrollBy(0, e.deltaY), { passive: true }); // let the page scroll past the phone
}
stage.addEventListener('cv-enter', () => post(isLastScene() ? 'cineview-embed-finished' : 'cineview-embed-unfinished'));
post('cineview-embed-ready');
```

Host side:

```js
let ready = false, active = false;
const frame = document.getElementById('phone-frame'); // <iframe src="./drag/?deferred">
const sync = () => {
  const r = act.getBoundingClientRect(), inView = r.top <= innerHeight / 2 && r.bottom >= innerHeight / 2;
  if (!ready || inView === active) return;
  active = inView; frame.contentWindow.postMessage(active ? 'cineview-activate' : 'cineview-freeze', location.origin);
};
addEventListener('message', (e) => {
  if (e.origin !== location.origin || e.source !== frame.contentWindow) return;
  if (e.data === 'cineview-embed-ready') { ready = true; active = false; sync(); } // every ready is a fresh page
  if (e.data === 'cineview-embed-finished') act.classList.add('is-finished');
  if (e.data === 'cineview-embed-unfinished') act.classList.remove('is-finished');
  if (String(e.data).startsWith('cineview-embed-lang:')) setLanguage(String(e.data).slice(20));
});
addEventListener('scroll', sync, { passive: true });
```

- When the host's language changes, reload the iframe; it reads the stored language on load.
- A transparent top bar over the phone still takes clicks unless it has `pointer-events: none`
  (with `auto` on its own links).
- Show the act's copy when the drag finishes, and also near the end of the act's scroll, so a
  reader who does not drag still reaches the closing links.
