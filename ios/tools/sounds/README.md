# Sound tools

Renders Pageturner's Focus sounds (all original; nothing is downloaded). Needs Python 3 with numpy and scipy, and ffmpeg.

```
python3 render_rain.py  rain_raw.wav 64
python3 render_fire.py  fire_raw.wav 74
python3 render_cafe.py  cafe_raw.wav 94
python3 render_beach.py beach_raw.wav 104

# optional: nudge a render's tone towards any reference recording (used only as a guide, never shipped)
python3 match_eq.py rain_raw.wav reference.ogg rain_eq.wav

python3 make_loop.py rain_eq.wav   rain.m4a      --seconds 60  --start 0
python3 make_loop.py fire_raw.wav  fireplace.m4a --seconds 70  --start 0
python3 make_loop.py cafe_raw.wav  cafe.m4a      --seconds 90  --start 0
python3 make_loop.py beach_raw.wav beach.m4a     --seconds 100 --start 0
```
Put the `.m4a` files in `ReadingTracker/Sounds`, and each loop's length in frames (seconds × 44100) in `loops.json`.
