# Pageturner advert (Instagram, 9:16)

- `pageturner-advert-9x16.mp4`: the advert. 1080 × 1920, 28 seconds, silent (add a track in Instagram).
- `pageturner-advert-9x16-pov.mp4`: the same with a different opening line, for testing which hook works better.
- `pageturner-advert-cover.png`: the cover frame.

## Changing it
The advert is an animated web page, `index.html`, rendered frame by frame.

- Wording and timing are in `index.html` (captions in the HTML, scene start times in `T`).
- The screens are in `assets/`. They come from the cloud build's `testAdvertScreens` screen test and the card render test, in the Lavender colours.
- Re-render with Node, Playwright and ffmpeg installed:

```
node render.js a     # main version
node render.js b     # "POV" opening
```
