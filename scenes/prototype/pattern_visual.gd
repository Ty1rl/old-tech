extends Node3D
# All interactive geometry is built from these same local query anchors.
const BLUE := Color("168eff")
const ORANGE := Color("f58024")
const YELLOW := Color("ffe538")
const STONE := Color("92918b")
var lit_valve: StandardMaterial3D
var dim_valve: StandardMaterial3D
var links: Array[MeshInstance3D] = []
var link_labels: Array[Label3D] = []
var plates: Array[MeshInstance3D] = []
var sections: Array[Node3D] = []
var valves: Array[MeshInstance3D] = []
var core: MeshInstance3D
var countdown: Label3D
var warning: MeshInstance3D
var feet: Array[MeshInstance3D] = []
var pattern: StringName
var boss := false

static func spans(mode: StringName) -> Array:
	if mode == &"loop":
		return [[Vector3(-0.65, 0.7, -0.65), Vector3(-1.8, 0.7, -1.8)],
			[Vector3(0.65, 0.7, -0.65), Vector3(1.8, 0.7, -1.8)],
			[Vector3(0.65, 0.7, 0.65), Vector3(1.8, 0.7, 1.8)],
			[Vector3(-0.65, 0.7, 0.65), Vector3(-1.8, 0.7, 1.8)]]
	if mode == &"zigzag":
		return [[Vector3(-2.0, 0.7, -1.25), Vector3(-1.2, 0.7, -0.75)],
			[Vector3(1.2, 0.7, -0.25), Vector3(2.0, 0.7, 0.25)],
			[Vector3(-2.0, 0.7, 0.75), Vector3(-1.2, 0.7, 1.25)]]
	return []

static func core_anchor(is_boss := false) -> Vector3:
	return Vector3(0, 1.45, -1.3 if is_boss else -0.95)

static func valve_anchor(index: int, is_boss := false) -> Vector3:
	return Vector3(-0.67 if index == 0 else 0.67, 1.6, -1.4 if is_boss else -0.95)

