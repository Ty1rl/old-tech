class_name RepairToolSpec
extends Resource

## Inspector-editable specification for a weapon's 3D repair presentation,
## camera framing, named 3D part anchors, and 3-stage gesture operations.

@export var id: StringName = &"ring"
@export var title: String = "Ring Cutter"
@export var accent: Color = Color("67c9f5")
@export_file("*.glb") var glb: String = "res://assets/equipment/ring_caster.glb"
@export var cam_pos: Vector3 = Vector3(0.0, 1.45, 1.15)
@export var cam_target: Vector3 = Vector3(0.0, 0.0, 0.0)
@export_range(0.25, 2.0, 0.01) var cam_size: float = 0.72
@export var model_pos: Vector3 = Vector3(-0.08, -0.02, -0.02)
@export var model_rot_deg: Vector3 = Vector3(14.0, -132.0, 4.0)
@export var open_cover_and_grille: bool = false
@export var spin_part_pivots: Dictionary = {}
@export var operations: Array[Dictionary] = []
