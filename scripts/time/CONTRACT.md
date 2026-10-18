# Time core contract (Round N Wave1, frozen for Wave2 consumers)

Files: `scripts/time/` (TimeSettings, TimeController, ReplayHistory, EmergencyRewind,
`time_settings.tres`) and the editor composition `scenes/time/time_core.tscn`.
Focused checks: `scenes/prototype/checks/time_core_n.gd`.

## Ownership
- **TimeController (Node)** is the ONLY owner of the time meter and emergency charges.
  Player, Equipment, HUD, weapons and campaign read its properties/signals and call
  its methods. Nobody mirrors `meter` or `charges_remaining`; there is no player health.
- **TimeSettings (Resource)** is the single source of time tuning. Edit
  `scripts/time/time_settings.tres` in the inspector. Code never writes to it at runtime;
  use a separate resource (or `duplicate()`) for experiments.
- **ReplayHistory (RefCounted)** stores value-only world snapshots. It never stores
  TimeController state, charges, learned lessons or acquired tools.
- **EmergencyRewind (Node)** holds the recovery choice session. UI and world restore are
  consumers of its signals; it has no visuals.

## Meter rules
| Event | Effect |
| --- | --- |
| Hit `apply_hit(base)` | Spends `base * hit_multiplier`, restarts the recharge delay. Free during recovery grace. Ignored while an emergency is active or the attempt is exhausted. |
| Slow (`slow_requested = true`) | Active only with time left; starts at or above `slow_min_to_start`, then runs to zero. Drains `slow_drain_per_second` real seconds. `world_scale = slow_scale`. |
| Repair `try_spend_repair_checkpoint()` | Atomic: pays `repair_cost_per_checkpoint` and returns true, or changes nothing. Restore condition only on true. |
| Other voluntary `try_spend(amount)` | Atomic, same as repair. |
| Recharge | `recharge_per_second` per REAL second, after `recharge_delay_after_hit`. Paused by: active slow, an active repair GESTURE (`set_repair_gesture_active(true)`), an emergency, exhaustion, or a native tree pause. An idle open repair panel must report `false`. |

Voluntary spending that reaches zero only stops slow and repair progress. It never
starts an emergency.

## Depletion, charges, attempts
- **Depletion** = a hit (cost > 0) that leaves the meter at 0, including a hit when the
  meter is already 0 from voluntary spending.
- With a charge left: one charge is spent IMMEDIATELY (`charges_changed`, then
  `emergency_started(charges_remaining)`). `world_scale` becomes 0 (world frozen)
  until `finish_emergency()`.
- With no charge left: `attempt_exhausted` fires once, and the attempt ignores further
  hits and recharge. The campaign then restarts the room and calls `begin_attempt()`.
- `begin_attempt()` = full meter + `charges_per_attempt` (3). Call it on room entry and
  on every explicit retry. A retry is a new attempt, not a refund. Learned lessons and
  tools persist outside the controller.
- Nothing in TimeController is captured in snapshots, so rewinding cannot refund
  time or charges.

## Emergency session
1. TimeController emits `emergency_started`. EmergencyRewind calls its
   `capture_present` Callable and `begin(present)`. A consumer may also call `begin()`
   directly if it owns the capture.
2. Choices: index 0 = NOW. Then recorded moments, newest first. When no moment is
   recorded and a checkpoint was seeded, the last choice is the checkpoint
   (`choice_age == CHECKPOINT_AGE`). NOW always exists, so an empty buffer never
   softlocks.
3. `step_selection(+1)` goes older (wheel down); `select(i)` is direct. Each change emits
   `selection_changed(index, age, state)` for a preview restore. A preview never touches
   run state or charges.
4. `confirm()` emits `confirmed(age, state)`. The consumer restores the world to
   `state`. History newer than the choice is discarded (a checkpoint clears the
   history). Then TimeController applies `meter = max(meter, recovery_floor)` and
   `recovery_grace_seconds` of free hits, and `ended` fires.
5. `abandon()` (scene exit) ends the session without a restore or refund. A room retry
   only needs `begin_attempt()`: EmergencyRewind listens to `attempt_started` and
   abandons by itself. The `time_controller` export wires these signals through its
   setter, whether the scene assigns it or code does.

## Integration notes for Wave2
- Feed `ReplayHistory.record(real_delta * world_scale, capture)`, so sampling stops while
  frozen. Build it with `ReplayHistory.from_settings(settings)`. Seed the room-start
  checkpoint with `seed_checkpoint()`. Turn on `validate_snapshots` in checks only.
- Multiply world deltas by `TimeController.world_scale`. Do not change Engine.time_scale.
  Menus and gesture input keep using real time.
- TimeController advances itself in `_physics_process` with
  `process_physics_priority = -100` (before gameplay). Set `auto_advance = false` to
  drive `advance()` manually. EmergencyRewind is `PROCESS_MODE_ALWAYS`; the world
  owner decides whether the tree is also paused during an emergency.
- Input owner sets `slow_requested` from the held InputMap action. There is no
  release/re-arm state.
- Defaults are provisional starting values in `time_settings.tres`: capacity 100,
  recharge 12/s after 1.5 s, slow 0.18x at 8/s (start ≥15), repair 6/checkpoint,
  3 charges, recovery floor 40, grace 1.5 s, history 12 s at 20 Hz (≤240).
