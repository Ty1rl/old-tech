# Combat prototype

Godot 4.7.2 Standard / Compatibility. From the Ubuntu host:

```sh
~/.local/bin/godot --path ~/game-jams/projects/old-tech/seats/jam-1/repo res://scenes/prototype/arena.tscn
```

Or open the root project, open `scenes/prototype/arena.tscn`, then F6.
The partner's original menu/game scenes and popup managers remain intact.

## Controls

- WASD moves; mouse aims. 1/2/3/4 equip ring/flash/cone/clock.
  Tab cycles forward; Shift+Tab cycles backward.
- +/- zooms the view; R restores the default closer camera.
- Ring: hold left mouse to draw a floor path, release to launch.
- Flash: hold left mouse to charge, release to fire. Quick taps are weaker.
- Cone: hold left mouse for continuous heat and repeating shove/stun pulses.
- Hold E to repair the equipped item; release E to resume. Full gear ignores E.
- Space with ring/flash/cone: slow the world; movement and aiming remain normal.
- Space with clock: freeze and inspect history. Wheel down goes backward, up
  returns toward now. Release Space to jump to the selected moment. At NOW,
  release simply resumes. Escape cancels to the original present.
- R resets. F1 spawns a stationary target; F2 blue, F3 yellow, F4 orange.
  F8 spawns a side-attachment guard. F5 adds a mixed pack; F6 starts/restarts
  the bounded encounter. Backspace clears enemies.
- Escape normally pauses. F7 cycles upper numbers through full/dim/hidden;
  the preference persists. Player gauges remain visible in every mode.
- F9 starts the front-plate guard showcase with a closer camera. R returns to
  the normal sandbox. M toggles sound and saves the choice across launches.

## Colored-part enemies

- **Blue connector:** cutting across it kills a blue-only enemy. A curved stroke
  can kill several; the cutter continues through enemies. It still stops at cover.
- **Yellow target:** an accurate flash shot kills it, including a quick tap.
- **Orange covering:** sustained cone heat breaks it and kills an orange-only enemy.
- **Side-attachment / front-plate guards:** cut the blue connector OR heat the
  orange covering, then shoot the exposed yellow target. Both openings are
  permanent; a quick accurate shot is enough to clean up. Body shots before
  opening do not receive the core kill.

Every tool can kill every enemy through ordinary damage. New enemies have high
health and take 12% ordinary body damage: a blue enemy takes about 30 fully charged
body shots versus one cable cut. This spends existing equipment condition; there
is no extra ammunition system. Correct part hits are decisive, not immunity rules.
These initial values need playtesting.

Blue connectors are thicker and accept nearby cursor strokes at their visible
height, rather than targeting the floor behind them. Yellow cores sit above
the hull and remain readable from every facing. Removed orange panels disappear.
Cursor assistance only resolves nearby visible blue/yellow targets; actual
attacks still collide with enemies and cover.

Blue connectors and guards approach in small cohorts that seek spaced slots on
a shrinking arc around the player. They release formation close to contact, so
packing never prevents attacks. Cohesion, spacing and approach are in `Tuning.PACK`;
set strength to zero for direct chasing. Cover avoidance still applies.

New enemies wind up before striking, then stop during recovery. Cone pulses
shove light enemies farther and stun for about two world seconds. Heavy guards
move less but still stun, so heating remains practical. Correct kills, recovery
and shove are intended to earn repair windows. No damage immunity is granted
while repairing. Mechanisms, windups, recovery and pack placement rewind.

The temporary player model is 30% larger, with both hands gripping the equipment
and forearms following those grips during walking. Collision and history roots
are unchanged. Jam-5's separate Blender model trial is not integrated here.

Tool colors are shared across HUD, parts and effects. Placeholder sounds include
weapon loops, impacts, mechanism breaks, repair clicks and clock speed ramps.
M mutes them. Historical browsing never replays hit/break cues.

## Equipment and repairs

Cyan/yellow/orange/violet arcs show remaining ring/flash/cone/clock condition.
The center stays open around the player. Selected equipment has a thin outer
highlight and readiness text; a short straight inner bar shows health.

The ring arcs harmlessly over cover to the start of the stroke. Only its
floor-level cutting path deals damage or stops against cover. The return
homes harmlessly to the moving player, including through cover. Preview
colors distinguish reachable and blocked portions of the cutting path.

