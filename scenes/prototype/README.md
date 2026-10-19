# Some Assembly Required - gameplay and testing

Use **Godot 4.7.2 Standard / Compatibility**. From the repository root:

```sh
godot --path .
```

Restart a running game after updates. Choose **New Game**, then **Easy** or **Hard** for the campaign.
Launch with `-- --developer` to enable **Encounter select** in developer options
and F10. Normal launches and Web exports hide these shortcuts.

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

History samples 12 times/second over 18 world seconds (normally 216 snapshots,
with a hard limit of 240), each at
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

Condition is consumed by use: cutter 24 launches; flash 64 shots; cone 36 seconds
with 0.3 additional wear per displacement pulse (about 29 seconds of continuous normal-time use). Edit `scenes/weapons/settings/weapon_condition.tres`.
Opening yellow lessons are protected until a deliberate repair lesson.

## Campaign and combat

A burial device beneath the museum assembles bodies from its exhibits. Cross
Public Galleries, Connected Collections, Restoration Rooms and Burial Exhibition,
collecting yellow, orange, then blue. The survival meter is visible from the start;
slow and rewind unlock during their respective lessons.

Easy and Hard share time, damage, and weapon-condition rules. Hard adds concurrent
threats and faster finite arrivals. Tune the authored `settings/difficulty_*.tres`
resources; `rooms.gd` contains the per-wave rosters and formations.

New mechanics demonstrate the actual action, then give two stationary and two
moving practice attempts before a finite combat wave. Combination and pattern
lessons use one of each. Familiar mixed waves separate new introductions. The
demonstration's Try it button skips directly to practice; learned lessons stay quiet.

Emergency rewind uses a short staged action and unavoidable hit, then opens the
real scrubber on a safe earlier moment. Confirming completes the lesson once and
starts real play with all three charges. Ordinary rewinds still spend a charge.
Retries retain completed lessons. Cleared rooms open a real north-wall doorway
with green floor arrows.

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
- `scenes/ui/repair_carousel.tscn`: actual owned-tool side previews and shared
  condition arcs. Repair supplies the selected model's viewport-space bounds;
  the carousel requests selection through the existing repair/equipment flow.
- `scripts/audio/protagonist_voice.gd`: category coverage and sparse reaction selection;
  `audio/voice/README.txt` documents timing, contexts and clip history.
- `scenes/navigation/`: native enemy routing and bounded crowd avoidance, using
  the current museum room's authored region and full body clearance.
- `scenes/tutorial/`: ordinary action demonstrations and the forced emergency
  rewind lesson. Campaign scenes mount these components; progression owns when
  they start and when safe practice gives way to combat.
- `scenes/ui/*.tscn`, `museum_theme.tres`: editable menus; no rebuilding their child
  trees in `_ready`. Status arcs and attack paths remain procedural geometry.
- `assets/ui/menu_background.png`: supplied menu artwork, with live title/buttons.
  `assets/fonts/` contains Barlow Condensed Black and Inter Regular/SemiBold plus
  their licenses. The shared museum theme and GameState startup apply typography
  to native controls and custom-drawn HUD text.

The existing scene manager and popup flow remain in use. The old `prototype`
directory name is retained to avoid a broad path migration during the jam.

## Verification

From the repository root, with Godot 4.7.2 Standard:

```sh
godot --headless --path . --script res://scenes/prototype/checks/complete_run.gd
godot --headless --path . --script res://scenes/prototype/checks/protagonist_voice.gd
godot --headless --path . --script res://scenes/prototype/checks/audio_s.gd
```

Additional focused checks cover time/recovery, weapon components, repairs,
enemy patterns and navigation, speech lifetime, menus and developer encounter
selection. `developer_encounters` verifies an actual Hard boss launch, including
enemy tuning and weapon wear. Keep logs and screenshots outside the source tree.

Use a private virtual display for automated graphical previews.
`flow_capture_k` and `combat_capture_o` are graphical captures, not headless checks: frame-post-draw
requires a renderer. Do not use the active desktop display for automated previews.

Models and sound remain provisional. Human playtesting determines whether the
resource budgets, repair interruptions and encounter pressure feel right.

## Recovery behavior and remaining limits

Weapon condition intentionally rewinds with the world. Choosing a moment before
repair undoes its result without refunding time; choosing a moment before firing
refunds wear. Time, charges, learned lessons, unlocked abilities, and acquired
tools remain live. Within-room wave timers, pending arrivals, practice results,
and enemies restore together; actual room-layout boundaries clear the history.

The music/SFX and difficulty values need human listening and playtesting. Fixed
room props use authored scenes/resources; the combat paths, swarms and HUD arcs
remain generated. Superseded previews that relied on removed health/manual-clock
APIs and the fixed Round R audio audit have been removed; Git retains their history.
