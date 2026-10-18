# Some Assembly Required — gameplay and testing

Use **Godot 4.7.2 Standard / Compatibility**. From the Ubuntu host:

```sh
~/.local/bin/godot --path ~/game-jams/projects/old-tech/seats/jam-1/repo
```

Restart an already running game after source updates. Choose **New Game** for the
campaign. **Encounter select** in the main/pause menu, or F10 during play, jumps to
a room, encounter or valid boss phase with the required equipment. Disable these
entrypoints with `SceneManager.developer_tools = false`.

## Controls

| Input | Action |
|---|---|
| WASD | Move, including while repairing |
| Mouse | Aim |
| 1–4 | Equip cutter, flash camera, heat bellows, clock, once collected |
| Tab / Shift+Tab | Cycle collected tools, including inside repair |
| Left mouse | Draw/release cutter; charge/release flash; hold cone |
| E | Toggle repair for the selected item; release E does nothing |
| Escape | Close repair, cancel a rewind preview, or pause ordinary play |
| Space | Manual slow; with the clock outside repair, enter rewind review |
| Wheel down / up | During review, go backward / toward the present |
| Release Space | Commit the selected rewind; NOW simply resumes |
| +/- | Zoom the perspective camera |
| R | Retry the current room |
| F7 | Full/dim/hidden diagnostic numbers, saved across launches |
| M | Toggle sound, saved across launches |

Holding Space survives tool switches. Switching to the clock enters review;
switching away cancels an uncommitted preview and keeps slowing while Space is
held. Inside repair, selecting the clock stays in repair rather than entering
review. The clock cannot power its own repair.

## Repair and condition

Repair shows a large transparent model over the moving world. Drag the highlighted
part to spin it in either direction, trace the highlighted route, or connect
matching shapes. Spin accepts uneven circles, partial turns and regrips.

E or Escape closes repair. Full gear stays visible as Ready so another item can
be selected without reopening the interface. Completed condition checkpoints
survive interruption; ordinary damage does not dismiss the panel. Death, leaving
play or losing application focus still cleans up the interaction. Weapons cannot
fire through the repair UI.

**Repair never starts time slow automatically.** Hold Space manually if desired
and the clock is available. Movement and enemies continue; repairs grant no damage
immunity. Equipment condition is consumed by use, not by idle time:

| Tool | Full condition |
|---|---|
| Cutter | 24 launches |
| Flash | 64 shots |
| Cone | 24 seconds, with extra wear for displacement pulses |
| Clock | 18 seconds; no passive recharge |

Yellow remains protected during the opening lessons and encounters. A deliberate
safe break teaches repair before ordinary yellow wear begins. Completing that
lesson restores the acquired tools. These are playtest budgets, not final balance.

## Campaign and combat

A burial device beneath the museum assembles bodies from its exhibits. The run
crosses Public Galleries, Connected Collections, Restoration Rooms and Burial
Exhibition. Equipment is found in order: yellow, orange, blue, purple.

New mechanics get a brief explanation and safe attempt, followed by finite staged
combat. Early encounters refill promptly when almost cleared; arrivals remain
warned and capped. Loop and multi-cut spawns reserve their full interactive span
and drawing clearance, including future boss phases. Clear rooms open a broad
green doorway; repair before walking through when ready.

| Part | Efficient interaction |
|---|---|
| Blue | Cross the connection with the cutter; one stroke can cut several units |
| Orange | Heat away protection with the cone; shove/stagger creates room |
| Yellow | Aim at the exposed target; quick shots work on simple yellow units |
| Guard | Cut or heat protection, then charge a shot into the exposed core |
| Pair | Quick shot at A opens B briefly; complete the sequence |
| Loop / zigzag | Complete the cut pattern, then charge the exposed core |

The Loop Curator has three cut/open/core phases; the Sequence Warden has three
paired-shot/core phases. The Burial Device tests pair, zigzag, loop and final core.
Body damage remains a slow alternative to every intended pattern. Partial pattern
timeouts reset links/shutters, not body damage or destroyed orange armor.

Fully charged flash shots pierce intersected enemies; solid cover stops them.
The cutter arcs harmlessly to its start, cuts along the stroke, and returns to the
moving player. Hit samples stay unchanged; only its displayed path is smoothed.

Hostile projectiles have locked windups, outlined red/ivory heads and short trails.
They can be dodged through movement, respect cover, slow with the world and rewind.
Their projected heads stay visible over the repair model. Dead owners, clear/retry
and lethal player damage remove their shots. There is no separate defense ability.

## Time, health and state

Slow scales player/enemy movement, gait, attack travel and combat timers. Cursor
input, drawing, charging and resource wear use real elapsed time. Clock review
freezes combat; positions interpolate between previews while discrete state stays
recorded. Releasing Space commits; Escape or switching tools cancels the preview.

Campaign history is bounded to 12 seconds / 240 snapshots, at most 64 KiB per
snapshot plus one backup. Only value data is stored. Reference/type, depth and size
validation remain enabled. History clears at progression boundaries; learned
controls and acquired equipment remain permanent within the run. Reinforcement
debt and in-flight threats rewind with the combat roster.

Review costs 0.2 clock units per real second; jumping additionally costs one unit
per second rewound. Previewing never refunds worn clock condition.

Only the latest wound regenerates after five quiet WORLD seconds, at 12 HP/s.
Another hit restarts the wait. Room retry/entry restores health and condition.
After finding the clock, lethal damage leaves a short rewind opportunity; otherwise
retry the room. Regeneration never revives a dead player.

## Source and verification

`arena.gd` coordinates input and the single simulation clock. `campaign.gd` owns
progression; `rooms.gd` contains rosters/layouts. Equipment/repair, weapons, enemy
controllers/visuals, history, and HUD remain separate. The directory's historical
`prototype` name is retained; teammate scenes and popup managers are still used.

For the isolated sandbox, open `scenes/prototype/arena.tscn` and press F6. F1–F4
spawn targets/color units; F5 a pack, F6 an encounter, F8/F9 guards; Backspace clears.
Campaign blocks those sandbox keys.

Use the shared project `check.py --seat jam-N --suite NAME` for bounded feature
checks. Keep full logs in seat state and report totals/failures. Automated graphical
previews must use `render.py` on its private virtual display, never Matt's desktop.
Current integration receipts live in `state/old-tech-jam-1/exports/round-m/`.

Models remain stylized, boss assemblies are simple, and audio remains provisional.
Human playtesting determines whether repair, pressure and movement feel right.
