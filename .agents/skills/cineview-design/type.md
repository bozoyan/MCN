# Type

Animated text stays real text: copies the framework makes for animation are hidden from screen
readers, the original stays selectable. The examples use `--font-display`, `--font-body`, `--ink`,
`--accent`, `--line` (see `styles.md`); sizes use `--u` (`framework.md`). `axis` needs a font with
that variable axis (Inter, Fraunces, Recursive, Noto Serif SC have weight).

## Title treatments

Very different openings come from the same few pieces: how many lines, how they are aligned, what
moves, and what sits beside them.

**T1 Rows with rules.** Two rows offset from each other, each with a rule running to the screen
edge. Calm, editorial.

```html
<h1 class="t1">
  <span class="row row-1">
    <span class="clip"><cv-animate fx="rise(line)" duration="950"><span>First line,</span></cv-animate></span>
    <cv-animate class="rule" from="scale-x:0" to="scale-x:1" duration="800" delay="450"><span></span></cv-animate>
  </span>
  <span class="row row-2">
    <cv-animate class="rule rule-2" from="scale-x:0" to="scale-x:1" duration="800" delay="650"><span></span></cv-animate>
    <span class="clip"><cv-animate fx="rise(line)" duration="950" delay="1050"><span>second line</span></cv-animate></span>
  </span>
</h1>
```

```css
.t1 { margin: 0; font: 300 calc(150 * var(--u))/1.05 var(--font-display); color: var(--ink); }
.row { display: flex; align-items: center; gap: calc(36 * var(--u)); }
.row-1 { padding-left: var(--m); } .row-2 { justify-content: flex-end; padding-right: var(--m); }
.clip { overflow: clip; overflow-clip-margin: calc(8 * var(--u)); padding-bottom: .08em; }
.rule { flex: 1; height: max(1px, calc(1.6 * var(--u))); }
.rule span { display: block; height: 100%; background: var(--line); } /* the line is the inner span */
.rule::part(layer) { transform-origin: left center; }                  /* the scale is on the layer */
.rule-2::part(layer) { transform-origin: right center; }
```

**T1b Centred stack.** Two or three short lines centred, each rising out of its own clip with a
stagger; a small label above, one sentence and a button below. Neutral; works with most styles.

```html
<h1 class="t1b">
  <span class="clip"><cv-animate fx="rise(line)" duration="900"><span>Plan the scenes.</span></cv-animate></span>
  <span class="clip"><cv-animate fx="rise(line)" duration="900" delay="140"><span>Let the page play them.</span></cv-animate></span>
</h1>
```

```css
.t1b { display: grid; justify-items: center; text-align: center; margin: 0;
       font: 600 calc(112 * var(--u))/1.05 var(--font-display); letter-spacing: -.02em; }
```

**T1c One huge word.** A single word as wide as the screen (`font-size` from the width, e.g.
`calc(330 * var(--u))`), the explanation small underneath. Loud; suits posters, launches.
`fx="axis(wght 200 900)"` makes it gain weight as it enters, or `wipe(left)` reveals it.

**T1d Number first.** A large figure leads (`fx="count"` if it is a real number), the title is the
caption beside or under it. Suits results, events with dates, prices.

**T1e Title over a picture.** The title sits on a full-bleed photo or video (layout L05), on a
gradient or progressive blur so it stays readable; the picture moves (`push`), the title enters
once. Suits brand stories, travel, food.

**T1f Title beside a product.** Left-aligned title and sentence, the product (screenshot, device,
object) on the right entering with `wipe` or `rise`. Suits software and hardware.

**T1g Words that arrive one by one.** `split="words" stagger="90"` with `fx="rise(soft)"`, or each
word lit in turn on a held scene (word scrub, reference 10). Suits a manifesto line.

**T1h Mixed weights.** One or two words in a heavier weight or the accent colour inside a light
title; `axis(wght ...)` can bring the weight in. Suits a single emphasised idea.

## T2 Controlling where a title breaks

Browsers break titles wherever they fit, which sometimes strands one word or one CJK character
on a line. Wrapping each intended line in a span that does not wrap keeps the breaks where they
were meant:

```html
<h2 class="title"><span class="nb">One scene,</span> <span class="nb">one timeline</span></h2>
<h2 class="title"><span class="nb">一个场景，</span><span class="nb">一条时间线</span></h2>
```

```css
.title .nb { display: inline-block; white-space: nowrap; }
```

Notes: Chinese needs no space between the spans (the full-width comma already spaces it);
`display: block` on the spans keeps two lines at every width; on narrow screens the spans may
need `white-space: normal`. `text-wrap: balance` is a lighter alternative for one-line-or-two
titles.

## T3 Typewriter

Suits conversations, AI products, commands. The full text is in the DOM from the start; a few
lines of script reveal it, so nothing reflows:

```js
function typewriter(el, msPerChar = 22) {
  const text = el.textContent, shown = document.createElement('span'), rest = document.createElement('span');
  rest.style.color = 'transparent'; rest.textContent = text; el.replaceChildren(shown, rest);
  let n = 0;
  return new Promise((done) => (function step() {
    shown.textContent = text.slice(0, ++n); rest.textContent = text.slice(n);
    n < text.length ? setTimeout(step, msPerChar) : done();
  })());
}
```

A "typing" indicator (three dots) before each answer reads as a conversation; with reduced motion
the text can simply appear.

## T4 Lines that enter one after another

```html
<cv-animate split="lines" fx="rise(soft)" stagger="140" duration="700">
  <p>First line of a short passage,<br>the second follows,<br>then the third.</p>
</cv-animate>
```

Best for two to four lines; line breaks are measured after fonts load, so it is worth checking at
each width.

## T5 Weight that changes

```html
<cv-animate fx="axis(wght 250 650)" duration="1600"><span class="big">Stay</span></cv-animate>
```

Reads as emphasis arriving; most visible on large words.

## T6 A number that counts

```html
<cv-animate fx="count"><span class="big">2,400</span></cv-animate> <span class="unit">px</span>
<p class="label">of scroll for one zone</p>
```

The digits roll up to the real value; the unit and label stay still.

## T7 A small label above a title

The product name and what it is, above the headline: as a row (`name · what it is`), stacked, in a
pill, or with a short rule under it.

```html
<cv-animate fx="rise(soft)" duration="700">
  <p class="kicker"><span class="kicker-name">Name</span><span class="kicker-what">what it is</span></p>
</cv-animate>
```

```css
.kicker { display: flex; gap: .6em; align-items: baseline; justify-content: center; }
.kicker-name { color: var(--accent); font: 600 calc(28 * var(--u))/1 var(--font-display); }
.kicker-what { color: var(--ink-soft); font: 400 calc(22 * var(--u))/1 var(--font-body); }
```

The layout sits on the inner `<p>`: layout set on a `cv-animate` itself does not reach its
children (`framework.md`).
