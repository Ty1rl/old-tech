extends Node3D

# Procedural chunky PSX-style articulated humanoid for the prototype player.
# Built once under player.model; animated only by explicit real-delta step calls.
const ToolStyle = preload("res://scenes/prototype/tool_style.gd")
const TOOL_IDS: Array[StringName] = [&"ring", &"beam", &"cone", &"clock"]

var body_pivot: Node3D
var head_pivot: Node3D
var head: MeshInstance3D
var visor: MeshInstance3D
var torso: MeshInstance3D
var shoulders: Node3D
var left_shoulder: MeshInstance3D
var right_shoulder: MeshInstance3D
var backpack: Node3D
var left_arm_pivot: Node3D
var right_arm_pivot: Node3D
var left_leg_pivot: Node3D
var right_leg_pivot: Node3D
var left_boot: MeshInstance3D
var right_boot: MeshInstance3D
var boots: Array[MeshInstance3D] = []
var held_tool: Node3D
var tool_attachments: Dictionary = {}

var coat_material: StandardMaterial3D
var trim_material: StandardMaterial3D
var dark_material: StandardMaterial3D
var head_material: StandardMaterial3D
var copper_material: StandardMaterial3D
var tool_material: StandardMaterial3D

var tool_index: int = 1
var tool_id: StringName = &"ring"
var walk_phase: float = 0.0
var idle_phase: float = 0.0
var stride_blend: float = 0.0
var _built := false


func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	build()


func _material(color: Color, unshaded: bool = false, metallic: float = 0.25, roughness: float = 0.72) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic if not unshaded else 0.0
	mat.roughness = roughness
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, node_name: String = "") -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add_mesh(parent, mesh, pos, mat, node_name)


func _cylinder(parent: Node3D, top_r: float, bottom_r: float, height: float, pos: Vector3, mat: Material, segments: int = 10, node_name: String = "") -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_r
	mesh.bottom_radius = bottom_r
	mesh.height = height
	mesh.radial_segments = segments
	return _add_mesh(parent, mesh, pos, mat, node_name)


func _add_mesh(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material, node_name: String = "") -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	if not node_name.is_empty():
		instance.name = node_name
	instance.mesh = mesh
	instance.position = pos
	instance.material_override = mat
	parent.add_child(instance)
	return instance


