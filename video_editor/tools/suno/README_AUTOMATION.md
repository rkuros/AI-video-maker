# Suno CLI Automation Notes

## Overview
This project automates Suno's Create web UI with Playwright so you can generate music from a CLI and save the MP3s in `~/Downloads`.

## Auth / Session
- Uses an existing Chrome login session via CDP connection.
- CAPTCHA is solved manually in the browser.

## Generation Modes
- **Simple tab**: use `--song-desc` only (no lyrics/style fields).
- **Custom tab**: use `--lyrics` and/or `--sound-desc`.

## CLI Usage (Simple mode)
```
python3 /Users/miyanorococo/Repository/Suno-api/suno_cli.py \
  --connect-cdp http://127.0.0.1:9222 \
  --song-desc "Gentle indie pop song about starting over" \
  --count 1
```

## CLI Usage (Custom mode)
```
python3 /Users/miyanorococo/Repository/Suno-api/suno_cli.py \
  --connect-cdp http://127.0.0.1:9222 \
  --lyrics "A short uplifting verse about morning light" \
  --sound-desc "Warm acoustic guitar, soft drums, airy vocals" \
  --count 1
```

## Download Logic
- Primary: watches `studio-api.prod.suno.com/api/feed/v2` responses and extracts `.mp3` URLs.
- Secondary: if a direct `.mp3` response is observed, it saves the response body as-is.
- Saved files go to `~/Downloads`.

## File Naming
- If the feed contains `title/name/clip_name`, it is used for the filename.
- Otherwise falls back to the URL-based UUID name.

## Timeouts / Waiting
- Default wait timeout: **1800 seconds**.
- `--debug` prints a status line every 10 seconds while waiting.

## Credits Handling
- If Create is disabled and page text includes `Out of Credits`, the CLI exits early.

## Key Files
- `suno_cli.py` - CLI implementation
- `dump_create_ui.py` - UI discovery helper
