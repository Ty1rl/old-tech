#!/usr/bin/env python3
"""Compose signed JAM-6 audio under own disposable state; no shared source edits."""
import hashlib
import json
from pathlib import Path
import subprocess

SOURCE = Path('/home/mattlongname/game-jams/projects/old-tech/seats/jam-6/repo')
COMMIT = 'e3d2d0cae735fe48475ecb9750feb537917e73f2'
OUT = Path('/home/mattlongname/game-jams/state/old-tech-jam-7/exports/round-r')
OUT.mkdir(parents=True, exist_ok=True)
files = ['scripts/autoloads/audio_manager.gd', 'scripts/audio/combat_audio_library.gd']
files += ['audio/music/' + name + '.mp3' for name in ['menu', 'regular_combat', 'boss', 'victory']]
record = {'source_commit': COMMIT, 'source_repo': str(SOURCE), 'files': {}, 'patches': [
    'AudioManager export initializer/type replaced by a dynamically injected real library, because the base project has no music_tracks schema or imported context resource.',
    'Library class_name removed only in disposable copy to avoid collision with base global type.',
    'All AudioManager function bodies remain byte-identical to signed JAM-6 source; supplied MP3 bytes copied unchanged.',
]}
for name in files:
    data = subprocess.check_output(['git', '-C', str(SOURCE), 'show', COMMIT + ':' + name])
    record['files'][name] = {'sha256': hashlib.sha256(data).hexdigest()}
    if name.endswith('audio_manager.gd'):
        old = b'@export var music_library: CombatAudioLibrary = preload("res://audio/music/contexts.tres")'
        assert data.count(old) == 1
        data = data.replace(old, b'var music_library: Variant')
        target = OUT / 'delivered_audio_manager.gd'
    elif name.endswith('.gd'):
        data = data.replace(b'class_name CombatAudioLibrary\n', b'', 1)
        target = OUT / 'delivered_audio_library.gd'
    else:
        target = OUT / Path(name).name
    target.write_bytes(data)
    record['files'][name].update(disposable=str(target), disposable_sha256=hashlib.sha256(data).hexdigest())
(OUT / 'audio-composition.json').write_text(json.dumps(record, indent=2) + '\n')
print(json.dumps({'status': 'prepared', 'source_commit': COMMIT, 'files': len(files)}))
