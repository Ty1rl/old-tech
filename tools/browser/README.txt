Web verification

Use Godot4.7.2 Standard with matching Web export templates. Import in one editor
invocation, then export-release Web to index.html in a separate invocation. Check
both full logs for SCRIPT ERROR/ERROR even if Godot returns exit0. Keep every
generated file together;do not rename only index.html after export.

web_smoke.py runs the actual HTML/WASM/PCK in Chromium. It serves a build on a
temporary loopback port,or visits --url (including iframe-hosted itch pages).
It saves console/network records,screenshots,audio-source counts,output signal,
frame gaps and summed browser-process RSS. Browser/server close after the run.
No host desktop window or X11 connection is used. Headless SwiftShader timing is
not host GPU performance. RSS includes shared pages;it is not unique memory.

Install requirements.txt into a disposable seat-specific environment. Reuse an
existing Playwright Chromium/headless-shell executable with --browser;no second
browser download is needed. Example,with requirements available to Python:

python3 tools/browser/web_smoke.py --build /path/to/export --browser /path/to/chrome-headless-shell --output /path/to/seat-state/browser-check --seconds 65 --actions /path/to/actions.json --require-audio

Replace --build with --url https://your-account.itch.io/your-game for hosting
checks. A private/password-protected page must be accessible to the test browser;
do not put account passwords in this repo. A blocked/non-Godot page fails.

Actions are viewport pixel coordinates in JSON,for example:
[{"at":5,"click":[190,430]},{"at":7,"click":[640,520]},{"at":28,"key_down":"w"},{"at":36,"key_up":"w"},{"at":52,"screenshot":"practice"}]

Also supports key,move,mouse_down,mouse_up. Coordinates above target1280x800 local
export;inspect screenshots before reusing on a smaller itch iframe. Include a user
click to exercise real browser audio activation. No autoplay-policy bypass is used.
Use --require-audio when the scenario should make sound;the analyser verifies a
non-silent output signal,not subjective mix quality. Default RSS guard1200MiB can
be adjusted explicitly for known test conditions;stop growth before host shortage.

This is a smoke/measurement harness,not proof of full game completion. Pair it
with campaign/rewind/repair native checks and human playtests. It reports errors
instead of masking them. Detailed initial evidence and ready-to-upload build are
under jam-1 state/exports/web-audit,not in the game package.
