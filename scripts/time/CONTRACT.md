# Time core contract (current: Round O Wave A)

Files: `scripts/time/` (TimeSettings, TimeController, ReplayHistory, EmergencyRewind,
`time_settings.tres`) and the editor composition `scenes/time/time_core.tscn`.
Consumers: `CombatArena` (`scenes/prototype/arena.gd`), `CombatPlayer`
(`scenes/prototype/combat_player.tscn`), campaign, HUD and emergency view.
Focused checks: `time_core_n`, `combat_player_n`, `emergency_mode_n`, `time_controls_o`.

## Ownership
- **TimeController (Node)** is the ONLY owner of the time meter, emergency charges and
  the slow/rewind capability flags. Player, equipment, HUD, weapons and campaign read
  its properties and signals and call its methods. Nobody mirrors `meter`,
  `charges_remaining`, `slow_unlocked` or `rewind_unlocked`. There is no player health.
- **TimeSettings (Resource)** is the single source of time tuning. Edit
  `scripts/time/time_settings.tres` in the inspector. Code never writes it at runtime.
- **ReplayHistory (RefCounted)** stores value-only world snapshots. It never stores
  time, charges, capabilities, learned lessons or acquired tools.
- **EmergencyRewind (Node)** holds the recovery choice session. UI and world restore
  consume its signals; it has no visuals.

## Real time vs world time
- `advance(real_delta)` takes REAL seconds. Meter costs, recharge, slow drain, hit
  delay and recovery grace are all real seconds.
- `world_scale` turns a real delta into a WORLD delta: 1.0 normally, `slow_scale` while
  slowing, 0.0 during an emergency. Gameplay, enemies and `ReplayHistory.record` use
  world deltas.
- The history window (`history_seconds`) and its sample rate are WORLD seconds.
  Slowed play records proportionally less real time, and a frozen world records
  nothing.

## Meter rules
| Event | Effect |
| --- | --- |
| Hit `apply_hit(base)` | Spends `base * hit_multiplier` and restarts the recharge delay. Free during recovery grace. Ignored during an emergency or after exhaustion. |
| Slow (`slow_requested`) | Needs `slow_unlocked` and time left. A FRESH press (false→true) starts slow on the next `advance` with any time > 0. While the key stays held after the meter ran empty, slow resumes only at `slow_min_to_start` (no flicker). Releasing always stops slow. Drains `slow_drain_per_second` real seconds; `world_scale = slow_scale`. |
| Repair `try_spend_repair_checkpoint()` | Atomic: pays `repair_cost_per_checkpoint` and returns true, or changes nothing. Restore condition only on true. |
| Other voluntary `try_spend(amount)` | Atomic, same as repair. |
| Recharge | `recharge_per_second` per real second after `recharge_delay_after_hit`. Paused by: active slow, an active repair GESTURE (`set_repair_gesture_active(true)`), an emergency, exhaustion, or a native tree pause. An idle open repair panel must report `false`. |

Voluntary spending that reaches zero only stops slow and repair progress. It never
starts an emergency.

## Capabilities (campaign-owned run progress)
- `set_capabilities(slow: bool, rewind: bool)`; read `slow_unlocked` / `rewind_unlocked`;
  listen to `capabilities_changed(slow, rewind)`.
- Defaults are both true (sandbox, previews, isolated tools). The campaign sets them
  explicitly at the start of every run and unlocks them as lessons introduce them.
- Flags are never snapshotted, survive `begin_attempt()` and room retries, and are not
  changed by an emergency.
- `slow_unlocked == false`: holding slow_time does nothing (world_scale stays 1).
- `rewind_unlocked == false`: a depleting hit ends the attempt (`attempt_exhausted` →
  room retry) WITHOUT spending a charge or opening EmergencyRewind. The meter stays
  the visible survival bar; the HUD hides slow/rewind hints and charge pips until
  introduced.

## Depletion, charges, attempts
- **Depletion** = a hit (cost > 0) that leaves the meter at 0, including a hit when the
  meter is already 0 from voluntary spending.
- Rewind unlocked with a charge left: one charge is spent IMMEDIATELY
  (`charges_changed`, then `emergency_started(charges_remaining)`). `world_scale` is
  0 until `finish_emergency()`.
- No charge left, or rewind locked: `attempt_exhausted` fires once. The attempt then
  ignores further hits and recharge, and the campaign restarts the room
  (`begin_attempt()`).
- `begin_attempt()` = full meter + `charges_per_attempt` (3). It is the only refill. A
  retry is a new attempt, not a refund.
- Every recovery is identical: `meter = max(meter, recovery_floor)`, recharge delay
  cleared, `recovery_grace_seconds` of free hits. Successive emergencies never
  accumulate a penalty; the spent charge is the cost of a do-over.
