class_name RingCutterSettings
extends Resource
## Shared read-only tuning. Edit the .tres in the inspector; actor state lives on components.

@export_range(0.001, 1000.0, 0.01) var range: float = 14.0
@export_range(0.001, 1000.0, 0.01) var length: float = 22.0
@export_range(0.001, 1000.0, 0.01) var minimum_length: float = 0.6
@export_range(0.001, 1000.0, 0.01) var sample_spacing: float = 0.18
@export_range(0.001, 1000.0, 0.01) var outbound_speed: float = 24.0
@export_range(0.001, 1000.0, 0.01) var stroke_speed: float = 38.0
@export_range(0.001, 1000.0, 0.01) var return_speed: float = 28.0
@export_range(0.001, 1000.0, 0.01) var radius: float = 0.4
@export_range(0.001, 1000.0, 0.01) var damage: float = 36.0
@export_range(0.001, 1000.0, 0.01) var arc_height: float = 3.2
@export_range(1, 256, 1) var max_samples: int = 256
@export var display_smoothing: bool = true
