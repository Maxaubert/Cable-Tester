# Cable Tester README film

The 26 s demo at the top of the main README, made with [HyperFrames](https://hyperframes.heygen.com):
HTML scenes that rebuild the real app (Pure Black Lime, SF Pro, 1.6x its point sizes), rendered
frame by frame.

- `SPEC.md`: shots, timings, look and motion rules.
- `index.html` mounts `compositions/splash.html`, `app.html` (checklist, result, save sheet, History) and `endcard.html`.
- SF Pro is not in the repo (Apple licence). Before rendering: `cp /System/Library/Fonts/SFNS.ttf assets/fonts/`.
- Render: `npx hyperframes render --output renders/cable-tester-demo.mp4`; README encodes are in the repo's CLAUDE.md.
