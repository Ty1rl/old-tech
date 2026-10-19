extends Node3D
## Weapon-only bench actor. Real player motion/time integration belongs to CombatPlayer.
@onready var visual: Node3D = $Model/PlayerVisual
@onready var camera: Camera3D = $Camera3D
func _ready() -> void:
	visual.build()
	visual.scale = Vector3.ONE * 1.3
	visual.set_tool_index(1)
func aim_at(point: Vector3, tool: int, world_delta: float) -> void:
	var direction := point - global_position
	direction.y = 0
	if direction.length_squared() > .001: visual.basis = Basis.looking_at(direction)
	visual.set_tool_index(tool)
	visual.step_visual(world_delta, 0, 6, Vector3.ZERO)
