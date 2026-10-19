#!/usr/bin/env python3
"""Focused Round T generation/provenance and unchanged-audio guard."""
import csv
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
BASE = '62054670ea89f93adf309727051cdcb5dd0bd485'
checks, failures = 0, []


def expect(ok, message):
    global checks
    checks += 1
    if not ok:
        failures.append(message)


def original(path):
    return subprocess.check_output(['git', 'show', f'{BASE}:{path}'], cwd=ROOT)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


rows = json.loads((ROOT / 'audio/voice/supplied-round-t.json').read_text())['tracks']
manifest = json.loads((ROOT / 'audio/encoding.json').read_text())['files']
before = json.loads(original('audio/encoding.json'))['files']
targets = {row['game_asset'] for row in rows}
expect(len(rows) == 3 and len(manifest) == len(before) + 2, 'Two additions, one replacement')
with (ROOT / 'audio/voice/EVENTS.tsv').open() as f:
    events = list(csv.DictReader(f, delimiter='\t'))
expect(len(events) == 40, 'Event inventory includes two additions')
for row in rows:
    asset = ROOT / row['game_asset']
    expect(sha(asset) == row['encoded_sha256'] and asset.stat().st_size == row['encoded_bytes'], 'Encoded game bytes: ' + row['event'])
    expect(row['encoded_bytes'] < row['source_bytes'] and row['encoded_sha256'] != row['source_sha256'], 'Compressed generation identified: ' + row['event'])
    expect(row['settings'] == ['-ac', '1', '-ar', '32000', '-b:a', '64k'], 'Voice encoding convention: ' + row['event'])
    expect(manifest[row['game_asset']]['source_sha256'] == row['source_sha256'], 'Manifest retains original upload hash: ' + row['event'])
    event = next(e for e in events if e['event_id'] == row['event'])
    expect(event['transcript'] == row['transcript'] and event['file'] == 'tutorial/' + asset.name, 'Exact event/transcript mapping: ' + row['event'])
    if row['event'] == 'tutorial.rewind':
        expect(row['previous_generation'] == before[row['game_asset']], 'Previous rewind generation preserved')
        expect(row['previous_event']['original_upload'] == 'tutorial/Emergency rewind.mp3', 'Previous upload trail retained')
for path, row in before.items():
    if path in targets:
        continue
    expect(manifest[path] == row and sha(ROOT / path) == row['encoded_sha256'], 'Other game audio not reencoded: ' + path)
for path in ['scripts/audio/dialogue_manager.tscn', 'scripts/autoloads/audio_manager.gd', 'default_bus_layout.tres', 'export_presets.cfg']:
    expect((ROOT / path).read_bytes() == original(path), 'Stream/pause/bus/export policy unchanged: ' + path)
print(json.dumps({'status': 'failed' if failures else 'passed', 'checks': checks, 'failures': failures,
                  'source_bytes': sum(r['source_bytes'] for r in rows), 'encoded_bytes': sum(r['encoded_bytes'] for r in rows)}))
raise SystemExit(bool(failures))
