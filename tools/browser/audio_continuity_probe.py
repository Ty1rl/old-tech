#!/usr/bin/env python3
"""Run repeatable Web Audio continuity probe against a local Web export."""
import argparse
import functools
import http.server
import json
from pathlib import Path
import socketserver
import sys
import threading
import time

for _cand in (Path.home() / 'game-jams/state/old-tech-jam-1/cache/web-tools',):
    if _cand.is_dir() and str(_cand) not in sys.path:
        sys.path.insert(0, str(_cand))

from playwright.sync_api import sync_playwright

BROWSER = Path.home() / '.cache/ms-playwright/chromium_headless_shell-1243/chrome-headless-shell-linux64/chrome-headless-shell'
PROBE = (Path(__file__).resolve().parent / 'audio_continuity_probe.js').read_text()


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map, '.wasm': 'application/wasm', '.pck': 'application/octet-stream'}
    isolated = False

    def end_headers(self):
        if self.isolated:
            self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
            self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
        super().end_headers()

    def log_message(self, *_args):
        pass


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True


def descendants(pid):
    seen, queue = set(), [pid]
    while queue:
        cur = queue.pop()
        if cur in seen:
            continue
        seen.add(cur)
        children = Path(f'/proc/{cur}/task/{cur}/children')
        if children.exists():
            queue.extend(int(x) for x in children.read_text().split() if x.isdigit())
    return seen


def rss_bytes(root_pid):
    total = 0
    for pid in descendants(root_pid):
        status = Path(f'/proc/{pid}/status')
        if status.exists():
            for line in status.read_text().splitlines():
                if line.startswith('VmRSS:'):
                    total += int(line.split()[1]) * 1024
    return total


def pick_game_frame(page):
    for frame in page.frames:
        try:
            if frame.locator('#canvas').count():
                return frame
        except Exception:
            pass
    return page.main_frame


