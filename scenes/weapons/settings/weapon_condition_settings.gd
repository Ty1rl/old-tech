class_name WeaponConditionSettings
extends Resource
## Shared read-only tuning. Edit the .tres in the inspector; actor state lives on components.

@export_range(0.001, 1000.0, 0.01) var ring_capacity: float = 24.0
@export_range(0.001, 1000.0, 0.01) var beam_capacity: float = 64.0
@export_range(0.001, 1000.0, 0.01) var cone_capacity: float = 24.0
@export_range(1, 8, 1) var repair_steps: int = 4
