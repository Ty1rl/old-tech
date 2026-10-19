class_name CombatPartVisual
extends Node3D

const Style = preload("res://scenes/prototype/tool_style.gd")
var instruction_visible := false
var instruction: Label3D

var cable: MeshInstance3D
var core: MeshInstance3D
var plate: Node3D
var heat_material: StandardMaterial3D
var halves: Array[Node3D] = []


static func cable_points(layout: StringName, radius: float) -> Array[Vector3]:
	match layout:
		&"side": return [Vector3(0.15, 0.85, 0), Vector3(radius + 0.35, 0.85, 0)]
		&"front": return [Vector3(0, 1.3, -0.2), Vector3(0, 1.3, -radius - 0.3)]
		_: return [Vector3(-0.4, 0.85, 0), Vector3(0.4, 0.85, 0)]


static func core_point(_radius: float) -> Vector3:
	return Vector3(0, 1.75, 0)


func material(color: Color, glow: bool = false) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.65
	if glow:
		result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return result


func box(parent: Node3D, size: Vector3, point: Vector3, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = point
	node.material_override = mat
	parent.add_child(node)
	return node


func pipe(parent: Node3D, start: Vector3, finish: Vector3, radius: float, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = start.distance_to(finish)
	mesh.radial_segments = 24
	node.mesh = mesh
	node.position = (start + finish) * 0.5
	var axis := (finish - start).normalized()
	var reference := Vector3.FORWARD if absf(axis.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var right := axis.cross(reference).normalized()
	node.basis = Basis(right, axis, right.cross(axis))
	node.material_override = mat
	parent.add_child(node)
	return node


func build(mode: StringName, layout: StringName, radius: float, body: Material) -> void:
	instruction = Label3D.new()
	instruction.position = Vector3(0, 2.6, 0)
	instruction.font_size = 32
	instruction.pixel_size = .01
	instruction.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	instruction.no_depth_test = true
	instruction.visible = false
	add_child(instruction)
	var dark := material(Color("303c46"))
	var metal := material(Color("9ba6ac"))
	var blue := material(Style.RING, true)
	heat_material = material(Style.CONE, true)
	if mode == &"cut":
		for side in [-1.0, 1.0]:
			var half := Node3D.new()
			half.position.x = side * 0.58
			add_child(half)
			box(half, Vector3(0.45, 1.1, 0.9), Vector3(0, 0.68, 0), body)
			box(half, Vector3(0.48, 0.13, 0.95), Vector3(0, 1.2, 0), metal)
			halves.append(half)
	else:
		box(self, Vector3(radius * 1.6, 1.15, radius * 1.3), Vector3(0, 0.72, 0), body)
		box(self, Vector3(radius * 1.7, 0.14, radius * 1.4), Vector3(0, 1.33, 0), metal)
		for side in [-1.0, 1.0]:
			pipe(self, Vector3(side * radius * 0.65, 0.25, -0.25), Vector3(side * radius * 0.65, 0.25, 0.3), 0.22, dark)
	if mode in [&"cut", &"open"]:
		var points := cable_points(layout, radius)
		cable = pipe(self, points[0], points[1], 0.19, blue)
		if layout == &"side":
			box(self, Vector3(0.35, 0.9, 0.75), Vector3(radius + 0.45, 0.8, 0), metal)
	if mode in [&"shot", &"open"]:
		var point := core_point(radius)
		core = MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.3
		sphere.height = 0.6
		sphere.radial_segments = 24
		sphere.rings = 12
		core.mesh = sphere
		core.material_override = material(Style.BEAM, true)
		core.position = point
		add_child(core)
	if mode in [&"heat", &"open"]:
		plate = Node3D.new()
		plate.position = Vector3(0, 0.12, -radius - 0.25)
		add_child(plate)
		box(plate, Vector3(radius * 2.05, 1.0, 0.14), Vector3(0, 0.5, 0), heat_material)
		for side in [-1.0, 1.0]:
			pipe(plate, Vector3(side * radius * 0.7, 0, -0.03), Vector3(side * radius * 0.7, 0.2, -0.03), 0.07, dark)
	# Exaggerated, separated moving feet make facing and motion readable.
	for side in [-1.0, 1.0]:
		box(self, Vector3(0.27, 0.16, 0.55), Vector3(side * radius * 0.6, 0.08, 0), dark)


func sync(cut: bool, exposed: bool, broken: bool, heat_ratio: float) -> void:
	for index in range(halves.size()):
		halves[index].rotation.z = (0.3 if index == 0 else -0.3) if cut else 0.0
	if is_instance_valid(cable): cable.visible = not cut
	if is_instance_valid(core): core.visible = exposed and not broken
	if is_instance_valid(plate): plate.visible = not exposed
	_update_instruction(broken)
	heat_material.albedo_color = Style.CONE.lerp(Color("fff0ad"), clampf(heat_ratio, 0.0, 1.0))

func set_instruction_visible(value: bool) -> void:
	instruction_visible = value
	if is_instance_valid(instruction):
		instruction.visible = value and not instruction.text.is_empty()

func _update_instruction(broken: bool) -> void:
	if not is_instance_valid(instruction): return
	instruction.text = ""
	if broken:
		instruction.visible = false
		return
	if is_instance_valid(core) and core.visible:
		instruction.text = "Charge yellow"
		instruction.modulate = Style.BEAM
	elif is_instance_valid(plate) and plate.visible:
		instruction.text = "Heat orange"
		instruction.modulate = Style.CONE
		if is_instance_valid(cable) and cable.visible:
			instruction.text = "Cut blue / Heat orange"
			instruction.modulate = Style.REPAIR_GUIDE
	elif is_instance_valid(cable) and cable.visible:
		instruction.text = "Cut blue"
		instruction.modulate = Style.RING
	instruction.visible = instruction_visible and not instruction.text.is_empty()
