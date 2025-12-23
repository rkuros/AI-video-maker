# Manual Testing Guide (macOS)

This document describes a repeatable manual test pass for the app.

## Prerequisites

- macOS
- `ffmpeg` and `ffprobe` available in `PATH`
  - `brew install ffmpeg`
- Flutter dependencies installed: `flutter pub get`

## Test Media

Prepare a small set of files:

- Video A: 10–30s MP4 (with audio)
- Video B: 10–30s MP4 (with audio)
- Audio: MP3 or WAV (10–30s)
- Image: PNG or JPG

## Run

```bash
flutter run -d macos
```

## 1) Media Import

### 1.1 Import via picker

- Click `Media Library` → `+` → pick all test media files
- Expected:
  - Items appear in the grid
  - Video/audio durations are not `--:--`
  - Clicking a video item loads it in the Preview panel

### 1.2 Import via drag & drop

- Drag the same files from Finder onto the Media Library panel
- Expected:
  - “Drop files to import” overlay appears while dragging
  - Imported items increase in count

## 2) Timeline Editing

### 2.1 Add tracks

- In Timeline toolbar, click:
  - `Add Video Track`
  - `Add Audio Track`
- Expected:
  - Track lanes appear

### 2.2 Place clips

- Drag Video A from Media Library onto the video track area
- Drag Audio onto the audio track area
- Expected:
  - Clips appear with non-zero width
  - Selecting a clip highlights it and opens Properties

### 2.3 Reorder / move

- Drag a timeline clip onto another position (drag target)
- Expected:
  - Clip start time updates visually

## 3) Properties (Effects / Audio / Noise Reduction / Transitions)

### 3.1 Effect add/remove

- Select a video clip in the timeline
- In Properties → `Effects`:
  - Choose an effect preset → `Add`
  - Remove it via the trash icon
- Expected:
  - “Applied Effects” count increases/decreases
  - Preview Effects button becomes enabled when effects exist

### 3.2 Effect preview

- With effects applied, press `Preview Effects`
- Expected:
  - Preview shows “Effect Preview” badge
  - Playback works on the generated preview
- Press `Exit Preview`
- Expected:
  - Preview returns to the original video

### 3.3 Noise reduction parameters

- Select a video clip
- In Properties → `Noise Reduction`:
  - Enable
  - Adjust sliders (Strength, Temporal Radius, Luma/Chroma)
  - Toggle “Preserve Details”
- Expected:
  - Clip’s effect list includes low-light denoise
  - Parameter changes persist while selection stays on the clip

### 3.4 Transitions

- Select a timeline clip
- In Properties → `Transitions`:
  - Pick a type
  - Apply `In` and/or `Out`
- Expected:
  - Clip shows transition indicators (In/Out tags)

## 4) Playback (Timeline Preview)

- Select `Preview Quality` preset (Timeline toolbar or Preview controls)
- Click Timeline toolbar `Play`
- Expected:
  - On first play after edits (or after changing Preview Quality), it starts a real-time streaming preview (may take a moment)
  - Playback starts at the current timeline position
  - Timeline playhead tracks preview position
- While playing, click on the time ruler / timeline area to seek
- Expected:
  - Stream restarts near the selected position and resumes after a short wait
  - Playback is seamless (no segment switching stutter during continuous play)
- Click `Stop`
- Expected:
  - Playhead returns to 0:00

## 5) Auto Edit / Highlight

### 5.1 Auto Edit

- Import multiple media items
- Click Timeline toolbar `Auto Edit`
- Expected:
  - Timeline is populated with clips

### 5.2 Generate Highlight

- With a non-empty timeline, click `Generate Highlight`
- Expected:
  - Timeline updates to a shorter highlight sequence

## 6) Project Save/Load

### 6.1 Save

- App bar → `Save Project As`
- Choose a `.vedproj` location
- Expected:
  - Success snackbar

### 6.2 Load

- App bar → `Open Project`
- Select the saved `.vedproj`
- Expected:
  - Timeline and media library contents are restored

## 7) Export

- App bar → `Export Video`
- Choose output `.mp4` path
- Expected:
  - Progress dialog advances to 100%
  - Output file is created and playable

## Troubleshooting

- If export/preview fails, verify:
  - `which ffmpeg` and `which ffprobe` return paths
  - The selected output directory is writable
