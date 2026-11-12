---
name: screenshot
description: Take windowed screenshots of the Moon project for a given scene, camera and time, count the light-culler and script errors in the same run, and analyse the images against the spec's screenshot list. Use for any visual check. Never edits code, specs or tests.
---

# Screenshot procedure

## Inputs
- The spec path and the screenshot list in it (each entry: scene or scenario, camera, time, what to look for, pass criteria).
- If the spec has no screenshot list, stop and report NEEDS_INPUT to the orchestrator. Do not guess what to shoot.

## Steps
1. For each screenshot entry, run the windowed scene once. Use the scenario command when the entry names a scenario:
   `WAYLAND_DISPLAY=wayland-0 timeout 25 tools/godot/godot --display-driver wayland --path . --script scripts/scenario.gd -- <N> <CAM>`
   For the main scene without a scenario, use `--path .` with the same display flags.
2. Save the image to the scratchpad. A scene-side save is needed, because the window cannot be captured from outside. Use a temporary script in the scratchpad that extends the scenario script and calls `root.get_texture().get_image().save_png(<scratchpad path>)`, as the earlier screenshot runs did. Remove any temporary script from the repository afterwards.
3. Capture the full log of the same run. Count lines matching `create_frustum_points` and `ERROR`, and list each distinct ERROR and SCRIPT ERROR line.
4. Open each image with the Read tool and describe what is visible: horizon, sky, terrain, rocks, craters, shadows, colour, seams, floating or buried objects, anything that looks wrong. Compare against the pass criteria in the spec entry.
5. Mark each entry PASS only if the image meets the pass criteria and the error count is 0. Otherwise mark it FAIL and say what is wrong. Mark as pending for the user anything the image cannot settle (for example frame rate on the user's monitor).

## Lit or dark side (required before judging)
Before judging an image, state whether the camera point is on the lit side of the Moon: run the scenario headless with the same arguments (`HEADLESS=1 make scenario N=<N> CAM=<CAM> [SUN_EL=<el>]`) and read the `sun local elevation` line, which is the Sun's elevation above the local horizon at the point. Elevation above 0 means lit. Write "lit, Sun elevation <x> deg" or "dark side, Sun elevation <x> deg" in the report line for each entry. A dark-side point is not a failure by itself; judge it against what the spec expects for a dark-side view, and say so.

## Rules
- Never edit specs, tests, implementation code or agent files.
- Never remove or overwrite a screenshot from an earlier run without listing it in the report.
- Keep each command under 60 seconds. Leave no Godot process running (check with pgrep).
- Do not use any Fable model.

## Report format (final message)
```
STATUS: PASS | FAIL | PARTIAL
SCREENSHOTS:
- <entry name> | <scene, camera, time> | <file path> | <PASS|FAIL|PENDING> | <what you see, in one or two lines> | errors: <count>
ERRORS: <distinct ERROR and SCRIPT ERROR lines across the runs, or none>
PENDING_USER: <what the image cannot settle>
NOTES: <anything you could not do>
```
