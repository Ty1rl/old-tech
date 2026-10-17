extends Node3D

# Geometry is built once; mechanism state only moves hinges and changes materials.
const Style = preload("res://scenes/prototype/tool_style.gd")
var shield_hinges: Array[Node3D] = []
var cable_spans: Array[MeshInstance3D] = []
var core: MeshInstance3D
var vent_material: StandardMaterial3D
var cable_material: StandardMaterial3D


func _material(color: Color, glow: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.55 if not glow else 0.1
	mat.roughness = 0.5
	if glow:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add_mesh(parent, mesh, pos, mat)


func _cylinder(parent: Node3D, r: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = r
	mesh.bottom_radius = r
	mesh.height = height
	mesh.radial_segments = 24
	return _add_mesh(parent, mesh, pos, mat)


func _add_mesh(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = pos
	instance.material_override = mat
	parent.add_child(instance)
	return instance


func _pipe(a: Vector3, b: Vector3, r: float, mat: Material) -> MeshInstance3D:
	var part := _cylinder(self, r, a.distance_to(b), (a + b) * 0.5, mat)
	var axis := (b - a).normalized()
	var helper := Vector3.FORWARD if absf(axis.dot(Vector3.UP)) > 0.95 else Vector3.UP
	var side := helper.cross(axis).normalized()
	part.basis = Basis(side, axis, side.cross(axis).normalized())
	return part


func build(r: float) -> void:
	var dark := _material(Color("28353f"))
	var steel := _material(Color("94a7ad"))
	var copper := _material(Color("b8764d"))
	var shield_mat := _material(Style.CONE.darkened(0.22))
	vent_material = _material(Style.CONE, true)
	cable_material = _material(Style.RING, true)
	var yellow := _material(Style.BEAM, true)
	# Wide feet, hip joints, twin hydraulic legs, and a ribbed shoulder frame.
	for side: float in [-1.0, 1.0]:
		_box(self, Vector3(0.62, 0.18, 0.95), Vector3(side * 0.65, 0.12, 0.05), dark)
		_cylinder(self, 0.21, 0.68, Vector3(side * 0.64, 0.5, 0.0), steel)
		_cylinder(self, 0.12, 0.47, Vector3(side * 0.84, 0.52, -0.19), copper)
		var hip := _cylinder(self, 0.25, 0.26, Vector3(side * 0.67, 0.85, 0.0), dark)
		hip.rotation.z = PI * 0.5
		_box(self, Vector3(0.22, 0.18, 1.45), Vector3(side * 0.72, 1.61, 0.0), steel)
		var hinge := Node3D.new()
		hinge.position = Vector3(side * 0.84, 1.03, -0.83)
		add_child(hinge)
		shield_hinges.append(hinge)
		_box(hinge, Vector3(0.82, 1.16, 0.18), Vector3(-side * 0.4, 0.0, 0.0), shield_mat)
		_box(hinge, Vector3(0.12, 1.2, 0.22), Vector3(0.0, 0.0, 0.0), steel)
		for bolt_y: float in [-0.42, 0.42]:
			var bolt := _cylinder(hinge, 0.067, 0.075, Vector3(-side * 0.64, bolt_y, -0.14), dark)
			bolt.rotation.x = PI * 0.5
		# Distinct horizontal orange slats mark the heat vents on either shoulder.
		for n in range(4):
			_box(self, Vector3(0.12, 0.07, 0.52), Vector3(side * 0.95, 1.05 + n * 0.14, 0.12), vent_material)
	_box(self, Vector3(1.25, 0.18, 1.36), Vector3(0.0, 1.72, 0.0), dark)
	_box(self, Vector3(0.58, 0.34, 0.57), Vector3(0.0, 1.97, -0.12), steel)
	_box(self, Vector3(0.36, 0.07, 0.06), Vector3(0.0, 2.0, -0.42), vent_material)
	# A circular yellow core is hidden physically behind the split shield.
	var socket := _cylinder(self, 0.40, 0.16, Vector3(0.0, 1.05, -0.65), dark)
	socket.rotation.x = PI * 0.5
	core = _cylinder(self, 0.28, 0.19, Vector3(0.0, 1.05, -0.74), yellow)
	core.rotation.x = PI * 0.5
	# Cyan U-shaped external cable matches the actual swept hit test in enemy.gd.
	var points: Array[Vector3] = [Vector3(r * 0.9, 1.22, -0.48), Vector3(r + 0.38, 1.22, -0.48), Vector3(r + 0.38, 1.22, 0.48), Vector3(r * 0.9, 1.22, 0.48)]
	for i in range(points.size() - 1):
		cable_spans.append(_pipe(points[i], points[i + 1], 0.075, cable_material))
	for z: float in [-0.48, 0.48]:
		var coupling := _cylinder(self, 0.13, 0.22, Vector3(r * 0.9, 1.22, z), copper)
		coupling.rotation.z = PI * 0.5


func sync(cut: bool, exposed: bool, core_broken: bool, heat_ratio: float) -> void:
	for i in range(shield_hinges.size()):
		shield_hinges[i].rotation.y = (-1.0 if i == 0 else 1.0) * (1.30 if exposed else 0.0)
	for span in cable_spans:
		span.visible = not cut
	if is_instance_valid(core):
		core.visible = exposed
		core.scale = Vector3.ONE * (0.55 if core_broken else 1.0)
	vent_material.albedo_color = Style.CONE.lerp(Color("fff0bd"), clampf(heat_ratio, 0.0, 1.0))