func build() -> void:
	if _built:
		return
	_built = true
	name = "PlayerVisual"
	# player.model is at y = 0.5 in player-local space; offset to y = -0.5 so
	# visual y = 0.0 rests directly on the floor plane.
	position = Vector3(0.0, -0.5, 0.0)

	coat_material = _material(Color("b9b199"), false, 0.15, 0.78)
	trim_material = _material(Color("6f7f8a"), false, 0.45, 0.58)
	dark_material = _material(Color("222b34"), false, 0.35, 0.65)
	head_material = _material(Color("d8ccb8"), false, 0.15, 0.70)
	copper_material = _material(Color("b8764d"), false, 0.55, 0.48)
	tool_material = _material(ToolStyle.RING, true)

	# Articulated leg pivots and chunky boots (pointing -Z forward)
	left_leg_pivot = Node3D.new()
	left_leg_pivot.name = "LeftLegPivot"
	left_leg_pivot.position = Vector3(-0.15, 0.50, 0.0)
	add_child(left_leg_pivot)
	_box(left_leg_pivot, Vector3(0.17, 0.30, 0.18), Vector3(0.0, -0.17, 0.0), trim_material, "LeftLeg")
	left_boot = _box(left_leg_pivot, Vector3(0.21, 0.18, 0.31), Vector3(0.0, -0.41, -0.05), dark_material, "LeftBoot")

	right_leg_pivot = Node3D.new()
	right_leg_pivot.name = "RightLegPivot"
	right_leg_pivot.position = Vector3(0.15, 0.50, 0.0)
	add_child(right_leg_pivot)
	_box(right_leg_pivot, Vector3(0.17, 0.30, 0.18), Vector3(0.0, -0.17, 0.0), trim_material, "RightLeg")
	right_boot = _box(right_leg_pivot, Vector3(0.21, 0.18, 0.31), Vector3(0.0, -0.41, -0.05), dark_material, "RightBoot")
	boots = [left_boot, right_boot]

	# Upper body pivot (pelvis/torso/shoulders/head/backpack/arms)
	body_pivot = Node3D.new()
	body_pivot.name = "BodyPivot"
	body_pivot.position = Vector3(0.0, 0.52, 0.0)
	add_child(body_pivot)

	torso = _box(body_pivot, Vector3(0.50, 0.50, 0.32), Vector3(0.0, 0.25, 0.0), coat_material, "Torso")

	shoulders = Node3D.new()
	shoulders.name = "Shoulders"
	shoulders.position = Vector3(0.0, 0.42, 0.0)
	body_pivot.add_child(shoulders)
	left_shoulder = _box(shoulders, Vector3(0.22, 0.16, 0.36), Vector3(-0.33, 0.0, 0.0), trim_material, "LeftShoulder")
	right_shoulder = _box(shoulders, Vector3(0.22, 0.16, 0.36), Vector3(0.33, 0.0, 0.0), trim_material, "RightShoulder")

	head_pivot = Node3D.new()
	head_pivot.name = "HeadPivot"
	head_pivot.position = Vector3(0.0, 0.50, -0.02)
	body_pivot.add_child(head_pivot)
	head = _box(head_pivot, Vector3(0.35, 0.33, 0.35), Vector3(0.0, 0.17, 0.0), head_material, "Head")
	visor = _box(head_pivot, Vector3(0.31, 0.11, 0.10), Vector3(0.0, 0.19, -0.16), dark_material, "Visor")

	# Backpack on the +Z back of the torso
	backpack = Node3D.new()
	backpack.name = "Backpack"
	backpack.position = Vector3(0.0, 0.25, 0.25)
	body_pivot.add_child(backpack)
	_box(backpack, Vector3(0.38, 0.40, 0.20), Vector3(0.0, 0.0, 0.0), dark_material, "BackpackFrame")
	_cylinder(backpack, 0.09, 0.09, 0.32, Vector3(-0.08, 0.04, 0.08), copper_material, 8, "BackpackCell")

	# Left arm
	left_arm_pivot = Node3D.new()
	left_arm_pivot.name = "LeftArmPivot"
	left_arm_pivot.position = Vector3(-0.34, 0.38, 0.0)
	body_pivot.add_child(left_arm_pivot)
	_box(left_arm_pivot, Vector3(0.16, 0.36, 0.18), Vector3(0.0, -0.15, -0.03), coat_material, "LeftArm")
	_box(left_arm_pivot, Vector3(0.17, 0.13, 0.19), Vector3(0.0, -0.32, -0.05), dark_material, "LeftGlove")

	# Right arm + forward held tool mount
	right_arm_pivot = Node3D.new()
	right_arm_pivot.name = "RightArmPivot"
	right_arm_pivot.position = Vector3(0.34, 0.38, 0.0)
	body_pivot.add_child(right_arm_pivot)
	_box(right_arm_pivot, Vector3(0.16, 0.32, 0.22), Vector3(0.0, -0.12, -0.10), coat_material, "RightArm")
	_box(right_arm_pivot, Vector3(0.18, 0.14, 0.22), Vector3(0.0, -0.22, -0.22), dark_material, "RightGlove")

	held_tool = Node3D.new()
	held_tool.name = "HeldTool"
	held_tool.position = Vector3(0.02, -0.20, -0.42)
	right_arm_pivot.add_child(held_tool)
	_box(held_tool, Vector3(0.14, 0.14, 0.26), Vector3(0.0, 0.0, 0.04), copper_material, "ToolStock")

	# 1. Ring launcher attachment (horizontal cyan disc/ring in front of hand)
	var ring_node := Node3D.new()
	ring_node.name = "ToolRing"
	held_tool.add_child(ring_node)
	_cylinder(ring_node, 0.23, 0.23, 0.06, Vector3(0.0, 0.02, -0.14), tool_material, 12, "RingDisc")
	_cylinder(ring_node, 0.10, 0.10, 0.08, Vector3(0.0, 0.02, -0.14), dark_material, 10, "RingHub")
	tool_attachments[&"ring"] = ring_node

	# 2. Flash (beam) lance attachment (extended yellow barrel along -Z)
	var beam_node := Node3D.new()
	beam_node.name = "ToolBeam"
	held_tool.add_child(beam_node)
	var barrel := _cylinder(beam_node, 0.065, 0.08, 0.44, Vector3(0.0, 0.02, -0.22), tool_material, 8, "BeamBarrel")
	barrel.rotation.x = PI * 0.5
	_box(beam_node, Vector3(0.18, 0.12, 0.14), Vector3(0.0, 0.02, -0.08), trim_material, "BeamCoil")
	tool_attachments[&"beam"] = beam_node

	# 3. Coneprojector attachment (wide flared orange emitter nozzle)
	var cone_node := Node3D.new()
	cone_node.name = "ToolCone"
	held_tool.add_child(cone_node)
	var horn := _cylinder(cone_node, 0.21, 0.08, 0.30, Vector3(0.0, 0.02, -0.16), tool_material, 10, "ConeHorn")
	horn.rotation.x = PI * 0.5
	tool_attachments[&"cone"] = cone_node

	# 4. Clock device attachment (violet twin-frame chronometer lantern)
	var clock_node := Node3D.new()
	clock_node.name = "ToolClock"
	held_tool.add_child(clock_node)
	_cylinder(clock_node, 0.17, 0.17, 0.14, Vector3(0.0, 0.03, -0.12), tool_material, 10, "ClockDial")
	_box(clock_node, Vector3(0.24, 0.05, 0.24), Vector3(0.0, 0.11, -0.12), copper_material, "ClockFrame")
	tool_attachments[&"clock"] = clock_node

	set_tool_index(tool_index)
	reset_pose()


