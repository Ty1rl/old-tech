BORROWED HEART — JAM-7 / ROUND J

One side_guard visual, based on the bottom-right figure in the shared
creature-lineup-concept.png. Source and generator are editable in Blender 4.3.2.
The small crawler is part of the same model and rig, with no independent AI.
Runtime arena/combat scripts are not part of this delivery. Jam-1 integrates it.

Deliverables
  borrowed_heart.blend: authored mesh, 22-bone rig, three baked NLA clips.
  build_borrowed_heart.py: deterministic rebuild, final pass by default.
  assets/enemies/borrowed_heart/borrowed_heart.glb: explicit skinned export.
  borrowed_heart.glb.import: Godot import settings, looping Idle and Walk.
  scenes/enemy_preview/borrowed_heart/: bounded private capture and asset checks.

Rebuild and preview from this seat checkout:
  python3 ../../../blender.py --seat jam-7 \
    --script "$PWD/art-source/enemies/borrowed_heart/build_borrowed_heart.py" \
    --name borrowed-heart-final --timeout 180
  python3 ../../../check.py --seat jam-7 --suite import
  python3 ../../../render.py --seat jam-7 \
    --script res://scenes/enemy_preview/borrowed_heart/capture.gd \
    --name borrowed-heart-final

Model contract
  Metres, floor at Y=0. Root at the humanoid's ground centre.
  Export: +Y up, -Z forward. Source: +Z up, -Y forward.
  The BorrowedHeart root's 180-degree yaw is intentional; do not discard it.
  Humanoid 2.575m tall. Companion stays on exported +X (humanoid's left).
  No root travel; clips are sampled in world time by the future integration.
  Idle 2s / Walk 1s loop; Flinch 0.6s one-shot. No IK or runtime solver.
  Skinning uses rigid sections at overlapping joints; fingers are not animated.
  Foot sliding remains possible during in-place playback.

Six mesh nodes, each a separately addressable visual role:
  Body              wrapped lean humanoid and its braces/harness
  Companion         wrapped pressure sac, head and four crawling limbs
  ConduitCouplings  fixed metal collars, flange studs and belt-mounted hip brace
  CutConduit        blue lateral hose including its ribs; hide on cable_cut
  HeatCover         orange plate AND shutter; hide when core becomes exposed
  CoreTarget        yellow lens and dark mounting ring; hide when core_broken

Default GLB is physically closed; orange shutter occludes the yellow lens.
For exposed state, hide HeatCover. For a cut, also hide CutConduit.
The core lens was moved forward of the chest surface after the first final
preview revealed torso occlusion. Triangle-ray checks verify both states.
There is no collision geometry, new part hitbox, or companion controller.

Root sockets (Godot local metres):
  CoreSocket       (0, 1.75, 0)
  ConduitStart     (0.15, 0.85, 0)
  ConduitEnd       (1.15, 0.85, 0)
  CoverSocket      (0, 1.75, -0.25)
  CompanionSocket  (1.57, 0.55, 0.08)
Core and conduit match existing side_guard queries in part_visual.gd.
The visible yellow lens projects 0.175m forward of CoreSocket, inside the
existing 0.38m target tolerance. Sockets are static root references, not bones.
Chest breath/tilt and gait are deliberately small. The conduit remains on root
so the cut line does not wander when a walk cycle is sampled.

Art passes
  1: lean humanoid, closed chest, side hose, crawler, rig and clips.
  2: tighter head wraps, forearm wraps, thicker/ribbed hose, crawler/back braces;
     corrected authoring color space and balanced the preview lighting.
  3: plate wear, visible ribs, clasps/flange studs and hip support. Final export
     corrections expose the lens cleanly and use orange rather than red paint.

Evidence lives in JAM_STATE_ROOT/exports/round-j/verification.json, full logs,
close/front/back, walking, closed/exposed, and actual ortho22/-55 1280x800 views.
Preview captures are a neutral art stage, not an arena integration/playtest.
