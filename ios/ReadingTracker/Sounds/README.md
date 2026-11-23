# Optional real recordings for Focus sounds

Pageturner generates its Focus sounds live, so nothing is needed here. To use a real recording instead of a
generated sound, add a seamlessly looping file named after the sound:

| File | Replaces |
|---|---|
| `rain.m4a` | Rain |
| `cafe.m4a` | Café |
| `fireplace.m4a` | Fire |
| `beach.m4a` | Beach |

`.caf`, `.mp3` and `.wav` also work. Then run `xcodegen` again and rebuild.

Only use recordings you're allowed to sell in an app: your own, or ones licensed for commercial use
without attribution (for example CC0 on freesound.org, or the Pixabay licence). Keep each under about
2 MB (a 1–2 minute loop at 96 kbps AAC is plenty).
