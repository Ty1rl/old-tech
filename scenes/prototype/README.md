# Some Assembly Required — gameplay and testing

Use **Godot 4.7.2 Standard / Compatibility**. From the Ubuntu host:

```sh
~/.local/bin/godot --path ~/game-jams/projects/old-tech/seats/jam-1/repo
```

Restart a running game after updates. Choose **New Game** for the campaign.
**Encounter select** in the main/pause menu, or F10, jumps to a room, encounter or
boss phase with the required equipment. `SceneManager.developer_tools` hides the
shortcuts when false.

## Controls

| Input | Action |
|---|---|
| WASD | Move, including while repairing |
| Mouse | Aim |
| 1 / 2 / 3 | Equip collected cutter / flash camera / heat bellows |
| Tab / Shift+Tab | Cycle collected weapons, including inside repair |
| Left mouse | Draw/release cutter; charge/release flash; hold cone |
| E | Toggle repair; release E does nothing |
| Escape | Close repair or pause play/recovery |
| Hold Space | Slow the world and player; drawing/input stay responsive |
| Wheel down / up | During emergency recovery, choose older / newer moments |
| Click / Enter | Confirm emergency recovery |
| +/- | Zoom the perspective camera |
| R | Retry the current room |
| F7 | Full/dim/hidden diagnostic numbers, saved across launches |
| M | Toggle sound, saved across launches |

There is no selectable clock or manual rewind. Holding Space survives weapon
switches. Repair never starts slow motion automatically.

## Time and recovery

One rechargeable time meter replaces player health. Hits, slowing and completed
repair checkpoints spend it. Running out through voluntary spending stops slow
or repair; only a hit triggers emergency recovery. The passive time device never
breaks or needs repair.

Starting values live in `scripts/time/time_settings.tres`: 100 time, recharge
12/second after a 1.5-second hit delay, slow at 0.18x for 8 time/second, repair
6 time/checkpoint, and three emergency charges per room attempt. These are
playtest settings. Recharge pauses while slowing or performing a repair gesture;
an idle repair panel allows recharge.

A depleting hit spends one charge immediately and freezes combat. Scroll down for
older moments, then click or press Enter. Recovery grants at least 40 time and
1.5 seconds of protection. Charges cannot be refunded by rewinding. With no
history, a seeded room checkpoint remains available. With no charges left, retry
the current room with fresh time/charges, preserving learned lessons and equipment.

History stores at most 240 value-only snapshots over 12 world seconds, each at
most 64 KiB, plus a checkpoint and the emergency's current-state copy. No nodes,
rigs, time balance, charges, learned lessons or acquired loadout enter snapshots.
Deep validation runs in checks; normal sampling retains size bounds without
recursive validation. Reinforcement debt and in-flight attacks rewind together.

## Repair and HUD

Three upper arcs show weapon condition in repair-checkpoint segments. Unowned
weapons are hidden; inactive ones are smaller/dimmer. An extra outer line marks
selection. The smooth lower purple arc shows time, with emergency-charge pips.
Charge appears at the cursor. Repair keeps a time readout above its transparent
model even when optional diagnostic numbers are hidden.

E starts with the equipped weapon if damaged, otherwise the most damaged owned
weapon. Drag the highlighted part to spin, trace, or connect matching shapes.
Spin accepts either direction, partial turns and regrips. Completed checkpoints
survive interruptions. Finishing a weapon advances to another damaged owned
weapon; finishing all closes the screen automatically. Tab/1–3 also select
manually. E/Escape closes. Mouse gestures cannot fire a weapon through the panel.

Condition is consumed by use: cutter 24 launches; flash 64 shots; cone 24 seconds
with extra wear for displacement pulses. Edit `scenes/weapons/settings/weapon_condition.tres`.
Opening yellow lessons are protected until a deliberate repair lesson.

## Campaign and combat

A burial device beneath the museum assembles bodies from its exhibits. Cross
Public Galleries, Connected Collections, Restoration Rooms and Burial Exhibition,
collecting yellow, orange, then blue. Time is available from the start.

