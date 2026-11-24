# Focus sounds

Every Focus sound in Pageturner is original to the app: rendered by the scripts in `ios/tools/sounds`.
No third-party recordings are included, so no credits or licences are needed. (The two recordings that Rain and Fire
were measured against are public domain in any case.)

| File | Made by | What's in it |
|---|---|---|
| `rain.m4a` | `texture.py` | new audio shaped to have the same measured character (tone, flicker, how bands move together) as a public-domain rain recording, [Rain (1).ogg](https://commons.wikimedia.org/wiki/File:Rain_(1).ogg). The recording is only measured, never copied |
| `fireplace.m4a` | `texture.py` + `crackle.py` | the same, measured from the public-domain [Dry grass burning in open fireplace.ogg](https://commons.wikimedia.org/wiki/File:Dry_grass_burning_in_open_fireplace.ogg), plus new crackles with the measured timing, size and tone |
| `cafe.m4a` | `render_cafe.py` | seven tables of murmured conversation, cups, spoons, cutlery, a chair, an espresso machine, the room |
| `beach.m4a` | `render_beach.py` | waves that swell, crash and fizz back as foam, distant surf, a light breeze |

White noise is generated live by the app.

Each file is a seamless stereo loop with a copy of its first 8192 samples after the loop point; the app plays exactly
the number of frames in `loops.json` and uses that copy to keep the join clean.
