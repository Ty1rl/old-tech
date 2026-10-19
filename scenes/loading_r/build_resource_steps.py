#!/usr/bin/env python3
"""Regenerate optional startup hints; never load scenes or alter their contents."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
classes = {}
for base in ('scenes', 'scripts'):
    for path in sorted((ROOT / base).rglob('*.gd')):
        if 'checks' in path.parts:
            continue
        match = re.search(r'^class_name\s+(\w+)', path.read_text(), re.M)
        if match:
            classes[match[1]] = path.relative_to(ROOT).as_posix()

seen, visiting, steps = set(), set(), []

def visit(resource):
    relative = resource.removeprefix('res://')
    path = ROOT / relative
    if relative in seen or relative in visiting or not path.is_file():
        return  # Ordinary root loading resolves cycles; these are timing hints.
    visiting.add(relative)
    dependencies = []
    if path.suffix in ('.tscn', '.tres'):
        dependencies = re.findall(r'\bpath="(res://[^\"]+)"', path.read_text())
    elif path.suffix == '.gd':
        source = path.read_text()
        dependencies = re.findall(r'''(?:preload\(\s*|extends\s+)["'](res://[^"']+)["']''', source)
        for name, target in classes.items():
            if target != relative and re.search(r'\b' + name + r'\b', source):
                dependencies.append('res://' + target)
    for dependency in dependencies:
        visit(dependency)
    visiting.remove(relative)
    seen.add(relative)
    steps.append('res://' + relative)

visit('res://scenes/prototype/campaign.tscn')
header = ('extends RefCounted\n'
          '## Generated optional startup hints; run build_resource_steps.py after dependency changes.\n'
          '## Ordinary root loading still resolves the actual graph. No gameplay authority.\n'
          'const STEPS: Array[String] = [\n')
(Path(__file__).parent / 'resource_steps.gd').write_text(
    header + ''.join('\t"' + path + '",\n' for path in steps) + ']\n')
print(f'Wrote {len(steps)} startup hints')
