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
var valve_labels: Array[Label3D] = []
var link_sections: Array[Node3D] = []
var core: MeshInstance3D
var countdown: Label3D
var warning: Node3D
var feet: Array[MeshInstance3D] = []
var pattern: StringName
var boss := false

static func spans(mode: StringName, stage := 0) -> Array:
	if mode == &"loop":
		var anchors := [[Vector3(-0.65, 0.7, -0.65), Vector3(-1.8, 0.7, -1.8)],
			[Vector3(0.65, 0.7, -0.65), Vector3(1.8, 0.7, -1.8)],
			[Vector3(0.65, 0.7, 0.65), Vector3(1.8, 0.7, 1.8)],
			[Vector3(-0.65, 0.7, 0.65), Vector3(-1.8, 0.7, 1.8)]]
		# Later boss shells rotate the four physical links into a fresh arrangement.
		for span: Array in anchors:
			for i in range(2): span[i] = span[i].rotated(Vector3.UP, stage * PI / 8)
		return anchors
	if mode == &"zigzag":
		return [[Vector3(-2.0, 0.7, -1.25), Vector3(-1.2, 0.7, -0.75)],
			[Vector3(1.2, 0.7, -0.25), Vector3(2.0, 0.7, 0.25)],
			[Vector3(-2.0, 0.7, 0.75), Vector3(-1.2, 0.7, 1.25)]]
	return []

static func core_anchor(is_boss := false) -> Vector3:
	return Vector3(0, 2.0 if is_boss else 1.85, -1.3 if is_boss else -0.95)

static func valve_anchor(index: int, is_boss := false) -> Vector3:
	return Vector3(-0.8 if index == 0 else 0.8, 2.2 if is_boss else 1.95, -1.4 if is_boss else -0.95)

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

func build(mode: StringName, is_boss: bool, identity: StringName = &"", stage := 0) -> void:
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
	core = ball(self, core_anchor(boss), 0.4 if boss else .34, YELLOW)
	core.material_override.no_depth_test = true
	for i in range(2):
		valves.append(ball(self, valve_anchor(i, boss), 0.36, YELLOW))
		var letter := Label3D.new()
		letter.text = "A" if i == 0 else "B"
		letter.position = valve_anchor(i, boss) + Vector3(0, 0.46, 0)
		letter.font_size = 38
		letter.pixel_size = 0.012
		letter.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		letter.no_depth_test = true
		letter.visible = mode == &"pair"
		add_child(letter)
		valve_labels.append(letter)
	for span: Array in spans(mode, stage if identity == &"loop_boss" else 0):
		links.append(rod(self, span[0], span[1], 0.2, BLUE))
		var number := Label3D.new()
		number.text = str(links.size())
		number.position = (span[0] + span[1]) * 0.5 + Vector3(0, 0.48, 0)
		number.pixel_size = 0.012
		number.font_size = 34
		number.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(number)
		link_labels.append(number)
		var component := Node3D.new()
		add_child(component)
		link_sections.append(component)
		var end: Vector3 = span[1]
		box(component, Vector3(end.x, .48, end.z), Vector3(.68, .96, .68), STONE)
		plates.append(box(component, Vector3(end.x, 1.0, end.z), Vector3(.75, .24, .75), ORANGE))
	if boss:
		# Each successful phase physically removes one of these large assemblies.
		for i in range(3):
			var section := Node3D.new()
			add_child(section)
			sections.append(section)
			if i == 0:
				box(section, Vector3(0, 2.4, 0.3), Vector3(2.7, 0.45, 0.7), STONE)
				for x in [-1.25, 1.25]:
					plates.append(box(section, Vector3(x, 1.6, 0.3), Vector3(0.4, 1.5, 0.7), ORANGE))
			elif i == 1:
				for x in [-2.3, 2.3]:
					box(section, Vector3(x, 0.9, 0.4), Vector3(0.4, 1.6, 1.2), STONE)
			else:
				for x in [-1.8, 1.8]:
					box(section, Vector3(x, 0.27, 1.7), Vector3(0.75, 0.54, 0.75), STONE)
		# A low circular kiln, a tall twin-spire instrument and a broad final idol.
		if identity == &"loop_boss":
			var halo := TorusMesh.new()
			halo.inner_radius = 1.0
			halo.outer_radius = 1.3
			var ring := MeshInstance3D.new()
			ring.mesh = halo
			ring.position.y = 2.7
			ring.material_override = mat(STONE.darkened(.2))
			add_child(ring)
		elif identity == &"sequence_boss":
			for x in [-.9, .9]:
				box(self, Vector3(x, 2.65, .3), Vector3(.5, 2.8, .65), STONE)
				ball(self, Vector3(x, 4.12, .3), .24, Color("6d7894"))
	countdown = Label3D.new()
	countdown.position = Vector3(0, 3.45, 0)
	countdown.font_size = 36
	countdown.pixel_size = 0.012
	countdown.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(countdown)
	warning = Node3D.new()
	add_child(warning)
	if boss and mode == &"loop":
		var ring := MeshInstance3D.new()
		var mesh := TorusMesh.new()
		mesh.inner_radius = 3.95
		mesh.outer_radius = 4.15
		ring.mesh = mesh
		ring.position.y = .035
		ring.material_override = mat(Color("ef6659"), true)
		warning.add_child(ring)
	elif boss:
		var fan := [-.3, 0.0, .3] if mode == &"pair" else [-.55, -.27, 0.0, .27, .55]
		for angle: float in fan:
			var ray := box(warning, Vector3(0, .035, -5.0).rotated(Vector3.UP, angle), Vector3(.12, .04, 8), Color("ef6659"))
			ray.rotation.y = angle
	else:
		box(warning, Vector3(0, .035, -1.4), Vector3(2.2, .04, .8), Color("e55d55"))

func sync(mask: int, opened: bool, bare: bool, progress: int, timer: float, phase: int, attack: StringName, alive: bool) -> void:
	for i in range(links.size()):
		links[i].visible = not bool(mask & (1 << i)) and alive
		link_labels[i].visible = links[i].visible
		link_sections[i].visible = links[i].visible
	for plate in plates: plate.visible = not bare and not opened and alive
	core.visible = opened and pattern != &"pair" and alive
	for i in range(valves.size()):
		valves[i].visible = pattern == &"pair" and alive and not opened
		valves[i].material_override = lit_valve if i == progress else dim_valve
		valves[i].material_override.no_depth_test = true
		valve_labels[i].visible = valves[i].visible
	if pattern == &"pair" and opened: core.visible = alive
	for i in range(sections.size()): sections[i].visible = i >= phase and alive
	warning.visible = attack in [&"windup", &"commit"] and alive
	warning.scale = Vector3.ONE
	countdown.text = "CHARGE YELLOW CORE" if opened else ("A → B" if pattern == &"pair" else "ONE BLUE LAUNCH")
	if timer > 0 and not opened: countdown.text = ("B " if pattern == &"pair" else "%d/%d " % [progress, links.size()]) + "%.1fs" % timer
	if not alive: countdown.text = "DISMANTLED"

func pose(clock: float, speed: float, attack: StringName, timer: float) -> void:
	var moving := clampf(speed, 0, 1)
	for i in range(feet.size()):
		var stride := sin(clock + i * PI) * moving
		feet[i].position.y = 0.22 + maxf(0, stride) * 0.1
		feet[i].position.z = 0.15 + stride * 0.12
	# A growing footprint telegraphs the fixed committed reach; recovery is quiet.
	# Keep the footprint fixed: it shows the exact coming danger throughout windup.
	warning.scale = Vector3.ONE
