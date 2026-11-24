# Focus sound recordings

Each file is a seamless stereo loop, loudness-matched to the others, with a copy of its first 8192 samples after the
loop point (the app plays exactly the number of frames listed in `loops.json`, and uses that copy to keep the join clean).

| File | Source | Licence |
|---|---|---|
| `rain.m4a` | Field recording [Rain (1).ogg](https://commons.wikimedia.org/wiki/File:Rain_(1).ogg) by ezwa, Wikimedia Commons | Public domain |
| `fireplace.m4a` | Field recording [Dry grass burning in open fireplace.ogg](https://commons.wikimedia.org/wiki/File:Dry_grass_burning_in_open_fireplace.ogg) by ezwa, Wikimedia Commons, with a soft low roar added | Public domain |
| `cafe.m4a` | Rendered for Pageturner by `tools/sounds/render_cafe.py` (14 synthetic voices in a simulated room, crockery, espresso machine) | Original, owned by the app |
| `beach.m4a` | Rendered for Pageturner by `tools/sounds/render_beach.py` (spectrally shaped waves, foam bubbles, surf, breeze) | Original, owned by the app |

White noise is generated live by the app.

To swap in a real recording later, replace the file and regenerate its loop with
`tools/sounds/make_loop.py SOURCE OUT.m4a --seconds 90`, then update its frame count in `loops.json`
(`seconds × 44100`).
