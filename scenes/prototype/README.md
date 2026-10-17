# Combat prototype

Godot 4.7.2 Standard / Compatibility. Open the root project, open
`scenes/prototype/arena.tscn`, then F6. From the Ubuntu host:

```sh
~/.local/bin/godot --path ~/game-jams/projects/old-tech/seats/jam-1/repo res://scenes/prototype/arena.tscn
```

WASD moves; mouse aims. Keys 1/2/3 select ring/flash/cone. Left mouse uses it.
Hold Space for time slow. E repairs the selected tool; T repairs the clock.
R resets the sandbox. F1–F4 spawn a target, swarmer, brute or skirmisher at
the cursor; F5 adds a mixed group; F6 starts/restarts a bounded encounter.
Backspace clears enemies and cancels the encounter. Escape pauses.

Four translucent arcs surround an open center around the player: ring (cyan),
flash (yellow), cone (orange), clock (violet). Each arc shows remaining condition;
the selected tool has a thin outer highlight and a nearby readiness label.
The short inner straight bar is health. F7 cycles the upper debugging readout
through full, dim, and hidden; it starts dim and saves the choice across launches.
The player gauges remain visible in all three modes. Their radius, spacing and
opacity are grouped in `status_hud.gd` for early playtest adjustments.

## Try the resource loop

Start with the stationary blue target, then F5 or F6 for pressure.

- Ring: hold and draw a floor path, release to launch. Only the stroke damages;
  outbound/return are harmless. Route around cover. The returning ring can
  home through cover in this prototype. One launch costs one service unit.
- Flash: a strong single-target pulse, first enemy or solid cover stops it.
  Damage 70, cooldown 0.8 seconds; one service unit per shot, including misses.
- Cone: a short multi-target attack. Initial bursts shove and briefly stagger;
  holding gives lighter sustained pushing and 16 damage per second. Strong
  bursts have a 1.5-second cooldown and cost 1.5 additional firing-seconds.
  Brutes resist shove/stagger; solid cover blocks the effect.

Equipment starts with 32 ring launches, 48 flash shots, 45 cone firing-seconds
and 24 slow-seconds. These are generous first tuning values, not a promise
about how often repairs will feel necessary. Wear occurs only during use.
The clock does not recharge passively. All tools can kill all enemy types;
the brute's front shield reduces damage to 25%, while sides/rear take full.
Actual attack contact decides armor, including the ring's path behind a brute.

## Repairs

Press E or T. Hold inside contact 1, follow the channel through the numbered
contacts, then release inside the final circle. Each completed section restores
one quarter of that item's capacity immediately. Close and return whenever you
want: completed steps and restored capacity remain. Only an unfinished gesture
is discarded. Full gear shows Ready.

Movement and enemies continue during repairs. A hit interrupts the panel.
The clock can help repair another tool, but cannot slow time during its own
repair. An empty clock remains repairable at normal speed. After repairs,
pause or exhaustion, release Space before activating slow again.

Time slow affects enemies, their attacks and the encounter schedule. Player
movement, weapon travel, damage, cooldowns, wear and repairs use real time.
F6 begins a 75-world-second sequence with at most six live enemies. Clear the
remaining enemies after the schedule to win. At 0 HP it stops spawning; R
returns to the sandbox or F6 retries. Sandbox has no forced death screen.

## Checks and tuning

All gameplay values are in `tuning.gd`; the arena owns the simulation clock.
The partner's original main-menu/game scenes and popup managers remain.
Headless checks cover components, real weapon/enemy combinations, resource
integration, interrupted repairs, cover, control, timing and encounter lifecycle.
Rendered checks also exercised a real GUI repair trace and retained progress.
They do not establish game feel: playtest shove strength, repair frequency,
repair readability under pressure and enemy density.

The shared lab runner bounds each check to 60 seconds and saves full logs:

```sh
python3 ~/game-jams/projects/old-tech/check.py --seat jam-1 --suite integration
```

Suites: equipment, foundation, player, repairs, weapons, enemies,
resource_integration and integration. Use `--suite import` after script/scene
changes. On another machine, run Godot directly with an external timeout:

```sh
timeout 60s godot --headless --editor --path . --quit
timeout 60s godot --headless --path . --script res://scenes/prototype/checks/integration.gd
```

Godot can stay alive after a script error; inspect the error instead of waiting
or rerunning unchanged. The timeout runner is in shared lab tooling, not a game
runtime dependency. There are no final assets or boss encounter in this pass.
