# Combat prototype

Godot 4.7.2 Standard / Compatibility. From the Ubuntu host:

```sh
~/.local/bin/godot --path ~/game-jams/projects/old-tech/seats/jam-1/repo res://scenes/prototype/arena.tscn
```

Or open the root project, open `scenes/prototype/arena.tscn`, then F6.
The partner's original menu/game scenes and popup managers remain intact.

## Controls

- WASD moves; mouse aims. 1/2/3/4 equip ring/flash/cone/clock.
- Ring: hold left mouse to draw a floor path, release to launch.
- Flash: hold left mouse to charge, release to fire. Quick taps are weaker.
- Cone: hold left mouse for continuous heat and repeating shove/stun pulses.
- Hold E to repair the equipped item; release E to resume. Full gear ignores E.
- Space with ring/flash/cone: slow the world; movement and aiming remain normal.
- Space with clock: freeze and inspect history. Wheel up goes backward, down
  returns toward now. Release Space to jump to the selected moment. At NOW,
  release simply resumes. Escape cancels to the original present.
- R resets. F1–F4 spawn target/swarmer/brute/skirmisher at cursor. F5 adds a
  mixed group; F6 starts/restarts a bounded encounter. Backspace clears it.
- Escape normally pauses. F7 cycles upper numbers through full/dim/hidden;
  the preference persists. Player gauges remain visible in every mode.

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
travel less but still visibly stagger. All tools can kill every archetype;
front armor reduces actual contact damage to 25%, not a weapon matchup bonus.

Starting condition: 32 ring launches, 48 flash shots, 45 cone firing-seconds,
24 clock slow-seconds. Cone pulses add wear. Clock has no passive recharge.
These are generous initial values to tune through play, not final balance.

Wear progressively erases the repair path. Trace the missing portion from
contact 1 through the marked end, then release the mouse. Each section restores
the next quarter boundary. Slight damage needs a shorter trace; completed
capacity survives interruption. Full repair closes automatically. Only an
unfinished gesture is lost on E release, damage, pause or focus loss.
Movement/enemies continue during repairs. The clock can slow another item's
repair, but cannot power its own. No separate T repair path exists.

## Rewind

Equipping 4 does not activate time manipulation. A fresh Space press begins
inspection; changing tools while already holding Space requires release first.
Inspection blocks movement, attacks, repair and debug mutations. Its nearby
readout shows NOW or selected age, proposed jump wear, and a short timeline.

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

F6 is a 75-world-second encounter capped at six live enemies. Clear survivors
after the schedule to win. Art, bosses, sound and authored levels are later work.
Tests establish behavior and state restoration, not enjoyable balance.

```sh
python3 ~/game-jams/projects/old-tech/check.py --seat jam-1 --suite rewind
```

Other suites: equipment, foundation, player, repairs, weapons, enemies, history,
resource_integration, integration. Use import after script/scene changes.
The shared lab runner bounds execution and saves full logs in seat state.
On another machine: `timeout 60s godot --headless --path . --script
res://scenes/prototype/checks/rewind.gd` (one shell line).
