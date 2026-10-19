class_name RepairSidePreview
extends Control
## One owned neighbor, one bounded viewport. No selected/central model here.
const MODELS := {
	&"ring": preload("res://assets/equipment/ring_caster.glb"),
	&"beam": preload("res://assets/equipment/flash_camera.glb"),
	&"cone": preload("res://assets/equipment/heat_bellows.glb")}
@onready var viewport: SubViewport = %PreviewViewport
@onready var pivot: Node3D = %Pivot
@onready var condition: RepairConditionView = %Condition
@onready var hit_area: Button = %HitArea
var tool: StringName = &""
var model: Node3D
var _models: Dictionary[StringName, Node3D] = {}

func bind_equipment(gear: WeaponEquipment, selected_tool: StringName) -> void:
	condition.bind_equipment(gear, selected_tool)
	if selected_tool == tool: return
	tool = selected_tool
	hit_area.tooltip_text = "Select " + String(tool)
	if is_instance_valid(model):
		model.hide()
	if tool not in MODELS:
		model = null
		return
	if _models.has(tool):
		model = _models[tool]
		model.show()
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		return
	model = MODELS[tool].instantiate()
	pivot.add_child(model)
	_models[tool] = model
	var bounds := AABB()
	var first := true
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = (model.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
		# Keep source geometry/materials immutable. A shallow mesh copy carries
		# per-preview surface materials without mesh-instance override uniforms.
		mesh.mesh = mesh.mesh.duplicate()
		for surface in range(mesh.mesh.get_surface_count()):
			var material := mesh.get_active_material(surface) as StandardMaterial3D
			if material != null:
				var local: StandardMaterial3D = material.duplicate()
				local.resource_local_to_scene = true
				mesh.mesh.surface_set_material(surface, local)
	for animation: AnimationPlayer in model.find_children("*", "AnimationPlayer", true, false): animation.active = false
	var factor := 1.15 / maxf(.001, maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z)))
	model.scale = Vector3.ONE * factor
	model.position = -bounds.get_center() * factor
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func fit(rect: Rect2) -> void:
	position = rect.position
	size = rect.size
	pivot_offset = size * .5
	# The ring lies outside the image; viewport/model is the smaller inner item.
	condition.position = size * .19
	condition.size = size * .62
