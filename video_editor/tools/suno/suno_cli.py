import argparse
import json
import sys
import time
import urllib.request
import urllib.parse
from pathlib import Path
from typing import Optional, List, Set

from playwright.sync_api import sync_playwright


def get_ws_url(cdp_url: str) -> str:
    version_url = cdp_url.rstrip("/") + "/json/version"
    with urllib.request.urlopen(version_url, timeout=3) as resp:
        payload = json.loads(resp.read().decode("utf-8"))
    return payload["webSocketDebuggerUrl"]


def pick_visible(locator):
    try:
        count = locator.count()
    except Exception:
        return None
    for i in range(count):
        item = locator.nth(i)
        try:
            if item.is_visible():
                return item
        except Exception:
            continue
    return None


def log(message: str) -> None:
    print(message, flush=True)


def log_error(message: str) -> None:
    sys.stderr.write(message + "\n")
    sys.stderr.flush()


def set_textarea_value(locator, value: str) -> None:
    try:
        locator.click()
    except Exception:
        pass
    try:
        locator.fill(value)
    except Exception:
        pass
    try:
        locator.evaluate(
            """(el, v) => {
              el.value = '';
              el.value = v;
              el.dispatchEvent(new Event('input', { bubbles: true }));
              el.dispatchEvent(new Event('change', { bubbles: true }));
            }""",
            value,
        )
    except Exception:
        pass


def detect_disabled_reason(page, use_custom: bool) -> Optional[str]:
    if not use_custom:
        try:
            value = page.evaluate(
                """
                () => {
                  const el = document.querySelector("textarea[placeholder^='Meditative hyperpop song']");
                  if (el && el.value) return el.value;
                  const visible = Array.from(document.querySelectorAll('textarea')).find(t => {
                    const style = window.getComputedStyle(t);
                    return style.display !== 'none' && style.visibility !== 'hidden' && t.getClientRects().length > 0;
                  });
                  return visible && visible.value ? visible.value : '';
                }
                """
            )
        except Exception:
            value = ""
        if not str(value).strip():
            return "song description empty"

    try:
        page_text = (page.evaluate("() => document.body.innerText || ''") or "").lower()
    except Exception:
        page_text = ""

    if "out of credits" in page_text:
        return "out of credits"
    if "sign in" in page_text or "log in" in page_text:
        return "login required"
    if "captcha" in page_text or "hcaptcha" in page_text or "turnstile" in page_text:
        return "captcha required"
    try:
        upgrade_near_create = page.evaluate(
            """
            () => {
              const buttons = Array.from(document.querySelectorAll('button'));
              const createBtn = buttons.find(b => {
                const text = (b.innerText || '').trim();
                const aria = b.getAttribute('aria-label') || '';
                return text === 'Create' || aria === 'Create song';
              });
              if (!createBtn) return false;
              const container = createBtn.closest('div');
              const scope = container || document;
              const upgradeBtn = Array.from(scope.querySelectorAll('button')).find(b => {
                const text = (b.innerText || '').toLowerCase();
                return text.includes('upgrade for full song');
              });
              return !!upgradeBtn;
            }
            """
        )
    except Exception:
        upgrade_near_create = False
    if upgrade_near_create:
        return "upgrade required"

    return None


def sanitize_filename(value: str) -> str:
    cleaned = []
    for ch in value:
        if "a" <= ch <= "z" or "A" <= ch <= "Z" or "0" <= ch <= "9":
            cleaned.append(ch)
        elif ch in (" ", "-", "_"):
            cleaned.append(ch)
    name = "".join(cleaned).strip().replace(" ", "_")
    while "__" in name:
        name = name.replace("__", "_")
    return name[:120]


def extract_mp3_entries(data) -> List[dict]:
    results = []

    def walk(val):
        if isinstance(val, list):
            for v in val:
                walk(v)
        elif isinstance(val, dict):
            mp3s = []
            title = None
            for k, v in val.items():
                if isinstance(v, str):
                    if ".mp3" in v:
                        mp3s.append(v)
                    if k in ("title", "name", "clip_name") and v:
                        title = v
            if mp3s:
                for url in mp3s:
                    results.append({"url": url, "title": title})
            for v in val.values():
                walk(v)

    walk(data)
    return results


def download_mp3(url: str, downloads_dir: Path, title: Optional[str] = None) -> Optional[Path]:
    filename = Path(urllib.parse.urlparse(url).path).name or f"suno_{int(time.time())}.mp3"
    if title:
        safe_title = sanitize_filename(title)
        if safe_title:
            filename = f"{safe_title}.mp3"
    out_path = downloads_dir / filename
    if out_path.exists():
        stem = out_path.stem
        suffix = out_path.suffix
        out_path = downloads_dir / f"{stem}_{int(time.time())}{suffix}"
    try:
        with urllib.request.urlopen(url, timeout=30) as resp:
            out_path.write_bytes(resp.read())
        return out_path
    except Exception:
        return None


