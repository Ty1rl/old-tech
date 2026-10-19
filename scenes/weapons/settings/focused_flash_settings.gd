class_name FocusedFlashSettings
extends Resource
## Shared read-only tuning. Edit the .tres in the inspector; actor state lives on components.

@export_range(0.001, 1000.0, 0.01) var range: float = 35.0
@export_range(0.001, 1000.0, 0.01) var radius: float = 0.35
@export_range(0.001, 1000.0, 0.01) var min_damage: float = 30.0
@export_range(0.001, 1000.0, 0.01) var max_damage: float = 100.0
@export_range(0.001, 1000.0, 0.01) var charge_time: float = 0.9
@export_range(0.001, 1000.0, 0.01) var speed: float = 42.0
@export_range(0.001, 1000.0, 0.01) var cooldown: float = 0.25
@export_range(1, 8, 1) var max_pulses: int = 8
@export_range(0.0, 1.0, 0.01) var pierce_threshold: float = 0.9
