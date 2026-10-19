#!/usr/bin/env python3
"""Make smaller game MP3s from archived originals, without normalizing their gain."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "audio/encoding.json"
SETTINGS = {"voice": ["-ac", "1", "-ar", "32000", "-b:a", "64k"],
            "effects": ["-ac", "1", "-ar", "44100", "-b:a", "96k"],
            "music": ["-ac", "2", "-ar", "44100", "-b:a", "128k"]}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ffmpeg", default="ffmpeg")
    parser.add_argument("--originals", type=Path, required=True,
                        help="Archive outside the repository; never added to exports")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    if args.originals.resolve().is_relative_to(ROOT):
        parser.error("Keep original archives outside the repository")
    old = json.loads(MANIFEST.read_text()).get("files", {}) if MANIFEST.exists() else {}
    rows = {}
    for folder, group in [("audio/voice", "voice"), ("audio/combat/supplied", "effects"),
                          ("audio/music", "music")]:
        for path in sorted((ROOT / folder).rglob("*.mp3")):
            name = path.relative_to(ROOT).as_posix()
            previous = old.get(name, {})
            current = digest(path)
            if previous.get("encoded_sha256") == current:
                rows[name] = previous
                continue  # Never re-encode an already-derived asset.
            row = {"source_sha256": current, "source_bytes": path.stat().st_size,
                   "settings": SETTINGS[group]}
            if not args.apply:
                rows[name] = row
                continue
            args.originals.mkdir(parents=True, exist_ok=True)
            original = args.originals / (current + ".mp3")
            if not original.exists():
                shutil.copy2(path, original)
            if digest(original) != current:
                raise RuntimeError("Original archive verification failed: " + name)
            with tempfile.TemporaryDirectory() as tmp:
                encoded = Path(tmp) / "encoded.mp3"
                subprocess.run([args.ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
                                "-i", str(original), "-map_metadata", "-1", "-vn",
                                "-c:a", "libmp3lame", *SETTINGS[group], str(encoded)], check=True)
                if encoded.stat().st_size < path.stat().st_size:
                    shutil.copy2(encoded, path)
            row.update(encoded_sha256=digest(path), encoded_bytes=path.stat().st_size)
            rows[name] = row
    if args.apply:
        MANIFEST.write_text(json.dumps({"description": "Derived game MP3s; original uploads remain in shared audio and Git history. No gain normalization.",
                                       "files": rows}, indent=2) + "\n")
        music_manifest = ROOT / "audio/music/supplied-round-r.json"
        provenance = json.loads(music_manifest.read_text())
        provenance["provenance"] = "Music supplied by Matt. Game copies compressed; original upload digests and encoding parameters recorded in audio/encoding.json."
        for track in provenance["tracks"]:
            row = rows[track["asset"]]
            track["original_sha256"] = row["source_sha256"]
            track["sha256"], track["bytes"] = row["encoded_sha256"], row["encoded_bytes"]
        music_manifest.write_text(json.dumps(provenance, indent=2) + "\n")
    print(json.dumps({"applied": args.apply, "files": len(rows),
                      "before_bytes": sum(r["source_bytes"] for r in rows.values()),
                      "after_bytes": sum(r.get("encoded_bytes", r["source_bytes"]) for r in rows.values())}))


if __name__ == "__main__":
    main()
