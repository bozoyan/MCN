# Video

A video in Cineview is usually scrubbed: its time follows the scene's time, so the reader's
scroll (or finger) plays it forward and back. Treat it as an animated picture, not a player.

## Prepare the file

- Short: 5 to 15 seconds; a zone of 2400 ms maps the whole file onto 2400 px of scroll.
- Every frame a keyframe, so any scroll position seeks instantly:
  `ffmpeg -i in.mp4 -an -vf "scale=720:-2" -c:v libx264 -pix_fmt yuv420p -g 1 -crf 30 -preset slow -movflags +faststart out.mp4`
  (`-g 1` is the important part; raise `-crf` to 33 for smaller files.)
- Size to its frame on screen (a 250-px frame needs about 360 px wide), no audio.
- A poster that is the first frame of the part you map (frame 0, or the start of `range`), so
  nothing jumps when the video takes over: `ffmpeg -i out.mp4 -frames:v 1 poster.jpg`. Check
  any poster you are given: if it is a later frame, make a new one.
- For blur effects, a stand-in a few pixels wide: `ffmpeg -i poster.jpg -vf scale=24:-1 poster-tiny.jpg`.

## V1 a clip that plays as you scroll

Suits: a product in motion, a short scene, a demo. Layout L01 or L05.

```html
<cv-scene zone>
  <section class="v1">
    <div class="v1-copy"><h2>Watch it work</h2><p>Scroll to play the clip, back to rewind.</p></div>
    <cv-video class="v1-clip" src="clip.mp4" poster="clip.jpg" duration="2400" ease="linear"
              aria-label="The editor applying a cut"></cv-video>
  </section>
</cv-scene>
```

```css
.v1 { display: grid; grid-template-columns: 620fr 900fr; align-items: center;
      gap: calc(100 * var(--u)); height: 100svh; padding: calc(150 * var(--u)) var(--m) calc(70 * var(--u)); }
.v1-clip { display: block; aspect-ratio: 16 / 9; border-radius: calc(18 * var(--u)); overflow: hidden; }
.v1-clip::part(video) { width: 100%; height: 100%; object-fit: cover; }
```

`duration` is the zone's length (the anchor); `range="2 8"` maps only seconds 2 to 8. In V2 the
video has both `at` and `duration`: its `duration` (2400) is what sets the zone's length; the other
layers only use `at` and keep their own short default durations.

## V2 film strip, three treatments in turn

Suits: several stills from one shoot or one clip; showing that one set of pictures can be treated
(focus, two inks, then played). Layout L12. Zone 2400.

```html
<cv-scene zone>
  <section class="strip-scene">
    <h2>Treatments can be layered</h2>
    <div class="strip">
      <span class="holes holes-top"></span><span class="holes holes-bottom"></span>
      <div class="frames">
        <!-- frames 1, 2, 4, 5: dim while the middle opens -->
        <cv-animate class="frame" from="opacity:1" to="opacity:0.28" at="55% 70%" ease="linear">
          <cv-animate class="layer" fx="focus" at="0% 8%" ease="linear">
            <cv-animate class="layer" fx="duotone(var(--ink-dark), var(--ink-light))" at="28% 38%" ease="linear">
              <img src="still-1.jpg" data-cv-blurred="still-1-tiny.jpg" alt="" width="360" height="640">
            </cv-animate>
          </cv-animate>
        </cv-animate>
        <!-- ...frames 2, 4, 5 the same with at windows shifted by 4% and 3%... -->
        <!-- frame 3: opens and plays -->
        <cv-animate class="frame frame-hero" fx="push(1, 1.42, center)" at="55% 70%" ease="linear">
          <cv-animate class="layer" fx="focus" at="8% 16%" ease="linear">
            <cv-animate class="layer" fx="duotone(var(--ink-dark), var(--ink-light))" at="34% 44%" ease="linear">
              <img src="poster.jpg" data-cv-blurred="poster-tiny.jpg" alt="" width="360" height="640">
            </cv-animate>
          </cv-animate>
          <cv-animate class="layer" fx="fade" at="58% 63%" ease="linear">
            <cv-video src="clip.mp4" poster="poster.jpg" at="60% 100%" duration="2400" ease="linear"
                      aria-label="A night ride, played as you scroll"></cv-video>
          </cv-animate>
        </cv-animate>
      </div>
    </div>
  </section>
</cv-scene>
```

```css
.strip { position: relative; padding: calc(52 * var(--u)) calc(34 * var(--u));
         border-radius: calc(8 * var(--u)); background: var(--film-base, #1d1a18); }
.holes { position: absolute; left: 0; right: 0; height: calc(14 * var(--u)); background: var(--ground);
         mask: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='34' height='14'%3E%3Crect x='8' y='1' width='18' height='12' rx='3'/%3E%3C/svg%3E")
               0 0 / calc(34 * var(--u)) 100% space no-repeat; }
.holes-top { top: calc(16 * var(--u)); } .holes-bottom { bottom: calc(16 * var(--u)); }
.frames { display: flex; gap: calc(22 * var(--u)); }
.frame { position: relative; width: calc(250 * var(--u)); aspect-ratio: 9 / 16;
         border-radius: calc(3 * var(--u)); overflow: hidden; }
.frame-hero { z-index: 2; overflow: visible; }
.layer, .layer > cv-video { position: absolute; inset: 0; }
.frame img, cv-video::part(video) { width: 100%; height: 100%; object-fit: cover; }
```

`--ink-dark` and `--ink-light` are the two print inks (any pair from the page's palette, or a
named pair such as `duotone(mono)`); the film base can be any dark colour.

Why it works: each treatment has its own window, so the reader sees one change at a time; the
holes are drawn in the ground colour on two thin layers (a mask over the whole strip would
re-composite it every frame); the tiny `data-cv-blurred` copies make `focus` a crossfade.

## V3 a drag demo in a phone

Suits: showing the drag mode, an app's own flow. Layout L17 inside a `theme="night"` act. The
phone holds an iframe of a drag page; see `drag.md` for both sides of the protocol.

## Do

- Map the whole file unless the story needs a part (`range`).
- Label every video (`aria-label`); decorative ones get `aria-hidden="true"`.
- A poster on the element keeps the frame filled while the file loads.