New mechanics get an explanation, safe practice and then staged combat. Emergency
rewind is taught through a real controlled depletion after usable history exists.
Retries retain completed lessons. Cleared rooms open a green exit doorway.

| Part | Efficient interaction |
|---|---|
| Blue | Cross the connection with the cutter; one stroke can cut several units |
| Orange | Heat away protection; cone shove/stagger creates room |
| Yellow | Aim at the exposed target; quick shots work on simple yellow units |
| Guard | Cut or heat protection, then charge a shot into the exposed core |
| Pair | Shoot A, then the briefly opened B |
| Loop / zigzag | Complete the cut pattern, then charge the exposed core |

The Loop Curator tests cut/open/core phases; the Sequence Warden tests paired
shots. The Burial Device combines pairs, zigzags, loops and a final core.
Ordinary damage remains a slow alternative. Pattern timeouts reset links/shutters,
not body damage or destroyed orange armor.

Charged flash pierces intersected enemies; cover stops it. Cutter outbound/return
travel is harmless. Its raw stroke drives hits; mild display smoothing leaves
successful cuts unchanged. Incoming attacks have subtle warning lines and visible
projectile heads. Movement dodges them; cover blocks them; time slows them.

## Where to edit

- `arena.gd` (`CombatArena`): composition, input, simulation tick and snapshot wiring.
- `campaign.gd` (`MuseumCampaign`), `rooms.gd`: progression, lessons and encounter data.
- `scripts/time/`: typed time/recovery core; `CONTRACT.md` describes its public API.
- `scenes/weapons/weapons.tscn`: real cutter/flash/bellows child components and
  inspector resources. See `scenes/weapons/README.txt` for an editing example.
- `combat_player.tscn`: authored player/camera/rig composition. `player.gd` handles
  movement and forwards damage to the shared time controller.
- `repair.tscn`, `repair.gd`, `repair_gestures.gd`: repair layout and gestures.
- `scenes/ui/*.tscn`, `museum_theme.tres`: editable menus; no rebuilding their child
  trees in `_ready`. Status arcs and attack paths remain procedural geometry.

The existing scene manager and popup flow remain in use. The old `prototype`
directory name is retained to avoid a broad path migration during the jam.

## Verification

From the shared project directory:

```sh
python3 check.py --seat jam-1 --suite campaign_n
python3 check.py --seat jam-1 --suite complete_run
python3 check.py --seat jam-1 --suite repair_n
```

Other focused suites cover time_core_n, combat_player_n, emergency_mode_n,
weapon_components_n, weapon_smoothing_n, enemy_time_n, ui_n, and movement_m.
Retained earlier combat, pattern, room, menu and animation checks use the current
components. Logs/receipts stay in each seat's state. Combined Round N evidence:
`state/old-tech-jam-1/exports/round-n/integration/`.

The removed manual-clock/four-tool suites were `rewind`, `presentation_j`,
`controls_l`, `resource_integration`, `space_m`, `repair_m`, `repairs`, `ui_m` and
`hud_profile_m`. Their obsolete health/clock assumptions are preserved in Git;
new time, repair, recovery, UI and integrated checks cover the replacement rules.
The remaining repair-view check still exercises actual gestures at multiple sizes.

Automated graphical previews must use shared `render.py` on a private display.
`flow_capture_k` is a graphical capture, not a headless check: frame-post-draw
requires a renderer. Never launch automated previews on Matt's desktop.

Models and sound remain provisional. Human playtesting determines whether the
resource budgets, repair interruptions and encounter pressure feel right.

## Known limitations from the current review

Emergency recovery currently rewinds weapon condition with the world. Choosing a
moment before a repair can undo that completed repair without refunding its time
cost; choosing a moment before firing can refund weapon wear. The next pass needs
to settle whether condition should persist through recovery like time and charges.

Remaining maintenance work: repair wiring accesses private popup/session fields;
arena startup overrides authored camera settings; the Space action is registered
at runtime and the time contract's wiring example needs updating. Historical
`ui_preview_m` and `ranged_preview/capture_m.gd` scripts still use removed APIs.
