extends Node3D

const Style = preload("res://scenes/prototype/tool_style.gd")
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


static func core_point(radius: float) -> Vector3:
	return Vector3(0, 0.82, -radius * 0.7)


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
		cable = pipe(self, points[0], points[1], 0.13, blue)
		if layout == &"side":
			box(self, Vector3(0.35, 0.9, 0.75), Vector3(radius + 0.45, 0.8, 0), metal)
	if mode in [&"shot", &"open"]:
		var point := core_point(radius)
		core = pipe(self, point, point + Vector3(0, 0.02, -0.08), 0.24, material(Style.BEAM, true))
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
	if is_instance_valid(plate): plate.rotation.x = -1.45 if exposed else 0.0
	heat_material.albedo_color = Style.CONE.lerp(Color("fff0ad"), clampf(heat_ratio, 0.0, 1.0))
