# Interview the user before building

Interview the user about every part of the page until you both picture the same page. Walk down
the decision tree below, settling the decisions that others depend on first. Ask one question at a
time, and give your recommended answer with each one. When the answer can be found in what the
user sent, look it up instead of asking. Write no code until the user has confirmed the
storyboard.

The questions are about the user's page; the answers come from the user. Your recommendations
come from the library in this folder and from their material, and the user is free to take them,
change them or say something else entirely.

## How to ask

- **One question per message.** Wait for the answer before asking the next.
- **A recommended answer with every question**, and the reason in a few words, so "yes" is a
  complete reply. Where the choice is open, add two or three alternatives.
- **Look before you ask.** Open the images (subject, orientation, quality, how many), check videos
  (`ffprobe`: length, size, frame rate, keyframes), read the copy, the current site or the brand
  files. Ask only what the material cannot tell you, and say what you found: "The clip is 10 s and
  portrait; the three screenshots are frames from it."
- **Turn vague answers into a choice.** "Make it look premium" becomes: "Premium as in A quiet and
  spacious, B dark and glossy, or C editorial with large serif titles? I'd suggest A, because your
  photos are bright and need room."
- **Plain words.** Describe what a reader sees ("the photo slides in from the side as you
  scroll"), not attribute names. Use the user's language.
- **Restate each decision in one line** once it is answered, and keep a running decision list.
- **Go back when an answer changes an earlier branch.** A video turns up, the audience changes, a
  scene loses its material: return to that decision, say what changes, settle it again.

## The decision tree

Roughly in this order; each depends on the ones above it.

1. **Purpose and reader.** What the page is for and who reads it. Everything else follows from
   this.
2. **The one thing.** What a reader should remember, or do, after the page.
3. **Material.** What exists (look first), what is missing, and which ideas that rules out.
4. **Direction and number of scenes.** Two or three directions, each with its number of scenes
   and one line per scene; recommend one. Roughly one scene per thing the reader should take
   away, plus an opening and a closing, is usually three to seven; a scene without material to
   show tends to become decoration.
5. **Each scene, one at a time**, as its own small branch:
   1. Point: the one thing this scene says.
   2. What the reader sees: two or three options from the library (`layouts.md`, `type.md`,
      `images.md`, `video.md`, `transitions.md`, `line-art.md`, `combinations.md`), plainly
      described, with your pick.
   3. Mode: an ordinary section, a held scene the scroll plays through, a sideways row, cards that
      stack, or a drag scene on phones. It often follows from the material (a clip suggests a held
      scene the scroll plays, or a background, or a click to play). How the scene hands over to
      the next one belongs here too: a cut, a cover, a transition clip (`transitions.md`).
   4. Material: which of theirs it uses; what it still needs, specifically; what stands in if that
      never arrives (leave the scene out, draw it, a marked placeholder).
   5. Words: theirs, or two or three options (a title and a sentence) in each language.
6. **Look.** A visual direction (`styles.md`) or their brand: fonts, colours, the feel.
7. **Constraints.** Devices that matter most, languages, motion preferences, things it must not
   do, deadline.
8. **Storyboard and material list**, confirmed by the user.

## What a question looks like

> **Scene 2 of 5: what should it show?**
> I'd suggest **one photo per screen, filling it, with its caption sliding in from the left**:
> your eight photos are strong enough to carry the page alone.
> Other options: **B** the photo beside its caption, alternating sides; **C** all eight in a
> sideways row.
> Reply "yes", pick B or C, or tell me what you have in mind.

And a direction proposal (decision 4):

> **A. Quiet gallery (5 scenes).** The photos carry the page, one per screen, with short captions.
> 1 The title over the strongest photo · 2-4 One photo each, the animal's name and place ·
> 5 Dates, address, tickets.
> **B. One walk through the show (3 scenes).** A single long scene where the photos pass by like a
> corridor, then the details.
> I'd suggest A: eight strong photos and a short message need little else.

## The storyboard and the material list

When every scene is settled, show the plan in one place:

| # | Scene | Says | Reader sees | Mode | Material (have / need) |
|---|---|---|---|---|---|

and list everything still needed, with how to prepare it:
- **Video**: 5-15 s, the aspect it will show at, no sound needed, every frame a keyframe so
  scrolling can seek it (`video.md`).
- **Screenshots**: about twice the width they will show at, one device or browser size, real
  content.
- **Photos**: how many, landscape or portrait, similar light if they show as a set.
- **Numbers, quotes, logos**: real ones with their source; logos as SVG.
- **Words**: approximate lengths (a title of two to six words, a sentence of ten to twenty-five).
- **Brand**: colours as hex values, font names or files.

## When it is done

The interview is finished when every scene has its point, what the reader sees, its mode, its
material and its words agreed; the material list says what is still missing and how to prepare
it; and the user has said yes to the storyboard. Then build. Show the page early (a link, or a
screenshot of each scene), and route later changes through the storyboard first, then the page.

## When the user wants it fast

If the user says "just make it" or "you decide", fill the tree with your recommendations, mark
each one as assumed, and show the storyboard and material list in one message. Build after the
user says yes to it.
