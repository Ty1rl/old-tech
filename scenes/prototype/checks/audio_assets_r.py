#!/usr/bin/env python3
"""Round R provenance/gain checks against the delegated base; never bakes audio."""
import ast
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[3]
BASE = "25cf66fbb0438d3f77b3fed14e7780278412c563"
checks, failures = 0, []


def expect(ok, message):
    global checks
    checks += 1
    if not ok:
        failures.append(message)


def original(path):
    return subprocess.check_output(["git", "show", f"{BASE}:{path}"], cwd=ROOT)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def cues(text):
    result = {}
    for block in text.split("[sub_resource")[1:]:
        name = re.search(r'\nid = &"([^"]+)"', block).group(1)
        gain = re.search(r'\nvolume_db = ([-.\d]+)', block)
        # Resource footer is outside the cue's property block.
        properties = block.split("[resource]")[0].strip()
        result[name] = (float(gain.group(1)), re.sub(r'\nvolume_db = [-.\d]+', '', properties))
    return result


provenance = json.loads((ROOT / "audio/music/supplied-round-r.json").read_text())
digests = []
for track in provenance["tracks"]:
    data = (ROOT / track["asset"]).read_bytes()
    expect(sha(data) == track["sha256"] and len(data) == track["bytes"], "Music manifest matches: " + track["context"])
    expect(data == Path(track["source"]).read_bytes(), "Music supplied bytes unchanged: " + track["context"])
    digests.append(sha(data))
expect(len(set(digests)) == 4, "Four distinct source tracks")
voices = sorted((ROOT / "audio/voice").rglob("*.mp3"))
expect(len(voices) == 37, "37 supplied voice recordings retained")
for path in voices:
    relative = path.relative_to(ROOT).as_posix()
    expect(sha(path.read_bytes()) == sha(original(relative)), "Voice bytes unchanged: " + relative)
expect((ROOT / "audio/voice/library.tres").read_bytes() == original("audio/voice/library.tres"), "Voice event resource unchanged")

before = cues(original("audio/combat/palette.tres").decode())
after = cues((ROOT / "audio/combat/palette.tres").read_text())
expect(before.keys() == after.keys() and len(after) == 99, "All 99 semantic effects retained")
boosts = []
for name, (gain, properties) in after.items():
    old_gain, old_properties = before[name]
    expect(gain == min(-6, old_gain + 6), "Raised gain with headroom cap: " + name)
    expect(properties == old_properties, "Cue stream/pitch/priority/timing unchanged: " + name)
    boosts.append(gain - old_gain)
changed_audio = subprocess.check_output(["git", "diff", "--name-only", BASE, "--", "audio/voice", "audio/combat"], cwd=ROOT).decode().splitlines()
expect(changed_audio == ["audio/combat/palette.tres"], "Only combat metadata changed; no effect/voice source asset or import changes")
expect("glow.ogg" not in (ROOT / "audio/combat/palette.tres").read_text(), "Old music bed removed from live bank")
expect((ROOT / "default_bus_layout.tres").read_bytes() == original("default_bus_layout.tres"), "Voice/Master/World bus layout unchanged")
ast.parse((ROOT / "tools/audio/bake_palette.py").read_text())
expect(True, "Offline baker parses without running a generation pass")
print(json.dumps({"status": "failed" if failures else "passed", "checks": checks, "failures": failures,
                  "music_files": 4, "unchanged_voice_mp3s": len(voices), "cue_count": len(after),
                  "effect_boost_db": {"min": min(boosts), "max": max(boosts)},
                  "note": "Signal/provenance checks; no subjective listening claim."}))
raise SystemExit(bool(failures))
