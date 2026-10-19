class_name TimeSettings
extends Resource
## Inspector-editable tuning for the shared time meter, slow, repair cost,
## emergency recovery and replay history. One resource is the single source of
## these numbers; TimeController only reads it and never writes to it at runtime.
## Values are provisional starting points, not balance law.

@export_group("Meter")
## Full meter in time units. Hits, slow and repair all spend from this pool.
@export_range(1.0, 1000.0, 1.0) var capacity: float = 100.0
## Units restored per REAL second while recharge is allowed.
@export_range(0.0, 200.0, 0.5) var recharge_per_second: float = 12.0
## Real seconds after a hit before recharge resumes.
@export_range(0.0, 10.0, 0.05) var recharge_delay_after_hit: float = 1.5

@export_group("Hits")
## A hit costs its caller-supplied base amount times this multiplier.
@export_range(0.0, 10.0, 0.05) var hit_multiplier: float = 1.0

@export_group("Slow")
## World time scale while slow is active (Space held with time available).
@export_range(0.01, 1.0, 0.01) var slow_scale: float = 0.18
## Units drained per REAL second while slow is active.
@export_range(0.0, 100.0, 0.5) var slow_drain_per_second: float = 8.0
## A fresh slow_time press starts slow with any time left. While the key stays
## held after the meter ran empty, slow only resumes at or above this value, so a
## held key does not flicker on every recharge tick.
@export_range(0.0, 100.0, 0.5) var slow_min_to_start: float = 15.0

@export_group("Repair")
## Paid atomically before each completed repair checkpoint restores condition.
@export_range(0.0, 100.0, 0.5) var repair_cost_per_checkpoint: float = 6.0

@export_group("Emergency")
## Emergency recoveries available per room attempt.
@export_range(0, 9, 1) var charges_per_attempt: int = 3
## After confirming a recovery the meter is raised to at least this value.
@export_range(0.0, 1000.0, 1.0) var recovery_floor: float = 40.0
## Real seconds after a recovery during which hits cost nothing.
@export_range(0.0, 10.0, 0.05) var recovery_grace_seconds: float = 1.5
## World seconds stepped per mouse-wheel or arrow notch during emergency rewind.
@export_range(0.1, 5.0, 0.1) var scrub_step_seconds: float = 1.0

@export_group("Replay history")
## Bounded window of recorded snapshots, in WORLD seconds (slowed time records
## proportionally less real time; a frozen world records nothing).
@export_range(1.0, 30.0, 0.5) var history_seconds: float = 18.0
## Snapshots per WORLD second. Restores land exactly on a snapshot; the display
## eases between previewed moments.
@export_range(1.0, 60.0, 1.0) var history_sample_rate: float = 12.0
## Hard memory cap on stored snapshots regardless of window/rate
## (18 s x 12 Hz = 216 fits under 240).
@export_range(1, 600, 1) var history_max_snapshots: int = 240
