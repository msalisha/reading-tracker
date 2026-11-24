# Sound tools

Renders Pageturner's Focus sounds (all original; reference recordings are only measured, never shipped). Needs Python 3 with numpy and scipy, and ffmpeg.

```
# Rain and Fire: new audio with the measured character of a reference recording (see texture.py)
python3 texture.py rain_reference.ogg rain.wav --seconds 64 --seed 3
python3 texture.py fire_reference.ogg fire_bed.wav --seconds 72 --iterations 25 --seed 5
python3 crackle.py fire_reference.ogg fire_bed.wav fire.wav --gain 0.95 --seed 4

python3 render_cafe.py  cafe_raw.wav 94
python3 render_beach.py beach_raw.wav 104

python3 make_loop.py rain.wav      rain.m4a      --periodic
python3 make_loop.py fire.wav      fireplace.m4a --periodic
python3 make_loop.py cafe_raw.wav  cafe.m4a      --seconds 90  --start 0
python3 make_loop.py beach_raw.wav beach.m4a     --seconds 100 --start 0
```
Put the `.m4a` files in `ReadingTracker/Sounds`, and each loop's length in frames (seconds × 44100) in `loops.json`.
