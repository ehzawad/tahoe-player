# Tahoe Player Manual QA

## Floating Controls

1. Launch the app:
   `./script/build_and_run.sh /tmp/tahoe-drag-test.mp4`
2. Confirm the floating controls appear over the video near the bottom.
3. Drag the handle slowly in a short circle.
   Expected: the panel tracks the pointer smoothly with no visible vibration.
4. Drag the handle quickly across the window.
   Expected: the panel stays under the pointer and does not jump backward.
5. Release the drag and click these controls:
   - play/pause
   - timeline scrubber
   - volume slider
   - subtitle menu, when present
   Expected: each control responds immediately and does not toggle the video surface underneath.
6. Double-click the handle.
   Expected: the controls return to the default bottom-center position.
7. Resize the window after moving the controls.
   Expected: the panel remains visible and clamped inside the window bounds.

## libmpv EOF Replay

1. Open a short file through the libmpv path, such as `.mkv`, `.webm`, or `.avi`.
2. Let playback reach the last frame.
   Expected: playback stops on the last frame.
3. Press play once.
   Expected: playback restarts from `0:00` instead of staying stuck at EOF.
4. Repeat after seeking near the end and letting playback finish again.
   Expected: replay still starts from the beginning.
5. Open a second libmpv-backed file immediately after EOF on the first file.
   Expected: the new file opens normally and does not inherit stale EOF state.
