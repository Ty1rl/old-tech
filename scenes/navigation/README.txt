ROUND P / WAVE A — JAM-5 NAVIGATION HANDOFF

Room contract (jam-2 / integration)
Supply one active, enabled NavigationRegion3D in group museum_navigation in the
director's World3D. Its mesh must describe the walkable floor, with the same
exhibits, doors and world-XZ cover rectangles as physical collision. The director
discovers it automatically on positive world steps. No arena wiring is needed.
There is no replacement region or production test room. Enemies hold until native
maps are ready. Disable/re-enable, a changed mesh/transform, and an initially empty
mesh followed by an in-place completed bake invalidate/rebuild the native cache.
Changing cover/doors must also update the authored region; a cover-array mutation
alone does not invalidate maps. Only one room's region should be enabled at once.

ExhibitNavigation derives at most four native clearance maps from the authored
mesh, accounting for its existing agent_radius. Additional erosion plus projected
expanded cover rectangles matches the conservative full-silhouette swept mover
at square corners. Async bakes are coalesced to four outstanding jobs. Stale
callbacks are discarded. Meshes are assigned before regions attach to maps;
readiness checks native publication before projecting goals. No hand pathfinder.

Movement and time
EnemyNavigation is a reusable NavigationAgent3D scene. Archetypes choose intent;
native paths choose travel direction. CombatEnemy alone applies displacement.
Flow.cohesion() returns finite lateral velocity biases instead of moving actors.
step_enemy() accepts this optional fourth argument; existing three-argument
callers remain valid. Full silhouette cover, body spacing, contact, knockback,
stagger and attack telegraphs remain in the actor's movement/attack owner.

Crowds use native RVO with eight local neighbors. Requests convert supplied world
velocity into real physics velocity; callbacks only cache bounded direction/speed
fractions. Actors consume those with the current world delta, then perform swept
cover/body checks. Different clearance maps have separate RVO populations; the
shared body sweep still guards all sizes. Avoidance may use the clearance mesh's
spare margin, while the authored floor and swept collision bound final movement.

There is no new clock. Zero/inactive steps suspend agents; the existing time
controller's emergency/exhausted signals suspend all avoidance immediately even
when the arena skips stepping. Snapshots contain pose and Vector3 intent only.
Restore clears future routes, cached velocities and callbacks before rebuilding
from restored pose/intent. RIDs, paths, meshes and agent objects are not captured.

Settings
Edit navigation_settings.tres (shared read-only Resource exposed by both scenes).
For example repath_interval .3 -> .45 increases the minimum moving-target refresh
interval in world seconds; target_motion_threshold .65 is also required. Changing
clearance buckets requires keeping them ascending and large enough for supported
full movement radii. At most four buckets are used. No live Resource mutation is
needed; agent intent/cache state lives on instances.

Verification and review
Bounded check.py: import passed; navigation_p 19, swarm_p 17, patterns 72 and
enemy_time_n 81 checks passed (189 total, no failures, all exits 0). New navigation
checks yield real physics frames against a disposable three-exhibit fixture.
It is never loaded by production. They cover both detour directions, wide pattern
clearance, initial/re-enabled/empty regions, contact, knockback, exact slow-time
travel, frozen query state, restore, actual multi-target weapons and 32 actors.

Private render.py produced five reviewed images. Receipt, complete logs, profile,
and images are in state/old-tech-jam-5/exports/round-p-a/. The 600-frame headless
crowd trial measured director p95 10.991 ms, native-navigation p95 2.438 ms,
193 native path changes, all 32 actors progressing, and a 3.63-radian escape gap.
These are isolated CPU measurements, not a combined-room graphics frame budget.

Integration still needs jam-1's combined/cold/actual-room checks with jam-2's
authored regions and collision. Older synchronous movement checks need a valid
region and physics frames for native publication; do not add a fallback room to
make those fixtures move. No campaign, room, art, weapon or time-source edits here.
Wave B is not started.
