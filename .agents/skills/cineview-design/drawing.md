# Your own drawing on the scene's time

When no preset does what the content needs, draw it yourself (Canvas, SVG, WebGL) and drive it from
an element's timeline. It then scrubs, stops, reverses and jumps with everything else in the scene.

## D1 Subscribe

```html
<cv-scene zone>
  <cv-animate id="time" from="opacity:0" to="opacity:1" duration="1600" ease="linear"><span class="shadow"></span></cv-animate>
  <canvas id="art"></canvas>
</cv-scene>
<script type="module">
  const time = document.getElementById('time');
  await customElements.whenDefined('cv-animate');
  const draw = (frame) => render(Math.min(Math.max(frame.progress, 0), 1));
  time.timeline.subscribe(draw);
  draw(time.timeline.frame);
</script>
```

The anchor element is real (here a floor shadow that fades in), and its `duration` sets the zone's
length. Draw only when the progress changes (compare with the last value).

## D2 Canvas drawn from progress

- Size the backing store to `clientWidth x devicePixelRatio` (cap DPR at 2) on a ResizeObserver.
- One `requestAnimationFrame` per change; a permanent loop for something the scroll drives costs
  frames for nothing.
- Keep per-frame work under ~3 ms at 1920: fewer than ~1500 sprites (pre-render each sprite once
  to a small canvas and `drawImage` it), no `getImageData`, no shadows.

## D3 A model that assembles from pieces (WebGL)

Suits: a product or a symbol that "comes together" as the reader scrolls; flat-shaded low-poly
reads clean on a light page.

Shape: a canvas the size of the scene, under its text (`position: absolute; inset: 0; z-index: 0;
pointer-events: none`); the model is drawn in a square on the right (the drag target).

Data, built once: triangles with, per vertex, position, face centre, normal, a scattered start
(x, y in -1..1, a tumble phase), part id and wait (when this part starts), colour.

Vertex shader, per frame (only uniforms change: view size, model centre, scale, rotation, progress,
time):

```glsl
float g = clamp((u_progress - a_wait) / 0.42, 0.0, 1.0); g = 1.0 - pow(1.0 - g, 3.0);
float tumble = (1.0 - g) * (a_start.z + u_time * 0.4);
vec3 local = turnX(turnY(a_pos - a_ctr, tumble), tumble * 0.7) * mix(0.55, 1.0, g); // shard shrinks and turns
vec3 q = turnX(turnY(a_ctr + local, u_ry), u_rx);                                   // the reader's rotation
vec2 home = project(q);                                                              // its place on screen
vec2 away = a_start.xy * 0.95 + 0.04 * vec2(sin(u_time * 0.3 + a_start.z), cos(u_time * 0.26 + a_start.z));
gl_Position = vec4(mix(away, home, g), depth(q), 1.0);
float lit = max(0.0, dot(turnX(turnY(a_n, u_ry), u_rx), normalize(vec3(-0.45, -0.6, 0.66))));
v_col = a_col * (0.58 + 0.62 * lit);                                                 // flat shading
```

Parts can move with the progress as well (a wheel: rotate its vertices about its centre by
`u_progress * 4pi` in the shader). A translucent beam: two crossed triangles drawn after the model
with blending and no depth write, alpha `lamp * 0.16`.

Interaction: pointer drag on the square changes `u_ry`/`u_rx` (clamp the tilt), a little inertia
after release, arrow keys turn it too; `touch-action: pan-y` keeps vertical page scroll on touch.

Loop: run `requestAnimationFrame` only while the scene is on screen (IntersectionObserver), the
page is visible, and the pieces are still drifting (`progress < 0.85`); otherwise redraw on change.

Fallback: if `getContext('webgl')` fails, hide the canvas; the copy still explains the point.

## Budgets (check them)

- rAF frame interval P95 under 25 ms while wheel-scrolling through the scene at 1920x1080, compared
  with the same page without the drawing.
- 0 draw calls while the scene is off screen.
- Under reduced motion: the finished state, no drifting.
