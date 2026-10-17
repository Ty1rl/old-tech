# Combat prototype

Godot 4.7.2 Standard / Compatibility. Open the root project and run
`scenes/prototype/arena.tscn` with F6, or from the Ubuntu host:

```sh
~/.local/bin/godot --path ~/game-jams/projects/old-tech/seats/jam-1/repo res://scenes/prototype/arena.tscn
```

WASD move; mouse aims; 1/2/3 select ring/flash/cone; left mouse uses the tool.
Hold Space for time slow. R resets everything. F1–F4 spawn a target, swarmer,
brute or skirmisher at the cursor; F5 spawns a mixed encounter; Backspace clears.
Escape opens the existing pause popup; its Exit returns to the main menu.

This foundation currently provides movement, the arena, HUD and pause/reset.
Weapons, enemy simulation and time-slow are assigned to the other seats.
All gameplay tuning belongs in `tuning.gd`. The arena is the only simulation
clock: player and weapons receive real delta, enemies receive scaled delta.
The existing main-menu/game scenes and manager APIs remain available.
