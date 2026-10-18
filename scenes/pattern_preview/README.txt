ROUND K — PATTERN ENEMIES

Manual standalone trial:
  godot --path . res://scenes/pattern_preview/main.tscn

F1 loop / F2 zigzag / F3 pair / F4 final boss; R restart/refill.
WASD move; 1 cutter, 2 yellow flash, 3 heat. Space slows world time.
F hold freezes world/actions; P toggles pause. V saves enemy; B restores it.
Click/drag blue spans in one cutter launch. Draw a loop around all four
supports; zigzag through the three staggered links. Partials reconnect
3 WORLD seconds after the first cut. A new launch starts a fresh pattern.
Completed blue openings stay open. One fully charged aimed yellow shot kills.
Twin Valve: quick A, then quick B within 2.4 WORLD seconds finishes the unit.
Wrong or late shots reset only shutters. All tools still deal reduced body
hits; heat permanently strips orange and improves ordinary damage.
Boss: pair -> zigzag -> loop -> final core. Complete each pattern then shoot
the central core with >=85% charge. Ordinary damage also removes phases.
The upper yoke, side columns and rear outriggers visibly disappear in turn.
Attack rhythm: approach, 0.8s warning, 0.18s commit, 1.9s recovery (world time).

INTEGRATION CONTRACT (jam-1)

PatternEnemy extends enemy.gd; static handles(kind) accepts pair, loop,
zigzag, final_boss. Route those IDs to this script in spawn AND snapshot
reconstruction. The director is deliberately unchanged on this seat.
configure(kind, spawn_pos, stable_id) and all existing Enemy methods remain.
No changes to player, arena, history, weapons, existing models, or enemy.gd.

receive_attack preserves dealt/armored/killed/connected/cue. New short cues:
link_cut, pattern_open, valve_b, shutters_reset, armor_removed, phase_removed,
core_break. Existing weapons' combat_event continues to supply ordinary hit
cues; these additional semantic strings need no new audio framework.

Ring: continue inspecting every segment while has_cuttable_part() is true.
already_hit=false marks the first connected segment of a new launch; true
permits further mechanism cuts with zero additional body damage. This is the
baseline weapon contract, exercised by pattern_weapons.gd using real launches.
Max four links; per-launch link masks and world windows serialize in snapshots.

cable_world_points() returns FLAT PAIRS [a0,b0,a1,b1,...], matching the physical
blue rods; no cable exists between b0 and a1. receive_attack tests exact pairs.
The standalone preview applies cursor assist to each pair. The baseline
shared aim_assist.gd only projects its first/last anchor: update that helper
when integrating multi-span enemies (owned by coordinator, untouched here).
For legacy enemies keep its existing single cable behavior. Exclude hidden
cut links from assistance using link_mask if desired. Hit geometry already
excludes phantom spans; querying all anchors permits rewind/teaching overlays.

is_core_exposed() includes the currently open A/B valve. core_world_position()
returns active A or B until the pair completes, then central finisher target.
lesson_state().open/complete report the completed pattern, independently of
that exposed active valve. Fields: pattern, progress, total, open, complete,
phase (zero-based; boss 0 pair, 1 zigzag, 2 loop, 3 core).

All projectile checks use the supplied swept endpoints and XZ footprint;
there is no invented ray extension through cover. Keep jam-6's cover-clipped
endpoints and piercing intersections on integration. Current baseline actual
shots are checked at 30/60/240Hz. Only world_delta advances windows/motion.

Checks (bounded project wrappers):
  python3 ~/game-jams/projects/old-tech/check.py --seat jam-5 --suite patterns
  python3 ~/game-jams/projects/old-tech/check.py --seat jam-5 --suite pattern_weapons
Private visual script: res://scenes/pattern_preview/capture.gd via render.py.
Review images and receipt: state/old-tech-jam-5/exports/round-k.