def get_song_ids(page) -> Set[str]:
    try:
        ids = page.evaluate(
            """
            () => {
              const ids = [];
              const links = document.querySelectorAll('[data-testid="clip-row"] a[href^="/song/"]');
              for (const a of links) {
                const href = a.getAttribute('href') || '';
                const id = href.split('/song/')[1] || '';
                if (id) ids.push(id);
              }
              return ids;
            }
            """
        )
    except Exception:
        return set()
    return set(ids)


def wait_for_downloads(
    page,
    downloads_dir: Path,
    target_count: int,
    timeout_s: int,
    log_fn=None,
    baseline_ids: Optional[Set[str]] = None,
) -> List[Path]:
    saved = []
    seen = set()
    mp3_entries = []

    def handle_response(resp) -> None:
        url = resp.url
        if url in seen:
            return
        if "studio-api.prod.suno.com/api/feed/v2" in url:
            try:
                data = resp.json()
            except Exception:
                return
            for entry in extract_mp3_entries(data):
                if entry["url"] not in {e["url"] for e in mp3_entries}:
                    mp3_entries.append(entry)
            return
        content_type = resp.headers.get("content-type", "")
        if ".mp3" not in url and not content_type.startswith("audio/"):
            return
        try:
            body = resp.body()
        except Exception:
            return
        seen.add(url)
        filename = Path(urllib.parse.urlparse(url).path).name or f"suno_{int(time.time())}.mp3"
        out_path = downloads_dir / filename
        try:
            out_path.write_bytes(body)
        except Exception:
            return
        saved.append(out_path)

    page.on("response", handle_response)

    deadline = time.time() + timeout_s
    last_log = 0
    last_ui_check = 0
    while time.time() < deadline and len(saved) < target_count:
        now = time.time()
        if log_fn and now - last_log >= 10:
            remaining = int(deadline - now)
            log_fn(f"Waiting for MP3... remaining {remaining}s, saved {len(saved)}/{target_count}")
            last_log = now
        if baseline_ids is not None and now - last_ui_check >= 10:
            current_ids = get_song_ids(page)
            new_ids = current_ids - baseline_ids
            if new_ids and log_fn:
                log_fn("UI shows new clip(s): " + ", ".join(sorted(new_ids)))
                baseline_ids.update(new_ids)
            last_ui_check = now
        if mp3_entries:
            for entry in list(mp3_entries):
                url = entry["url"]
                if url in seen:
                    continue
                out_path = download_mp3(url, downloads_dir, title=entry.get("title"))
                seen.add(url)
                if out_path:
                    saved.append(out_path)
        page.wait_for_timeout(1000)

    return saved


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate music from Suno Create page via Playwright.")
    parser.add_argument("--lyrics", required=False, default="", help="Lyrics or prompt text")
    parser.add_argument("--song-desc", required=False, default="", help="Song description text (Simple tab)")
    parser.add_argument("--sound-desc", required=False, default="", help="Sound description text")
    parser.add_argument("--count", type=int, default=2, help="Number of tracks to wait for")
    parser.add_argument("--downloads", default=str(Path.home() / "Downloads"), help="Download directory")
    parser.add_argument("--timeout", type=int, default=1800, help="Timeout seconds for generation")
    parser.add_argument("--connect-cdp", default="", help="CDP endpoint, e.g. http://127.0.0.1:9222")
    parser.add_argument("--user-data-dir", default=str(Path.home() / ".suno-playwright"), help="Persistent profile dir")
    parser.add_argument("--login-only", action="store_true", help="Open Create page for manual login then exit")
    parser.add_argument("--instrumental", action="store_true", help="Enable instrumental mode")
    parser.add_argument("--debug", action="store_true", help="Print diagnostics")

    args = parser.parse_args()
    downloads_dir = Path(args.downloads)
    downloads_dir.mkdir(parents=True, exist_ok=True)

    with sync_playwright() as p:
        if args.connect_cdp:
            ws_url = get_ws_url(args.connect_cdp)
            browser = p.chromium.connect_over_cdp(ws_url)
            context = browser.contexts[0] if browser.contexts else browser.new_context()
        else:
            context = p.chromium.launch_persistent_context(
                user_data_dir=args.user_data_dir,
                channel="chrome",
                headless=False,
            )

        page = None
        if args.connect_cdp:
            for pge in context.pages:
                if "suno.com/create" in (pge.url or ""):
                    page = pge
                    break
        if page is None:
            page = context.new_page()
            page.goto("https://suno.com/create", wait_until="load")
        else:
            page.bring_to_front()

        if args.login_only:
            log("Log in and solve any captcha, then press Enter here.")
            try:
                input()
            finally:
                if not args.connect_cdp:
                    context.close()
            return 0

        if args.debug:
            log(f"URL: {page.url}")
            visible_textareas = []
            ta = page.locator("textarea")
            for i in range(ta.count()):
                item = ta.nth(i)
                try:
                    if item.is_visible():
                        ph = item.get_attribute("placeholder") or ""
                        visible_textareas.append(ph)
                except Exception:
                    continue
            if visible_textareas:
                log("Visible textareas: " + " | ".join(visible_textareas))

        # Decide mode: Simple when song description is provided, otherwise Custom for lyrics/style.
        use_custom = not bool(args.song_desc)

        lyr_locator = page.locator("textarea[placeholder^='Write some lyrics or a prompt']")
        simple_desc_locator = page.locator("textarea[placeholder^='Meditative hyperpop song']")
        sound_desc_locator = page.locator("textarea[placeholder^='Describe the sound you want']")

        if use_custom:
            custom_btn = pick_visible(page.get_by_role("button", name="Custom"))
            if custom_btn:
                custom_btn.click()
                page.wait_for_timeout(500)

            # Ensure Lyrics tab is selected when available.
            if pick_visible(lyr_locator) is None:
                lyrics_btn = pick_visible(page.get_by_role("button", name="Lyrics"))
                if lyrics_btn:
                    lyrics_btn.click()
                    page.wait_for_timeout(500)
        else:
            simple_btn = pick_visible(page.get_by_role("button", name="Simple"))
            if simple_btn:
                simple_btn.click()
                page.wait_for_timeout(500)

        if args.instrumental:
            inst_button = page.get_by_role("button", name="Instrumental")
            try:
                if inst_button.count() > 0:
                    pressed = inst_button.first.get_attribute("aria-pressed")
                    if pressed != "true":
                        inst_button.first.click()
            except Exception:
                pass

        if args.song_desc:
            song = pick_visible(simple_desc_locator)
            if song:
                set_textarea_value(song, args.song_desc)
            else:
                if args.debug:
                    log("Song description textarea not visible in Simple mode.")
                # Fallback to any visible textarea in Simple mode.
                visible_textareas = []
                ta = page.locator("textarea")
                for i in range(ta.count()):
                    item = ta.nth(i)
                    try:
                        if item.is_visible():
                            visible_textareas.append(item)
                    except Exception:
                        continue
                if visible_textareas:
                    set_textarea_value(visible_textareas[0], args.song_desc)

        if args.lyrics and use_custom:
            lyr = pick_visible(lyr_locator)
            if lyr:
                lyr.fill(args.lyrics)
            elif args.debug:
                log("Lyrics textarea not visible.")

        if args.sound_desc and use_custom:
            snd = pick_visible(sound_desc_locator)
            if snd:
                snd.fill(args.sound_desc)
            else:
                # Fallback: in Custom mode, use the other visible textarea as style prompt.
                visible_textareas = []
                ta = page.locator("textarea")
                for i in range(ta.count()):
                    item = ta.nth(i)
                    try:
                        if item.is_visible():
                            visible_textareas.append(item)
                    except Exception:
                        continue
                style_target = None
                for item in visible_textareas:
                    try:
                        ph = (item.get_attribute("placeholder") or "").lower()
                    except Exception:
                        ph = ""
                    if not ph.startswith("write some lyrics"):
                        style_target = item
                        break
                if style_target:
                    style_target.fill(args.sound_desc)
                elif args.debug:
                    log("Sound/style textarea not visible.")

        create_button = page.get_by_role("button", name="Create song")
        if create_button.count() == 0:
            create_button = page.get_by_role("button", name="Create")
        btn = pick_visible(create_button)
        if btn:
            btn.scroll_into_view_if_needed()
            if args.debug:
                try:
                    log(f"Create enabled: {btn.is_enabled()} aria-disabled={btn.get_attribute('aria-disabled')}")
                except Exception:
                    pass
            if not btn.is_enabled():
                reason = detect_disabled_reason(page, use_custom)
                if reason == "out of credits":
                    log("Create is disabled: out of credits.")
                    log_error("Create is disabled: out of credits.")
                elif reason:
                    log(f"Create is disabled: {reason}.")
                    log_error(f"Create is disabled: {reason}.")
                else:
                    log("Create is disabled.")
                    log_error("Create is disabled.")
                if not args.connect_cdp:
                    context.close()
                return 3
            btn.click()
        else:
            log("Create button not found or not visible.")
            if not args.connect_cdp:
                context.close()
            return 2

        baseline_ids = get_song_ids(page)
        saved = wait_for_downloads(
            page,
            downloads_dir,
            args.count,
            args.timeout,
            log_fn=log if args.debug else None,
            baseline_ids=baseline_ids,
        )

        if not args.connect_cdp:
            context.close()

    if not saved:
        print("No MP3 files captured. The page may require manual captcha or UI may have changed.")
        return 2

    for path in saved:
        log(str(path))
    return 0


if __name__ == "__main__":
    sys.exit(main())
