#!/usr/bin/env python3
"""Exercise an actual Web export with Chromium; save console, graph and RSS evidence."""
import argparse
import asyncio
import functools
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import threading
import time

from playwright.async_api import async_playwright


def resident_bytes(processes):
    total = 0
    for process in processes:
        try:
            for line in Path(f"/proc/{process['id']}/status").read_text().splitlines():
                if line.startswith("VmRSS:"):
                    total += int(line.split()[1]) * 1024
        except (OSError, KeyError):
            pass
    return total  # Sum of RSS includes shared pages; not unique memory or just JS heap.


async def run(args, url):
    args.output.mkdir(parents=True, exist_ok=True)
    console, samples, failures, requests = [], [], [], []
    actions = json.loads(args.actions.read_text()) if args.actions else []
    engine_seen = False
    async with async_playwright() as playwright:
        browser = await playwright.chromium.launch(executable_path=str(args.browser), headless=True,
            args=["--disable-dev-shm-usage", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"])
        try:
            control = await browser.new_browser_cdp_session()
            context = await browser.new_context(viewport={"width": 1280, "height": 800})
            page = await context.new_page()
            page.on("console", lambda message: console.append({"type": message.type, "text": message.text[:3000]}))
            page.on("pageerror", lambda error: console.append({"type": "exception", "text": str(error)[:3000]}))
            page.on("requestfailed", lambda request: console.append({"type": "network", "text": request.url, "failure": request.failure}))
            page.on("response", lambda response: requests.append({"url": response.url,
                "status": response.status, "encoding": response.headers.get("content-encoding"),
                "content_type": response.headers.get("content-type")}))
            page.on("crash", lambda _: failures.append("Browser renderer crashed"))
            await page.add_init_script(path=Path(__file__).with_name("audio_probe.js"))
            await page.goto(url, wait_until="domcontentloaded", timeout=30000)
            began = time.monotonic()
            for second in range(args.seconds):
                await asyncio.sleep(max(0, began + second - time.monotonic()))
                for action in actions:
                    if action["at"] != second:
                        continue
                    if "click" in action:
                        await page.mouse.click(*action["click"])
                    if "key" in action:
                        await page.keyboard.press(action["key"])
                    if "key_down" in action:
                        await page.keyboard.down(action["key_down"])
                    if "key_up" in action:
                        await page.keyboard.up(action["key_up"])
                    if "move" in action:
                        await page.mouse.move(*action["move"])
                    if "mouse_down" in action:
                        await page.mouse.down(button=action["mouse_down"])
                    if "mouse_up" in action:
                        await page.mouse.up(button=action["mouse_up"])
                    if "screenshot" in action:
                        await page.screenshot(path=args.output / (action["screenshot"] + ".png"))
                processes = (await control.send("SystemInfo.getProcessInfo"))["processInfo"]
                rss = resident_bytes(processes)
                if rss > args.memory_limit_mib * 1024 * 1024:
                    failures.append("Own browser exceeded RSS safety limit; stopped before host exhaustion")
                    break
                game_frame = page.main_frame
                for frame in page.frames:
                    if await frame.evaluate("typeof Engine !== 'undefined'"):
                        engine_seen = True
                        game_frame = frame
                        break
                audit = await asyncio.wait_for(game_frame.evaluate("window.__readWebAudit?.() || {}"), timeout=8)
                audit["game_frame"] = game_frame.url
                samples.append({"second": second, "browser_rss_bytes": rss, **audit})
                with (args.output / "samples.jsonl").open("a") as handle:
                    handle.write(json.dumps(samples[-1]) + "\n")
                if second in [5, 15, args.seconds - 1]:
                    await page.screenshot(path=args.output / f"second-{second}.png")
                if failures:
                    break
            await page.screenshot(path=args.output / "final.png")
        except Exception as error:
            failures.append(f"{type(error).__name__}: {error}")
        finally:
            try:
                await asyncio.wait_for(browser.close(), timeout=10)
            except Exception as error:
                failures.append(f"Browser close: {error}")
    if not engine_seen:
        failures.append("No Godot frame observed; the page may be blocked or failed to load")
    if args.require_audio and not any(row.get("audiblePeak", 0) > .0001 for row in samples):
        failures.append("No non-silent browser audio output observed")
    errors = [line for line in console if line["type"] in ["error", "exception"]]
    result = {"status": "failed" if failures or errors else "passed", "url": url,
              "failures": failures, "errors": errors[:12], "samples": len(samples),
              "first": samples[0] if samples else {}, "last": samples[-1] if samples else {},
              "max_browser_rss_bytes": max((row["browser_rss_bytes"] for row in samples), default=0),
              "renderer": "Chromium headless / SwiftShader; not host GPU performance",
              "memory_note": "Sum of browser-process RSS, including shared pages; separate from JS heap."}
    (args.output / "console.json").write_text(json.dumps(console, indent=2) + "\n")
    (args.output / "samples.json").write_text(json.dumps(samples, indent=2) + "\n")
    (args.output / "requests.json").write_text(json.dumps(requests, indent=2) + "\n")
    (args.output / "summary.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    location = parser.add_mutually_exclusive_group(required=True)
    location.add_argument("--build", type=Path)
    location.add_argument("--url")
    parser.add_argument("--browser", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--actions", type=Path, help="JSON list: at seconds, click [x,y], key, screenshot name")
    parser.add_argument("--seconds", type=int, default=45)
    parser.add_argument("--memory-limit-mib", type=int, default=1200)
    parser.add_argument("--require-audio", action="store_true")
    args = parser.parse_args()
    if not 1 <= args.seconds <= 300:
        parser.error("Use a bounded duration of1..300 seconds")
    server = None
    if args.build:
        class QuietHandler(SimpleHTTPRequestHandler):
            def log_message(self, *_):
                pass
        handler = functools.partial(QuietHandler, directory=str(args.build.resolve()))
        server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        url = f"http://127.0.0.1:{server.server_port}/index.html"
    else:
        url = args.url
    try:
        asyncio.run(asyncio.wait_for(run(args, url), timeout=args.seconds + 60))
    finally:
        if server:
            server.shutdown()


if __name__ == "__main__":
    main()
