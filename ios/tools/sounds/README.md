# Sound tools

Used to make the Focus sound loops in `ReadingTracker/Sounds`. Needs Python 3 with numpy and scipy, and ffmpeg.

```
python3 render_cafe.py cafe_raw.wav 94          # renders 94 s of café ambience
python3 render_beach.py beach_raw.wav 104       # renders 104 s of beach
python3 make_loop.py cafe_raw.wav cafe.m4a --seconds 90 --start 0
python3 make_loop.py "Rain (1).ogg" rain.m4a --seconds 40          # picks the steadiest stretch
python3 make_loop.py fire.ogg fireplace.m4a --seconds 60 --shuffle --roar 4
```
The loop length in frames (seconds × 44100) goes in `ReadingTracker/Sounds/loops.json`.