def run_actions(page, frame, actions, out):
    box = frame.locator('#canvas').bounding_box() or {'x': 0, 'y': 0}
    for action in actions:
        if 'click' in action:
            x, y = action['click']
            page.mouse.click(box['x'] + x, box['y'] + y)
        if 'move' in action:
            x, y = action['move']
            page.mouse.move(box['x'] + x, box['y'] + y)
        if 'mouse_down' in action:
            page.mouse.down(button=action['mouse_down'])
        if 'mouse_up' in action:
            page.mouse.up(button=action['mouse_up'])
        if 'wheel' in action:
            dx, dy = action['wheel']
            page.mouse.wheel(dx, dy)
        if 'key' in action:
            page.keyboard.press(action['key'])
        if 'key_down' in action:
            page.keyboard.down(action['key_down'])
        if 'key_up' in action:
            page.keyboard.up(action['key_up'])
        if 'screenshot' in action:
            page.screenshot(path=str(out / f'{action["screenshot"]}.png'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dir', type=Path, required=True, help='Local directory containing exported index.html')
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--seconds', type=int, default=45)
    parser.add_argument('--max-rss-mb', type=int, default=1200)
    parser.add_argument('--isolate', action='store_true', help='Serve headers required by threaded Web exports')
    parser.add_argument('--actions', default='[{"at": 5, "click": [190, 450]}, {"at": 7, "click": [640, 470]}]')
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    actions = json.loads(args.actions if args.actions.lstrip().startswith('[') else Path(args.actions).read_text())
    Handler.isolated = args.isolate
    server = Server(('127.0.0.1', 0), functools.partial(Handler, directory=str(args.dir.resolve())))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    url = f'http://127.0.0.1:{server.server_port}/index.html'
    console, errors, samples = [], [], []
    failures = []
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(
                executable_path=str(BROWSER) if BROWSER.exists() else None,
                headless=True,
                args=['--disable-dev-shm-usage', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'],
            )
            context = browser.new_context(viewport={'width': 1280, 'height': 800})
            context.add_init_script(PROBE)
            page = context.new_page()
            page.on('console', lambda m: console.append({'type': m.type, 'text': m.text}))
            page.on('pageerror', lambda e: errors.append(str(e)))
            page.goto(url, wait_until='domcontentloaded', timeout=45000)
            control = browser.new_browser_cdp_session()
            processes = control.send('SystemInfo.getProcessInfo')['processInfo']
            root_pid = next((item['id'] for item in processes if item['type'] == 'browser'), None)
            began = time.monotonic()
            for sec in range(args.seconds):
                time.sleep(max(0, began + sec - time.monotonic()))
                frame = pick_game_frame(page)
                due = [a for a in actions if a.get('at') == sec]
                if due:
                    run_actions(page, frame, due, args.out)
                snap = frame.evaluate('window.__jamAudioProbe ? window.__jamAudioProbe.snapshot() : {}')
                sample = {'second': sec, 'browser_rss_bytes': rss_bytes(root_pid) if root_pid else 0, **snap}
                samples.append(sample)
                if sample['browser_rss_bytes'] > args.max_rss_mb * 1024 * 1024:
                    failures.append(f'browser RSS exceeded {args.max_rss_mb} MiB at {sec}s: {sample["browser_rss_bytes"]}')
                    break
            page.screenshot(path=str(args.out / 'final.png'))
            browser.close()
    finally:
        server.shutdown()

    bad_console = [c for c in console if c['type'] == 'error' or 'SCRIPT ERROR' in c['text'] or 'aborted(' in c['text']]
    if errors or bad_console:
        failures.append(f'{len(errors)} page errors and {len(bad_console)} console errors')
    last = samples[-1] if samples else {}
    if last.get('audiblePeak', 0) <= 0.0001:
        failures.append('no audible WebAudio signal observed')
    max_rss = max((s['browser_rss_bytes'] for s in samples), default=0)
    max_reg_bytes = max((s.get('registeredSampleBytes', 0) for s in samples), default=0)
    summary = {
        'status': 'failed' if failures else 'passed',
        'failures': failures,
        'errors': errors,
        'console_errors': bad_console[:10],
        'samples': len(samples),
        'max_browser_rss_bytes': max_rss,
        'max_registered_sample_bytes': max_reg_bytes,
        'stream_ring_buffer_frames': last.get('streamRingBufferFrames', 0),
        'stream_ring_buffer_ms': last.get('streamRingBufferMs', 0),
        'worklet_probe_installed': last.get('workletProbeInstalled', False),
        'stream_mode': last.get('streamMode', 'unknown'),
        'worklet_total_quanta': last.get('workletTotalQuanta', 0),
        'worklet_underflow_quanta': last.get('workletUnderflowQuanta', 0),
        'worklet_underflow_ms': last.get('workletUnderflowMs', 0),
        'audible_underflow_quanta': last.get('audibleUnderflowQuanta', 0),
        'audible_underflow_ms': last.get('audibleUnderflowMs', 0),
        'audible_underflow_events': last.get('audibleUnderflowEvents', 0),
        'max_audible_dropout_ms': last.get('maxAudibleDropoutMs', 0),
        'max_chunk_gap_ms': last.get('maxChunkGapMs', 0),
        'frame_stalls_over_50ms': last.get('frameStallsOver50Ms', 0),
        'frame_stalls_over_100ms': last.get('frameStallsOver100Ms', 0),
        'max_frame_gap_ms': last.get('maxFrameGapMs', 0),
        'sample_sources_created': last.get('created', 0),
        'sample_sources_started': last.get('starts', 0),
        'sample_sources_stopped': last.get('stops', 0),
        'sample_sources_ended': last.get('ended', 0),
        'active_sample_nodes_end': last.get('activeSampleNodes', 0),
        'registered_samples_end': last.get('registeredSamples', 0),
        'last': last,
        'renderer': 'Chromium headless / SwiftShader; not host GPU performance',
    }
    (args.out / 'samples.json').write_text(json.dumps(samples, indent=2) + '\n')
    (args.out / 'console.json').write_text(json.dumps(console, indent=2) + '\n')
    (args.out / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps(summary))
    raise SystemExit(0 if summary['status'] == 'passed' else 1)


if __name__ == '__main__':
    main()