- `force_depletion()` (scripted lesson) runs the same depletion path, ignores grace and
  spends a real charge. The campaign must unlock rewind before calling it.

## Weapon condition DOES rewind (decision, Round O)
Snapshots include weapon condition. A recovery restores condition exactly as recorded,
including completed repairs and wear after that moment. Time and charges stay live.
There is no permanent-wear or refund ledger.

## Emergency session
1. TimeController emits `emergency_started`. EmergencyRewind calls `capture_present`
   and `begin(present)`.
2. Choices: index 0 = NOW, then recorded moments newest first, or the seeded checkpoint
   when nothing is recorded (`choice_age == CHECKPOINT_AGE`). NOW always exists, so an
   empty buffer never softlocks.
3. `step_selection(+1)` selects the next older moment (wheel down / Up/Left arrows);
   `step_selection(-1)` goes newer; `select(i)` is direct. At 12 Hz one notch is
   about 0.083 world s, and the full 18 s window is 216 choices. Each change emits
   `selection_changed(index, age, state)` for a PREVIEW restore.
4. `confirm()` emits `confirmed(age, state)`. The consumer restores the world exactly to
   `state`. Newer history is discarded (a checkpoint choice clears history). Then the
   recovery floor and grace apply, and `ended` fires.
5. `abandon()` (scene exit) ends without restore or refund. `begin_attempt()` abandons
   automatically.

## Emergency mode ownership (GameState)
- `GameState.bind_emergency(rewind)`: EMERGENCY runs from `started` to `ended`. The tree
  is NOT paused; combat freezes through `world_scale == 0`.
- PAUSED covers PLAYING or EMERGENCY and resumes to whichever it covered. A retry or
  menu exit while paused ends the emergency once (`emergency_exited`).

## CombatPlayer (`scenes/prototype/combat_player.tscn`)
- Authored Camera3D, Model and Model/PlayerVisual. The Camera3D inspector settings
  (position, rotation, fov, projection) are authoritative. The arena only scales the
  camera's authored offset by its explicit `zoom` value; it never writes
  `Camera3D.size` or fov.
- `take_damage(amount) -> float` → `apply_hit`. `world_scale` and `can_act` are
  read-only getters. `step(real_delta, aim)` does nothing while frozen.
  `capture_state()` = {position, velocity, facing}.

## Arena (CombatArena) — actual wiring
```gdscript
# _setup_time_core(): one TimeCore instance, manual advance
time_controller.auto_advance = false
time_controller.set_physics_process(false)
history = ReplayHistory.from_settings(time_controller.settings)
emergency_rewind.history = history
emergency_rewind.capture_present = capture_state
GameState.bind_emergency(emergency_rewind)

# _physics_process(delta): the ONLY advance per tick
time_controller.slow_requested = _is_slow_held()   # Input.is_action_pressed(&"slow_time")
time_controller.advance(delta)                     # real seconds
var world_delta := delta * time_controller.world_scale
...director/weapons with world_delta...
history.record(world_delta, capture_state)         # skipped while frozen

# _input: slow_time press/release updates slow_requested immediately
# emergency: wheel/arrows -> step_selection(±1); LMB/Enter -> confirm()
```
- `slow_time` is authored in `project.godot` (physical Space). No runtime InputMap
  creation and no aliases. `_is_slow_held()` = last `_input` press/release OR the
  native action state; the press flag is re-read from `Input` on every pause, state
  and focus change, so a release missed while paused cannot stick.
- The repair panel is reached through `SceneManager.get_popup(&"Repair") as
  WeaponRepair` and its public `tool`, `switch_tool`, `show_message` and
  `has_active_session`.

## Campaign and HUD
- Campaign: on a NEW run call `time_controller.set_capabilities(false, false)`. Unlock
  slow when the slow lesson starts (`set_capabilities(true, false)`), then rewind
  before the scripted depletion (`set_capabilities(true, true)` → `force_depletion()`).
  Debug/checkpoint entry computes both flags from learned lessons. Keep handling
  `attempt_exhausted` → `retry_room()` (this covers locked-rewind depletion).
  Do not call `begin_attempt()` twice per entry (arena `reset_arena` already does).
- HUD: bind `capabilities_changed` (and read the flags on bind). Hide slow hints while
  `slow_unlocked` is false; hide charge pips and rewind text while `rewind_unlocked`
  is false. Always show the meter.
- Defaults (provisional): capacity 100, recharge 12/s after 1.5 s, slow 0.18x at 8/s
  (held resume ≥15), repair 6/checkpoint, 3 charges, floor 40, grace 1.5 s, history
  18 world s at 12 Hz (216 ≤ 240 cap, 64 KB per snapshot).
