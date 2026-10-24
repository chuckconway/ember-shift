# Ember Shift

A menu bar app that warms and dims the screen on a schedule, and lets you override that schedule whenever you want.

- **Warmth and brightness as separate sliders.** Brightness dims through the gamma table, so it can go below macOS's minimum.
- **Holds beat the schedule.** Moving a slider or clicking a preset holds that look until the schedule's next change, or until you click *Resume schedule*.
- **A shiftable schedule.** Day, Evening and Night each start at sunrise/sunset ± an offset, or at a clock time, and each eases in over its own number of minutes.
- **Smooth switches.** Presets, Resume, and a hold ending fade over 30 seconds (adjustable). Slider drags are instant.
- **Self-healing.** Every 3 seconds Ember checks the display's gamma table and re-applies its tint if macOS or another app has reset it.

## Build

```sh
./build-app.sh   # runs checks, builds release, installs ~/Applications/Ember.app
```

`swift run EmberSnapshot <dir>` renders the panel and schedule window to PNGs offscreen, without touching the display.

`swift run EmberChecks` runs the core checks: color math, sun times and schedule. Command Line Tools ship neither XCTest nor a usable Swift Testing, so these run as an executable.

Quit f.lux and turn off Night Shift before running Ember. Each one overwrites the gamma table.
