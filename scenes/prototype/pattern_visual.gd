class_name CombatPatternVisual
extends Node3D
# All interactive geometry is built from these same local query anchors.
const Tuning = preload("res://scenes/prototype/tuning.gd")
const Style = preload("res://scenes/prototype/tool_style.gd")
const BLUE := Style.RING
const ORANGE := Style.CONE
const YELLOW := Style.BEAM
var instruction_visible := false
const STONE := Color("92918b")
# Built-in primitive resources are immutable after creation and shared between
# instances/phases. Only the actor's transforms/visibility change during play.
static var _materials: Dictionary = {}
static var _boxes: Dictionary = {}
static var _balls: Dictionary = {}
static var _rods: Dictionary = {}
static var _silhouettes: Dictionary = {}
var lit_valve: StandardMaterial3D
var dim_valve: StandardMaterial3D
var links: Array[MeshInstance3D] = []
var link_labels: Array[Label3D] = []
var plates: Array[MeshInstance3D] = []
var sections: Array[Node3D] = []
var valves: Array[MeshInstance3D] = []
var valve_labels: Array[Label3D] = []
var link_sections: Array[Node3D] = []
var cut_ends: Array[Node3D] = []
var valve_gates: Array[MeshInstance3D] = []
var core: MeshInstance3D
var countdown: Label3D
var warning: Node3D
var feet: Array[MeshInstance3D] = []
var identity_parts: Array[Node3D] = []
var pattern: StringName
var boss := false
var boss_identity: StringName = &""
var body_color: Color = STONE
var trim_color: Color = STONE.darkened(0.25)
var accent_color: Color = Color("6d7894")
var chassis_extents: Vector3 = Vector3(1.45, 2.27, 1.12)
# Per-instance presentation state only; shared meshes/materials stay immutable.
var _last_sync_state: Array = []

static func palette_for(identity: StringName, is_boss: bool) -> Dictionary:
	if not is_boss:
		return {"body": STONE, "trim": STONE.darkened(0.25), "accent": STONE.darkened(0.12)}
	match identity:
		&"loop_boss":
			return {"body": Color("4e3630"), "trim": Color("2b1d1a"), "accent": Color("c88a3e")}
		&"sequence_boss":
			return {"body": Color("2d3d4e"), "trim": Color("1b2530"), "accent": Color("9ab4c9")}
		&"final_boss":
			return {"body": Color("282230"), "trim": Color("16121b"), "accent": Color("d8a848")}
		_:
			return {"body": Color("3b383f"), "trim": Color("222026"), "accent": Color("b89852")}

static func spans(mode: StringName, stage := 0, is_boss := false) -> Array:
	if mode == &"loop":
		var anchors := [[Vector3(-0.85, 0.85, -0.85), Vector3(-2.15, 0.85, -2.15)],
			[Vector3(0.85, 0.85, -0.85), Vector3(2.15, 0.85, -2.15)],
			[Vector3(0.85, 0.85, 0.85), Vector3(2.15, 0.85, 2.15)],
			[Vector3(-0.85, 0.85, 0.85), Vector3(-2.15, 0.85, 2.15)]]
		# Later boss shells rotate the four physical links into a fresh arrangement.
		for span: Array in anchors:
			for i in range(2):
				span[i] = span[i].rotated(Vector3.UP, stage * PI / 8)
				if is_boss: span[i].y = 1.65
		return anchors
	if mode == &"zigzag":
		var height := 1.65 if is_boss else .85
		return [[Vector3(-2.35, height, -1.55), Vector3(-1.35, height, -0.95)],
			[Vector3(1.35, height, -0.30), Vector3(2.35, height, 0.30)],
			[Vector3(-2.35, height, 0.95), Vector3(-1.35, height, 1.55)]]
	return []

# Spawn reservation derives from the actual link endpoints and pod half-diagonal.
# Bosses reserve later phases too, so dismantling never grows into nearby cover.
static func silhouette_radius(identity: StringName) -> float:
	if _silhouettes.has(identity): return float(_silhouettes[identity])
	var extent := 2.65 if String(identity).ends_with("_boss") else (2.0 if identity == &"pair" else 1.35)
	var modes := [&"loop", &"zigzag"] if identity == &"final_boss" else [&"loop" if identity == &"loop_boss" else identity]
	for mode: StringName in modes:
		for span: Array in spans(mode):
			for point: Vector3 in span:
				extent = maxf(extent, Vector2(point.x, point.z).length() + 0.54)
	_silhouettes[identity] = extent
	return extent

