# Combat prototype

Round C development: shared equipment/cover interfaces are ready; repair puzzles,
wear consumption, crowd control and the encounter sequence are being assigned.
The repair panel is currently a placeholder. The published playable Round B
remains on `origin/prototype/combat-playground` at `1419d7a`.

Godot 4.7.2 Standard / Compatibility. Open the root project and run
`scenes/prototype/arena.tscn` with F6, or from the Ubuntu host:

```sh
~/.local/bin/godot --path ~/game-jams/projects/old-tech/seats/jam-1/repo res://scenes/prototype/arena.tscn
```

WASD move; mouse aims; 1/2/3 select ring/flash/cone; left mouse uses the tool.
Hold Space for time slow. R resets everything. F1–F4 spawn a target, swarmer,
brute or skirmisher at the cursor; F5 spawns a mixed encounter; Backspace clears.
Escape opens the existing pause popup; its Exit returns to the main menu.

Tool 1: hold left mouse, draw a path on the floor, release. The ring travels
out, cuts along that path, and returns to your current position. Only the
drawn section damages enemies. Blue is preview; orange is the active route;
green is the completed portion. The stroke has range and length limits.

Tool 2: click for a precise flash that hits the first enemy. Tool 3: hold for
a broad, short-range cone. All three tools can kill every enemy. The orange
brute's pale shield reduces frontal damage; the rear takes full damage.
Blue targets are stationary, red swarmers approach, and green skirmishers
alternate sidestepping and approaching. Damage feedback reports actual HP lost.

Time slow affects enemy movement and contact attacks. You, your weapons and
the slow meter continue at normal speed. Release Space to recharge; after
exhaustion or pausing, release it before activating again. Switch tools while
the ring travels; switching while holding the mouse requires a fresh press.

Start with the target, then F5 for a modest mixed group. There is no automatic
enemy spawning or death screen; at zero health you can still experiment, or R
restores health. There are no repair puzzles, audio or finished art in this pass.

All gameplay tuning belongs in `tuning.gd`. The arena is the only simulation
clock: player and weapons receive real delta, enemies receive scaled delta.
The existing main-menu/game scenes and manager APIs remain available.

Verification: 168 headless checks across foundation, player, weapons, enemies
and integration. The integration suite uses the real enemy and weapon scripts,
checks every weapon/enemy pairing, rear armor contacts, frame-independent cone
damage, slow time, pause/resume and reset. From the root checkout on the host:

```sh
~/.local/bin/godot --headless --editor --path . --quit
~/.local/bin/godot --headless --path . --script res://scenes/prototype/checks/integration.gd
```

The other suites are `foundation.gd`, `player.gd`, `weapons.gd` and `enemies.gd`
in the same checks directory. Headless checks verify behavior; human playtesting
still needs to judge aiming, stroke limits, enemy pressure and slow duration.
