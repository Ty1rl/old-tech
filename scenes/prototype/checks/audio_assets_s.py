#!/usr/bin/env python3
"""Round S source provenance, one-generation compression, and ownership checks."""
import csv
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
BASE = 'e84a1d8549e4254ee35db69830bd75384aa9337a'
checks, failures = 0, []


def expect(ok, message):
    global checks
    checks += 1
    if not ok:
        failures.append(message)


def original(path):
    return subprocess.check_output(['git', 'show', f'{BASE}:{path}'], cwd=ROOT)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


manifest = json.loads((ROOT / 'audio/encoding.json').read_text())['files']
previous = json.loads(original('audio/encoding.json'))['files']
provenance = json.loads((ROOT / 'audio/voice/supplied-round-s.json').read_text())
targets = {row['game_asset'] for row in provenance['tracks']}
expect(len(targets) == 3, 'Exactly three Round S uploads consumed')
for row in provenance['tracks']:
    source, asset = Path(row['source']), ROOT / row['game_asset']
    expect(digest(source) == row['source_sha256'] and source.stat().st_size == row['source_bytes'], 'Original upload bytes: ' + source.name)
    expect(digest(asset) == row['encoded_sha256'] and asset.stat().st_size == row['encoded_bytes'], 'Derived game bytes: ' + asset.name)
    expect(row['settings'] == ['-ac', '1', '-ar', '32000', '-b:a', '64k'], 'Voice compression settings: ' + asset.name)
    expect(row['encoded_bytes'] < row['source_bytes'], 'Compressed size: ' + asset.name)
    expect(manifest[row['game_asset']]['source_sha256'] == digest(source), 'Encoded from original, not previous derivative: ' + asset.name)
    expect(row['source_sha256'] != row['encoded_sha256'], 'Source and game generations identified: ' + asset.name)
for path, row in manifest.items():
    expect(digest(ROOT / path) == row['encoded_sha256'], 'Manifest matches runtime file: ' + path)
    if path not in targets:
        expect(row == previous[path], 'Unrelated audio was not recompressed: ' + path)
expect(len(manifest) == len(previous) + 1, 'One added recording; two replacements')
with (ROOT / 'audio/voice/EVENTS.tsv').open() as handle:
    events = list(csv.DictReader(handle, delimiter='\t'))
expect(len(events) == 38, 'Every recording has one event row')
for row in events:
    expect((ROOT / 'audio/voice' / row['file']).is_file(), 'Event file exists: ' + row['event_id'])
confirmed = {row['event_id']: row['transcript'] for row in events if row['transcript']}
expect(confirmed == {
    'narration.intro': 'An ancient device has turned exhibits into monsters. Survive with cobbled-together old tech and time borrowed from your future self.',
    'tutorial.time_meter': 'Taking damage, slowing time, and repairing drain your reserve. Find moments to let it recharge.',
    'tutorial.pickup': 'Walk towards the new item.'}, 'Exact supplier-confirmed transcripts only')
protagonist = [row for row in events if row['event_id'].startswith('protagonist.')]
expect(len(protagonist) == 16 and len({row['event_id'] for row in protagonist}) == 8, 'All protagonist recordings inventoried')
for path in ['default_bus_layout.tres', 'scripts/audio/dialogue_manager.tscn', 'audio/combat/palette.tres', 'audio/music/contexts.tres']:
    expect((ROOT / path).read_bytes() == original(path), 'Bus/stream/SFX/shared music gain unchanged: ' + path)
manager = (ROOT / 'scripts/autoloads/audio_manager.gd').read_text()
expect('if voice.stream_paused != paused:' in manager and 'if music.stream_paused != pause_music:' in manager, 'Web transition-only pause guards preserved')
expect('if not music.can_process(): return' in manager, 'Paused music cannot be restarted per frame')
expect(not subprocess.check_output(['git', 'diff', BASE, '--', 'scenes/prototype/campaign.gd', 'scenes/ui', 'scenes/prototype/arena.gd'], cwd=ROOT), 'Gameplay/tutorial/UI owners untouched')
print(json.dumps({'status': 'failed' if failures else 'passed', 'checks': checks, 'failures': failures,
                  'source_files': 3, 'voice_recordings': 38, 'protagonist_recordings': 16,
                  'runtime_voice_bytes': sum(p.stat().st_size for p in (ROOT / 'audio/voice').rglob('*.mp3'))}))
raise SystemExit(bool(failures))