static func core_anchor(is_boss := false) -> Vector3:
	return Vector3(0, 2.0 if is_boss else 1.85, -1.3 if is_boss else -0.95)

static func valve_anchor(index: int, is_boss := false) -> Vector3:
	return Vector3(-1.1 if index == 0 else 1.1, 2.2 if is_boss else 1.95, -1.4 if is_boss else -0.95)

static func valve_size(is_boss: bool) -> Vector3:
	return Vector3(.84, .84, .30) if is_boss else Vector3(.78, .78, .28)

static func core_radius(is_boss: bool) -> float:
	return .50 if is_boss else .44

static func link_radius(is_boss: bool) -> float:
	return .38 if is_boss else .28

func mat(color: Color, unlit := false) -> StandardMaterial3D:
	var key := color.to_html() + ("_unlit" if unlit else "_lit")
	if boss and color == BLUE: key += "_boss_target"
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.85
		if unlit: m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		# Mechanisms can be cut through their own chassis; show those boss spans
		# as opaque unlit targets too. External cover still blocks the weapon.
		m.no_depth_test = unlit and (color == YELLOW or (boss and color == BLUE))
		_materials[key] = m
	return _materials[key]

func box(parent: Node3D, center: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	if not _boxes.has(size):
		var mesh := BoxMesh.new()
		mesh.size = size
		_boxes[size] = mesh
	var node := MeshInstance3D.new()
	node.mesh = _boxes[size]
	node.position = center
	node.material_override = mat(color)
	parent.add_child(node)
	return node

func ball(parent: Node3D, center: Vector3, size: float, color: Color) -> MeshInstance3D:
	if not _balls.has(size):
		var mesh := SphereMesh.new()
		mesh.radius = size
		mesh.height = size * 2
		mesh.radial_segments = 12
		mesh.rings = 6
		_balls[size] = mesh
	var node := MeshInstance3D.new()
	node.mesh = _balls[size]
	node.position = center
	node.material_override = mat(color, true)
	parent.add_child(node)
	return node

func rod(parent: Node3D, a: Vector3, b: Vector3, thickness: float, color: Color) -> MeshInstance3D:
	var key := Vector2(thickness, a.distance_to(b))
	if not _rods.has(key):
		var mesh := CylinderMesh.new()
		mesh.top_radius = thickness
		mesh.bottom_radius = thickness
		mesh.height = key.y
		mesh.radial_segments = 10
		_rods[key] = mesh
	var node := MeshInstance3D.new()
	node.mesh = _rods[key]
	node.material_override = mat(color, true)
	parent.add_child(node)
	node.position = (a + b) * 0.5
	node.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
	return node

func build(mode: StringName, is_boss: bool, identity: StringName = &"", stage := 0) -> void:
	_last_sync_state.clear()
	lit_valve = mat(YELLOW,true)
	dim_valve = mat(Color("343b41"),true)
	pattern = mode
	boss = is_boss
	boss_identity = identity
	var pal := palette_for(identity, is_boss)
	body_color = pal["body"]
	trim_color = pal["trim"]
	accent_color = pal["accent"]
	chassis_extents = Vector3(2.38, 3.65, 1.72) if boss else Vector3(1.45, 2.27, 1.12)
	# Heavy feet, ribbed burial-machine body, stone/monolith head; bosses use a
	# substantially wider/taller chassis and distinct material palette.
	if boss:
		for x in [-1.02, 1.02]:
			feet.append(box(self, Vector3(x, 0.28, 0.18), Vector3(0.82, 0.56, 1.55), trim_color))
		var rib_heights := [0.72, 1.18, 1.64, 2.10]
		for r_idx in range(rib_heights.size()):
			var w := 2.38 - float(r_idx) * 0.08
			var d := 1.68 - float(r_idx) * 0.05
			box(self, Vector3(0, rib_heights[r_idx], 0.08), Vector3(w, 0.36, d), body_color)
			if r_idx < rib_heights.size() - 1:
				box(self, Vector3(0, rib_heights[r_idx] + 0.23, 0.08), Vector3(w * 0.92, 0.10, d * 0.94), accent_color)
		box(self, Vector3(0, 2.68, 0.02), Vector3(1.08, 0.86, 0.96), body_color)
		box(self, Vector3(0, 2.94, -0.48), Vector3(0.92, 0.18, 0.16), accent_color)
		for x in [-1.34, 1.34]:
			box(self, Vector3(x, 1.16, -0.22), Vector3(0.54, 1.68, 0.82), trim_color)
			plates.append(box(self, Vector3(x, 1.32, -0.46), Vector3(0.62, 0.68, 0.56), ORANGE))
		plates.append(box(self, core_anchor(boss), Vector3(1.32, 0.98, 0.22), ORANGE))
	else:
		for x in [-0.63, 0.63]:
			feet.append(box(self, Vector3(x, 0.22, 0.15), Vector3(0.55, 0.44, 1.1), trim_color))
		for y in [0.65, 1.0, 1.35]:
			box(self, Vector3(0, y, 0), Vector3(1.45, 0.29, 1.12), body_color)
		box(self, Vector3(0, 1.95, 0), Vector3(0.58, 0.64, 0.6), body_color)
		for x in [-0.9, 0.9]:
			box(self, Vector3(x, 0.7, -0.3), Vector3(0.34, 1.05, 0.44), accent_color)
			plates.append(box(self, Vector3(x, 1.15, -0.4), Vector3(0.48, 0.5, 0.5), ORANGE))
		plates.append(box(self, core_anchor(boss), Vector3(1.1, 0.82, 0.18), ORANGE))
	# Core has a large halo and stays still; quick targets are a pair of small
	# square sockets with moving shutters, readable without relying on labels.
	var core_halo := TorusMesh.new()
	core_halo.inner_radius = .56 if boss else .48
	core_halo.outer_radius = .72 if boss else .60
	var core_rim := MeshInstance3D.new()
	core_rim.mesh = core_halo
	core_rim.rotation.x = PI / 2
	core_rim.position = core_anchor(boss)
	core_rim.material_override = mat(Color("574914"), true)
	add_child(core_rim)
	core = ball(self, core_anchor(boss), core_radius(boss), YELLOW)
	for i in range(2):
		valves.append(box(self, valve_anchor(i, boss), valve_size(boss), YELLOW))
		var gate := box(self, valve_anchor(i, boss) + Vector3(0, 0, -.18), Vector3(.92 if boss else .86, .22 if boss else .20, .12), Color("64717b"))
		valve_gates.append(gate)
		var letter := Label3D.new()
		letter.text = "A" if i == 0 else "B"
		letter.position = valve_anchor(i, boss) + Vector3(0, 0.46, 0)
		letter.font_size = 38
		letter.pixel_size = 0.012
		letter.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		letter.no_depth_test = true
		letter.visible = false
		add_child(letter)
		valve_labels.append(letter)
	for span: Array in spans(mode, stage if identity == &"loop_boss" else 0, boss):
		links.append(rod(self, span[0], span[1], link_radius(boss), BLUE))
		var ends := Node3D.new()
		add_child(ends)
		cut_ends.append(ends)
		rod(ends, span[0], span[0].lerp(span[1], .18), link_radius(boss), BLUE.darkened(.5) if boss else BLUE)
		rod(ends, span[1].lerp(span[0], .18), span[1], link_radius(boss), BLUE.darkened(.5) if boss else BLUE)
		var number := Label3D.new()
		number.text = str(links.size())
		number.position = (span[0] + span[1]) * 0.5 + Vector3(0, 0.48, 0)
		number.pixel_size = 0.012
		number.font_size = 34
		number.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(number)
		number.visible = false
		link_labels.append(number)
		var component := Node3D.new()
		add_child(component)
		link_sections.append(component)
		var end: Vector3 = span[1]
		box(component, Vector3(end.x, .52 if boss else .48, end.z), Vector3(.78 if boss else .68, 1.04 if boss else .96, .78 if boss else .68), body_color)
		plates.append(box(component, Vector3(end.x, 1.06 if boss else 1.0, end.z), Vector3(.82 if boss else .75, .26 if boss else .24, .82 if boss else .75), ORANGE))
	if boss:
		# Each successful phase physically removes one of these large assemblies.
		for i in range(3):
			var section := Node3D.new()
			add_child(section)
			sections.append(section)
			if i == 0:
				box(section, Vector3(0, 2.55, 0.36), Vector3(3.15, 0.54, 0.86), body_color)
				box(section, Vector3(0, 2.88, 0.36), Vector3(2.85, 0.16, 0.64), accent_color)
				for x in [-1.45, 1.45]:
					plates.append(box(section, Vector3(x, 1.68, 0.34), Vector3(0.48, 1.65, 0.80), ORANGE))
			elif i == 1:
				for x in [-2.42, 2.42]:
					box(section, Vector3(x, 1.08, 0.42), Vector3(0.56, 2.02, 1.38), body_color)
					box(section, Vector3(x, 2.18, 0.42), Vector3(0.64, 0.22, 1.46), accent_color)
			else:
				for x in [-1.92, 1.92]:
					box(section, Vector3(x, 0.38, 1.78), Vector3(0.90, 0.74, 0.94), trim_color)
					box(section, Vector3(x, 0.82, 1.78), Vector3(0.72, 0.18, 0.76), accent_color)
		# Distinct boss crown/silhouette per identity:
		# loop_boss = broad double-ringed circular kiln with four furnace stacks;
		# sequence_boss = tall twin-spire chronometer instrument with high transom;
		# final_boss = grand winged reliquary idol with tri-spire crown and sun-halo.
		if identity == &"loop_boss":
			var kiln_root := Node3D.new()
			add_child(kiln_root)
			identity_parts.append(kiln_root)
			var halo := TorusMesh.new()
			halo.inner_radius = 1.28
			halo.outer_radius = 1.64
			var ring := MeshInstance3D.new()
			ring.mesh = halo
			ring.position.y = 3.05
			ring.material_override = mat(trim_color)
			kiln_root.add_child(ring)
			var inner_halo := TorusMesh.new()
			inner_halo.inner_radius = 0.78
			inner_halo.outer_radius = 1.02
			var inner_ring := MeshInstance3D.new()
			inner_ring.mesh = inner_halo
			inner_ring.position.y = 3.42
			inner_ring.material_override = mat(accent_color)
			kiln_root.add_child(inner_ring)
			for corner: Vector3 in [Vector3(-1.32, 2.35, -0.45), Vector3(1.32, 2.35, -0.45), Vector3(-1.32, 2.35, 0.72), Vector3(1.32, 2.35, 0.72)]:
				box(kiln_root, corner, Vector3(0.36, 1.35, 0.36), trim_color)
		elif identity == &"sequence_boss":
			var spire_root := Node3D.new()
			add_child(spire_root)
			identity_parts.append(spire_root)
			for x in [-1.18, 1.18]:
				box(spire_root, Vector3(x, 2.85, 0.34), Vector3(0.62, 3.25, 0.78), body_color)
				box(spire_root, Vector3(x, 4.25, 0.34), Vector3(0.72, 0.22, 0.86), accent_color)
				ball(spire_root, Vector3(x, 4.58, 0.34), 0.32, accent_color)
			box(spire_root, Vector3(0, 3.82, 0.34), Vector3(2.96, 0.28, 0.44), accent_color)
		elif identity == &"final_boss":
			var idol_root := Node3D.new()
			add_child(idol_root)
			identity_parts.append(idol_root)
			for x in [-1.85, 1.85]:
				box(idol_root, Vector3(x, 2.15, 0.55), Vector3(0.68, 2.85, 1.18), trim_color)
				box(idol_root, Vector3(x, 3.62, 0.55), Vector3(0.76, 0.24, 1.26), accent_color)
			box(idol_root, Vector3(0, 3.48, 0.38), Vector3(2.88, 0.40, 0.72), accent_color)
			for x in [-1.15, 0.0, 1.15]:
				var spire_h := 1.45 if is_equal_approx(x, 0.0) else 1.18
				box(idol_root, Vector3(x, 3.68 + spire_h * 0.5, 0.38), Vector3(0.38, spire_h, 0.42), accent_color)
			var sun_halo := TorusMesh.new()
			sun_halo.inner_radius = 1.05
			sun_halo.outer_radius = 1.38
			var sun_ring := MeshInstance3D.new()
			sun_ring.mesh = sun_halo
			sun_ring.rotation.x = PI * 0.5
			sun_ring.position = Vector3(0, 3.35, 0.42)
			sun_ring.material_override = mat(accent_color)
			idol_root.add_child(sun_ring)
	countdown = Label3D.new()
	countdown.position = Vector3(0, 3.45, 0)
	countdown.font_size = 36
	countdown.pixel_size = 0.012
	countdown.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	countdown.visible = false
	add_child(countdown)
	warning = Node3D.new()
	add_child(warning)
	if mode == &"loop":
		var ring := MeshInstance3D.new()
		var mesh := TorusMesh.new()
		mesh.inner_radius = float(Tuning.PATTERNS.loop_reach) - .15
		mesh.outer_radius = float(Tuning.PATTERNS.loop_reach) + .05
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
	# Timer does not drive this discrete presentation. Pose/turning continue at
	# their existing cadence; only identical child-property writes are skipped.
	var state := [pattern, boss, mask, opened, bare, progress, phase, attack, alive, instruction_visible]
	if state == _last_sync_state: return
	_last_sync_state = state
	for i in range(links.size()):
		links[i].visible = not bool(mask & (1 << i)) and alive
		link_labels[i].visible = false
		# Cutting a link leaves its stone support in place. Only the cable breaks;
		# a timeout reconnects it once instead of repeatedly losing entire legs.
		link_sections[i].visible = alive
		cut_ends[i].visible = alive and bool(mask & (1 << i))
	for plate in plates: plate.visible = not bare and not opened and alive
	core.visible = opened and pattern != &"pair" and alive
	for i in range(valves.size()):
		valves[i].visible = pattern == &"pair" and alive and not opened
		valves[i].material_override = lit_valve if i == progress else dim_valve
		valve_labels[i].visible = false
		valve_gates[i].visible = valves[i].visible
		valve_gates[i].position.y = valve_anchor(i, boss).y + (.52 if i == progress else 0.0)
	if pattern == &"pair" and opened: core.visible = alive
	for i in range(sections.size()): sections[i].visible = i >= phase and alive
	warning.visible = attack in [&"windup", &"commit"] and alive
	warning.scale = Vector3.ONE
	countdown.text = ""
	if alive:
		if opened:
			countdown.text = "Charge yellow"
			countdown.modulate = YELLOW
		elif pattern == &"pair":
			countdown.text = "A then B" if progress == 0 else "Then B"
			countdown.modulate = YELLOW
		else:
			countdown.text = "Cut blue"
			countdown.modulate = BLUE
	_refresh_instruction_visibility()

func set_instruction_visible(value: bool) -> void:
	instruction_visible = value
	_refresh_instruction_visibility()

func _refresh_instruction_visibility() -> void:
	if not is_instance_valid(countdown): return
	countdown.visible = false
	for i in range(link_labels.size()):
		link_labels[i].visible = false
	for i in range(valve_labels.size()):
		valve_labels[i].visible = false

func pose(clock: float, speed: float, attack: StringName, timer: float) -> void:
	# Keep the shown target edge fixed. The next socket is distinguished by its
	# bright material and raised shutter, not a misleading changing silhouette.
	for i in range(valves.size()):
		valves[i].scale = Vector3.ONE
	var moving := clampf(speed, 0, 1)
	var base_foot_y := 0.28 if boss else 0.22
	var base_foot_z := 0.18 if boss else 0.15
	for i in range(feet.size()):
		var stride := sin(clock + i * PI) * moving
		feet[i].position.y = base_foot_y + maxf(0, stride) * 0.1
		feet[i].position.z = base_foot_z + stride * 0.12
	# A growing footprint telegraphs the fixed committed reach; recovery is quiet.
	# Keep the footprint fixed: it shows the exact coming danger throughout windup.
	warning.scale = Vector3.ONE

