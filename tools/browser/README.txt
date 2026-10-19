Web exports and audio

Prefer the Web Threaded export preset. It marks the build web_threaded and runs
speech,effects and music through Godot's Stream mixer. The100ms requested audio
buffer produced a92.88ms ring in the verified Chromium export. A50ms request
underran during stressed software rendering;the100ms comparison did not. This
is a tested configuration,not a guarantee against all audible artifacts.

On itch.io enable Embed options > Frame options > SharedArrayBuffer support.
Keep Click to Play enabled. Local threaded hosting requires COOP:same-origin
and COEP:require-corp response headers. Upload the complete ZIP,index.html at root.
The legacy Web preset works without isolation and retains Sample speech/effects;
its music still streams. It is a separate fallback,not a threaded comparison made
by turning the hosting checkbox off.

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
The bounded frame probe also records per-sampling-window frame-time median,
95th percentile and maximum,plus cumulative browser long-task counts. These
measure main-thread/browser frame stalls,not subjective audio continuity or GPU time.

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

Use whole seconds for at. Common key aliases such as space/escape are normalized.
Held mouse input uses {"move":[640,270]}, then {"mouse_down":"left"} and
{"mouse_up":"left"}. Malformed schedules/buttons fail before browser launch.

Audio continuity and output capture

python3 tools/browser/audio_continuity_probe.py --dir /path/to/export --out /path/to/seat-state/audio-check --seconds 45 --isolate --capture-audio --actions /path/to/actions.json

--isolate serves the required threaded headers. The optional capture records the
summed stereo output into audio.f32 (little-endian float32) and audio-capture.json
(sample rate/frame count). It records application output,not a microphone.
Read summary.json for actual buffer size,backend,underruns and Sample allocations.
Inspect reported underruns even when the script exits successfully. Float capture
can check clipping;sample discontinuities alone do not prove an audible click.
A non-silent recording and zero reported underruns still need human listening.