Flash has a 35-unit range, 30–100 damage over 0.9 seconds of charge, and a short
cooldown. Visible pulses hit the first enemy or cover. Cone damages multiple
enemies and shoves/staggers at 1.2-world-second intervals while held. Brutes
travel less but still visibly stagger. All tools can kill every archetype; correct colored-part contacts are much
more efficient than ordinary body damage.

Starting condition: 32 ring launches, 48 flash shots, 45 cone firing-seconds,
24 clock slow-seconds. Cone pulses add wear. Clock has no passive recharge.
These are generous initial values to tune through play, not final balance.

Wear progressively erases the repair path. Trace the missing portion from
contact 1 through the marked end, then release the mouse. Each section restores
the next quarter boundary. Slight damage needs a shorter trace; completed
capacity survives interruption. Full repair closes automatically. Only an
unfinished gesture is lost on E release, damage, pause or focus loss.
Movement/enemies continue during repairs. Repairing ring/flash/cone automatically
uses clock-powered slow, spending clock condition at its normal real-time rate.
An empty clock leaves repairs at normal speed; the clock cannot power its own
repair. Release E to stop the automatic slow. No separate T repair path exists.

## Rewind

Equipping 4 does not activate time manipulation. A fresh Space press begins
inspection; changing tools while already holding Space requires release first.
Inspection blocks movement, attacks, repair and debug mutations. Its nearby
readout shows NOW or selected age, proposed jump wear, and a short timeline.
Positions and orientations ease between selected snapshots over 0.14 real
seconds. Health, destroyed parts and other discrete state stay recorded values;
commit/cancel restores the exact selected state before gameplay resumes.

Inspection costs 0.2 clock units per real second. A committed jump additionally
costs 1 clock unit per second rewound. Preview never refunds clock condition;
committed clock is capped at the lesser of its restored and live values before
the jump cost. Other equipment, health, enemy roster/behavior, encounter state,
and launched attacks restore to the selected snapshot. The clock stays equipped;
held attacks/drawing/charge must start afresh after leaving inspection.

Cancellation preserves the original present and charges inspection wear only.
An unaffordable wheel selection is rejected; exhausting condition while browsing
cancels to the present rather than forcing a jump. Focus loss cancels before
pausing. A committed jump discards the abandoned future; scrolling does not.
Death freezes normal simulation and preserves recent history for a do-over.

History samples explicit gameplay values at 20 Hz, retaining up to five seconds
and 100 encoded snapshots. Each snapshot is limited to 64 KiB, with at most 32
live enemies, bounded attack paths and eight flash pulses. During inspection,
cancel backup shares existing payloads and may retain one extra evicted payload.
This bounds encoded storage to 101 payloads; decoded state/engine overhead is
additional. No scenes, textures, materials or live Node references are copied.
Reset and debug spawns/clears erase history; HUD preferences do not rewind.

## Timing and verification

`tuning.gd` holds gameplay values; arena owns the tick and Engine.time_scale
stays 1. Player input, movement, flash charge, cooldowns, wear and repair use
real time. Enemy behavior, attack flight, cone damage and shove cadence use
world time. During inspection only its real-time clock wear advances.

F5 adds two blues, both opening layouts, one yellow and one orange. F6 begins
with three blues, adds yellow/orange at 12 seconds and guards at 24 seconds.
There are no new arrivals at the 36-second checkpoint; reinforcements resume
at 48 seconds. Clear current enemies to earn that breathing room. The encounter
lasts 75 world seconds and caps live enemies at eight; clear survivors to win.
Final art, bosses and authored levels are later work.
Tests establish behavior and state restoration, not enjoyable balance.

```sh
python3 ~/game-jams/projects/old-tech/check.py --seat jam-1 --suite rewind
```

Other suites: equipment, foundation, player, repairs, weapons, enemies, history,
resource_integration, integration, parts, feedback, scrub_view, presentation,
player_visual, variants, readability.
Use import after script/scene changes.
The shared lab runner bounds execution and saves full logs in seat state.
On another machine: `timeout 60s godot --headless --path . --script
res://scenes/prototype/checks/rewind.gd` (one shell line).