func mat(color: Color, unlit := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	if unlit: m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

func box(parent: Node3D, center: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = center
	node.material_override = mat(color)
	parent.add_child(node)
	return node

func ball(parent: Node3D, center: Vector3, size: float, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = size
	mesh.height = size * 2
	mesh.radial_segments = 12
	mesh.rings = 6
	node.mesh = mesh
	node.position = center
	node.material_override = mat(color, true)
	parent.add_child(node)
	return node

func rod(parent: Node3D, a: Vector3, b: Vector3, thickness: float, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = thickness
	mesh.bottom_radius = thickness
	mesh.height = a.distance_to(b)
	mesh.radial_segments = 10
	node.mesh = mesh
	node.material_override = mat(color, true)
	parent.add_child(node)
	node.position = (a + b) * 0.5
	node.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
	return node

func build(mode: StringName, is_boss: bool) -> void:
	lit_valve = mat(YELLOW,true)
	dim_valve = mat(Color("343b41"),true)
	pattern = mode
	boss = is_boss
	# Heavy feet, ribbed burial-machine body, small stone head; no new art assets.
	for x in [-0.63, 0.63]:
		feet.append(box(self, Vector3(x, 0.22, 0.15), Vector3(0.55, 0.44, 1.1), STONE.darkened(0.25)))
	for y in [0.65, 1.0, 1.35]:
		box(self, Vector3(0, y, 0), Vector3(1.45, 0.29, 1.12), STONE)
	box(self, Vector3(0, 1.95, 0), Vector3(0.58, 0.64, 0.6), STONE)
	for x in [-0.9, 0.9]:
		box(self, Vector3(x, 0.7, -0.3), Vector3(0.34, 1.05, 0.44), STONE.darkened(0.12))
		plates.append(box(self, Vector3(x, 1.15, -0.4), Vector3(0.48, 0.5, 0.5), ORANGE))
	plates.append(box(self, core_anchor(boss), Vector3(1.1, 0.82, 0.18), ORANGE))
	core = ball(self, core_anchor(boss), 0.31, YELLOW)
	for i in range(2):
		valves.append(ball(self, valve_anchor(i, boss), 0.27, YELLOW))
		var letter := Label3D.new()
		letter.text = "A" if i == 0 else "B"
		letter.position = valve_anchor(i, boss) + Vector3(0, 0.46, 0)
		letter.font_size = 38
		letter.pixel_size = 0.012
		letter.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		letter.visible = mode == &"pair"
		add_child(letter)
	for span: Array in spans(mode):
		links.append(rod(self, span[0], span[1], 0.16, BLUE))
		var number := Label3D.new()
		number.text = str(links.size())
		number.position = (span[0] + span[1]) * 0.5 + Vector3(0, 0.48, 0)
		number.pixel_size = 0.012
		number.font_size = 34
		number.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(number)
		link_labels.append(number)
		for p: Vector3 in [span[0], span[1]]:
			box(self, Vector3(p.x, 0.28, p.z), Vector3(0.48, 0.56, 0.48), STONE)
	if boss:
		# Each successful phase physically removes one of these large assemblies.
		for i in range(3):
			var section := Node3D.new()
			add_child(section)
			sections.append(section)
			if i == 0:
				box(section, Vector3(0, 2.4, 0.3), Vector3(2.7, 0.45, 0.7), STONE)
				for x in [-1.25, 1.25]:
					box(section, Vector3(x, 1.6, 0.3), Vector3(0.4, 1.5, 0.7), ORANGE)
			elif i == 1:
				for x in [-2.3, 2.3]:
					box(section, Vector3(x, 0.9, 0.4), Vector3(0.4, 1.6, 1.2), STONE)
			else:
				for x in [-1.8, 1.8]:
					box(section, Vector3(x, 0.27, 1.7), Vector3(0.75, 0.54, 0.75), STONE)
	countdown = Label3D.new()
	countdown.position = Vector3(0, 3.45, 0)
	countdown.font_size = 36
	countdown.pixel_size = 0.012
	countdown.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(countdown)
	warning = box(self, Vector3(0, 0.03, -1.4), Vector3(2.2, 0.04, 0.8), Color("e55d55"))

func sync(mask: int, opened: bool, bare: bool, progress: int, timer: float, phase: int, attack: StringName, alive: bool) -> void:
	for i in range(links.size()):
		links[i].visible = not bool(mask & (1 << i)) and alive
		link_labels[i].visible = links[i].visible
	for plate in plates: plate.visible = not bare and not opened and alive
	core.visible = opened and pattern != &"pair" and alive
	for i in range(valves.size()):
		valves[i].visible = pattern == &"pair" and alive and not opened
		valves[i].material_override = lit_valve if i == progress else dim_valve
	if pattern == &"pair" and opened: core.visible = alive
	for i in range(sections.size()): sections[i].visible = i >= phase and alive
	warning.visible = attack in [&"windup", &"commit"] and alive
	warning.scale.z = 1.5 if attack == &"commit" else 1.0
	countdown.text = "CORE OPEN" if opened else ("A → B" if pattern == &"pair" else "ONE LAUNCH")
	if timer > 0 and not opened: countdown.text = ("B " if pattern == &"pair" else "%d/%d " % [progress, links.size()]) + "%.1fs" % timer
	if not alive: countdown.text = "DISMANTLED"

func pose(clock: float, speed: float, attack: StringName, timer: float) -> void:
	var moving := clampf(speed, 0, 1)
	for i in range(feet.size()):
		var stride := sin(clock + i * PI) * moving
		feet[i].position.y = 0.22 + maxf(0, stride) * 0.1
		feet[i].position.z = 0.15 + stride * 0.12
	# A growing footprint telegraphs the fixed committed reach; recovery is quiet.
	warning.scale.x = 0.65 + 0.35 * clampf(1 - timer / 0.8, 0, 1) if attack == &"windup" else 1.0
