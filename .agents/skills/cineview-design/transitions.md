# Video and animated transitions

Ideas for pages where a video sits behind the content, plays when the reader clicks, or carries
the change from one scene to the next. Two kinds of time are involved, and most ideas pick one:
- **Scrubbed**: the video's time follows the reader's scroll or finger (`<cv-video>` inside a held
  scene). Stops when they stop, reverses when they reverse.
- **Played**: the video plays at its own speed once something starts it (a click, a scene
  becoming current). Plain `<video>`, or a `<cv-video>` whose timeline has ended (see V4).

## V4 A background video behind a scene

A muted, looping clip fills the scene; the content sits on top over a gradient for contrast.

```html
<cv-scene>
  <section class="bg-scene">
    <video class="bg" src="loop.mp4" poster="loop.jpg" muted loop playsinline autoplay aria-hidden="true"></video>
    <div class="bg-shade"></div>
    <cv-animate class="bg-copy" fx="rise(soft)" duration="800"><h1>...</h1><p>...</p></cv-animate>
  </section>
</cv-scene>
```

```css
.bg-scene { position: relative; height: 100svh; overflow: clip; }
.bg { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; }
.bg-shade { position: absolute; inset: 0; background: linear-gradient(to top, rgb(0 0 0 / .55), transparent 60%); }
.bg-copy { position: relative; z-index: 1; }
```

Notes: a plain `<video>` is enough here because the framework does not drive its time. Pausing it
while the scene is off screen (an IntersectionObserver calling `pause()`/`play()`) saves battery;
with reduced motion, the poster alone works well (`matchMedia('(prefers-reduced-motion: reduce)')`).
Files around 2-6 MB, 6-15 s, cut so the loop point is invisible.

## V5 Click to play, then move on

The scene shows a still (or the background loop). A button plays the real clip in place; when it
ends, the page goes on to the next scene, or the clip stays on its last frame with a "next" button.

```html
<cv-scene id="story">
  <section class="clip-scene">
    <video class="clip" src="story.mp4" poster="story.jpg" playsinline preload="metadata"></video>
    <button class="play" type="button">Play the story</button>
  </section>
</cv-scene>
<cv-scene id="after">...</cv-scene>
```

```js
const clip = document.querySelector('.clip'), play = document.querySelector('.play');
const stage = document.querySelector('cv-stage');
play.addEventListener('click', () => { clip.play(); play.hidden = true; });
clip.addEventListener('ended', () => stage.goTo('after'));   // scroll (smooth) or drag to the next scene
```

Notes: `stage.goTo('after')` scrolls smoothly in scroll mode and runs the scene change in drag
mode. Keeping the controls reachable (a pause button, `controls` on the video, or captions)
matters when the clip carries information; with sound, the click is what browsers require before
audio plays.

## V6 A transition clip between two scenes

A short clip (a whip pan, a door opening, a zoom through a window, ink spreading) plays over the
cut from one scene to the next, so the change feels like a single shot.

In a held scene, the clip can be scrubbed by the scroll: the scene's own timeline is the
transition.

```html
<cv-scene zone>
  <cv-video class="cut" src="cut.mp4" duration="900" ease="linear" aria-hidden="true"></cv-video>
  <cv-animate class="from" from="opacity:1" to="opacity:0" at="0% 45%">...first picture...</cv-animate>
  <cv-animate class="to" from="opacity:0" to="opacity:1" at="55% 100%">...next picture...</cv-animate>
</cv-scene>
```

As a played transition (after a click, or at a scene change in drag mode), the clip sits fixed
over the page, plays, and the page changes scene while it covers the screen:

```js
async function cutTo(id) {
  const cut = document.querySelector('.cut-overlay');           // <video> fixed over the page, hidden
  cut.currentTime = 0; cut.hidden = false; await cut.play();
  setTimeout(() => stage.goTo(id, { animated: false }), 450);   // swap while the clip covers it
  cut.addEventListener('ended', () => (cut.hidden = true), { once: true });
}
```

Notes: the swap happens at the clip's most covered frame (find it by stepping through the file);
the clip's first and last frames can match the two scenes so the cut is invisible.

## V7 A video that starts scrubbed and then plays on

`<cv-video range="0 3">` scrubs the first three seconds with the scroll; when the reader reaches the
end of that range, the rest of the file plays on its own (the framework hands the video to the
browser), for example a product demo that the reader starts and then watches.

## Animated transitions without video

- **Cover**: the next scene slides over the current one (`<cv-scene stack covered="dim">`).
- **Wipe**: the next picture is revealed from one side (`fx="wipe(left)"` on a held scene, the two
  pictures stacked).
- **Zoom through**: the current picture scales up (`push(1, 3, 50% 40%)`) until a detail fills the
  screen, and the next scene starts inside that detail.
- **Shared element**: one object (a product, a logo) stays on screen while the scenery changes
  behind it (`<cv-fixed>` holds it while its scene passes).
- **Fade to black, then lights up**: the scene's palette flips (`theme`), with a short dark beat
  between two acts.
- **Drag**: in drag mode the finger itself scrubs the change between scenes (`drag.md`); exits on
  the leaving scene and entrances on the arriving one are the transition.

## Preparing transition clips

- Short: 0.6-1.5 s for a cut, 5-15 s for a background loop.
- For scrubbing: every frame a keyframe (`video.md`); for playing: a normal encode is fine and
  smaller.
- Muted unless the reader starts it; a poster from the first frame.
- Sized to the screen it covers (1920 wide for full screen on desktop, a portrait cut for phones).
