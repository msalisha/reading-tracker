# Focus sounds

Every Focus sound in Pageturner is original to the app: rendered by the scripts in `ios/tools/sounds`.
No third-party recordings are included, so no credits or licences are needed.

| File | Made by | What's in it |
|---|---|---|
| `rain.m4a` | `render_rain.py`, tone-matched with `match_eq.py` | distant wash, rain drumming on roofs, a dense patter of drops, puddle "plinks", a gutter drip |
| `fireplace.m4a` | `render_fire.py` | the roar and hiss of the flames, bursts of crackles, a log shifting, sap whistling, a small room |
| `cafe.m4a` | `render_cafe.py` | seven tables of murmured conversation, cups, spoons, cutlery, a chair, an espresso machine, the room |
| `beach.m4a` | `render_beach.py` | waves that swell, crash and fizz back as foam, distant surf, a light breeze |

White noise is generated live by the app.

Each file is a seamless stereo loop with a copy of its first 8192 samples after the loop point; the app plays exactly
the number of frames in `loops.json` and uses that copy to keep the join clean.
