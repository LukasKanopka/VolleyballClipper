# VolleyballClipper

Native macOS highlight builder that turns long volleyball footage into an “action only” reel using on-device body-pose analysis (Vision) and lossless passthrough stitching (AVFoundation).

## Run

- Requires Xcode 16.4+ and macOS 15.5+ (Apple Silicon recommended).
- Open `VolleyballClipper.xcodeproj` and run the `VolleyballClipper` target.

## Use

1. Open the app and click **Choose Video…**
2. Click **Analyze & Classify** (progress shows the current timestamp being analyzed).
3. Review the detected clip list.
4. Optional: open **Debug** to tune thresholds and click **Re-run classification** (no re-analysis required).
5. Click **Export Highlights…** to export a `.mov` using passthrough stitching.

## Batch + Diagnostics

Use the **Batch** tab to:

- Select multiple videos
- Choose an output folder
- Run analysis/classification for each video and export diagnostics per video (`summary.json`, `predicted_clips.csv`, and optional `frames.csv` / `debug.csv`)
- `transitions.csv` is also exported to show state machine transitions and trigger context per transition.

## Tuning & Debugging

The **Debug** tab graphs:

- `teamEnergy` over time (movement intensity)
- `huddleScore` over time (inverse centroid spread)

You can adjust:

- **Action energy threshold** (READY → ACTION trigger)
- **Walking energy threshold** and **Reset low-energy seconds** (ACTION → stop trigger for indoor/reset)
- **Huddle score threshold** (ACTION → stop trigger for beach/grass celebration)

## Notes

- Analysis down-samples frames for Vision (default `640x360`) to keep memory usage low.
- Export ranges are aligned to sync samples to keep GOPs intact where possible.
