class_name HeatBellowsSettings
extends Resource
## Shared read-only tuning. Edit the .tres in the inspector; actor state lives on components.

@export_range(0.001, 1000.0, 0.01) var range: float = 5.0
@export_range(0.001, 1000.0, 0.01) var half_angle: float = 0.65
@export_range(0.001, 1000.0, 0.01) var damage_per_second: float = 16.0
@export_range(0.001, 1000.0, 0.01) var pulse_interval: float = 1.2
@export_range(0.001, 1000.0, 0.01) var pulse_cost: float = 1.5
@export_range(0.001, 1000.0, 0.01) var pulse_impulse: float = 22.0
@export_range(0.001, 1000.0, 0.01) var pulse_stagger: float = 0.85
@export_range(0.001, 1000.0, 0.01) var sustained_push: float = 5.0