func set_tool_index(index: int) -> void:
	build()
	tool_index = clampi(index, 1, TOOL_IDS.size())
	tool_id = TOOL_IDS[tool_index - 1]
	tool_material.albedo_color = ToolStyle.color_for(tool_id)
	for id: StringName in tool_attachments:
		var node: Node3D = tool_attachments[id]
		node.visible = (id == tool_id)


func reset_pose() -> void:
	build()
	walk_phase = 0.0
	idle_phase = 0.0
	stride_blend = 0.0
	_apply_pose()


func step_visual(real_delta: float, planar_speed: float, max_speed: float = 6.0) -> void:
	build()
	if real_delta <= 0.0:
		return
	var dt := minf(real_delta, 0.25)
	var move_ratio := clampf(planar_speed / maxf(0.001, max_speed), 0.0, 1.0)
	if move_ratio > 0.02:
		walk_phase = wrapf(walk_phase + dt * lerpf(4.5, 11.0, move_ratio), 0.0, TAU)
		stride_blend = move_toward(stride_blend, move_ratio, dt * 10.0)
	else:
		idle_phase = wrapf(idle_phase + dt * 2.4, 0.0, TAU)
		stride_blend = move_toward(stride_blend, 0.0, dt * 8.0)
	_apply_pose()


func _apply_pose() -> void:
	var idle_weight := 1.0 - stride_blend
	var swing := sin(walk_phase) * 0.62 * stride_blend
	left_leg_pivot.rotation = Vector3(swing, 0.0, 0.0)
	right_leg_pivot.rotation = Vector3(-swing, 0.0, 0.0)
	left_arm_pivot.rotation = Vector3(-swing * 0.70 + sin(idle_phase) * 0.04 * idle_weight, 0.0, 0.0)
	right_arm_pivot.rotation = Vector3(swing * 0.30 + sin(idle_phase + 0.7) * 0.03 * idle_weight, 0.0, 0.0)
	var bob := absf(sin(walk_phase)) * 0.055 * stride_blend + sin(idle_phase) * 0.018 * idle_weight
	body_pivot.position = Vector3(0.0, 0.52 + bob, 0.0)
	body_pivot.rotation = Vector3(-0.09 * stride_blend, 0.0, -cos(walk_phase) * 0.04 * stride_blend)
	head_pivot.rotation = Vector3(0.04 * stride_blend, sin(idle_phase * 0.5) * 0.04 * idle_weight, 0.0)
