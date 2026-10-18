ROUND M — CLEAR SPACE / ENEMY PARTS / ROOM FOOTPRINTS

Branch: seats/jam-5/round-m; base 7b02642.

flow.gd now reserves the complete silhouette and a cutter-width drawing margin,
not just the controller's body radius. Pattern extents derive from the existing
PatternVisual.spans anchors and the visible support pod half-diagonal. All future
final-boss phases are reserved at arrival. Walls, cover, the player and occupied
units all participate. This changes placement, never authoritative hit anchors.

Candidates keep their preferred entrance and formation; try alternate distances
before another entrance. Large patterns prefer positions where their full shape
and labels fit the normal 52-degree gameplay perspective. A bounded per-member
room-grid fallback prevents a blocked formation from retrying forever. Fallback
preserves the finite roster prefix. Cohort bounds, warnings and rewind format stay
unchanged. Existing room cover is retained in full.

A clear cutter launch corridor is also required. This was the main correction
from the first revised private views: the support ring was clear but an intervening
cabinet could block the initial flight. Real cutter launches, not just radius
checks, verify loop/zigzag/loop-boss/final-boss loops in every room. The last camera
review also caught a low rear spawn clipping an outer support, hence the view
preference. Geometry safety remains mandatory even when the view preference needs
to yield to a genuinely crowded room.

Borrowed Heart now loses its disconnected Companion AND ConduitCouplings on a
cable cut. Its whole companion returns on rewind. Existing conjoined B_* removal
is preserved. A committed enemy attack holds the legs rather than running in place.
Yellow accents remain on current query positions from every facing; orange and
its rims/pods disappear fully when removed. No Blender/export/anchor change.

Pattern primitive meshes/materials are shared across instances and phase rebuilds.
No per-frame material mutation is needed for valve depth policy. Tests check shared
resource identity and 600 sync/pose ticks without new geometry/material/node entries.
Room cover gets quiet neutral floor edging to clarify solid footprints; its original
cover and collider rectangles remain authoritative.

Focused checks via project check.py --seat jam-5 --suite:
  space_m          four rooms / 16 seeds / four player positions / seven rosters;
                   occupied silhouettes, off-formation fallback, future boss phases
  space_weapons_m  actual raw cutter strokes plus outbound flight in all four rooms
  visual_m         split/rewind, anchors, orange removal, commit pose, shared resources
Existing flow_k, rooms, art_integration and patterns are regression checks.

Private review only (no desktop connection):
  python3 ~/game-jams/projects/old-tech/render.py --seat jam-5 \
    --script res://scenes/space_preview_m/capture.gd --name round-m-after --timeout 60
capture-pass.txt in the seat's exports/round-m selects the filename prefix; default
is before. Recorded baseline before-*.png precedes production changes. after-*.png
shows the same room seeds, part removal/rewind, four yellow facings and an actual
world-time approach sequence. Logs and verification.json live in that directory.

Integration: no campaign/director/controller/tuning/player/HUD files changed.
Native AI still owns movement after arrival. If later moving large enemies need
wider cover detours, jam-6 can use Flow.placement_radius(kind) for those detours;
this assignment establishes safe initial practice/boss/formation placement.
The view preference reflects normal gameplay distance; user zoom/aspect changes
remain camera-owned. No node/camera/resource references enter rewind state.
