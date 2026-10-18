extends "res://scenes/prototype/museum_environment.gd"

# Four-room museum presentation and physical campaign wayfinding.
# Extends MuseumEnvironment with four-room cover kit builders (display_island, partition,
# column, bench, plinth), doorway framing, visible exit/activation cues, restrained
# room-specific floor/lighting palettes, and the boss entrance gate/pause/activation ceremony.

const Rooms = preload("res://scenes/prototype/rooms.gd")

signal exit_state_changed(open: bool)
signal gates_closed(room_id: StringName)
signal boss_activated(room_id: StringName)

const GATE_CLOSE_DURATION := 0.60
const BOSS_PAUSE_DURATION := 0.50

var floor_accents_root: Node3D
var doors_root: Node3D
var ceremony_root: Node3D

var active_room_id: StringName = &"gallery"
var active_definition: Dictionary = {}
var active_cover_rectangles: Array[Rect2] = []

var exit_open: bool = false
var boss_ceremony_state: StringName = &"inactive"
var boss_ceremony_timer: float = 0.0
var gates_closed_ratio: float = 0.0
var boss_activation_glow: float = 0.0

var _north_gate_left: MeshInstance3D
var _north_gate_right: MeshInstance3D
var _south_gate_left: MeshInstance3D
var _south_gate_right: MeshInstance3D
var _exit_beacon_mat: StandardMaterial3D
var _entrance_beacon_mat: StandardMaterial3D
var _boss_ring_mat: StandardMaterial3D
var _boss_core_mat: StandardMaterial3D
var _north_door_width: float = 6.4
var _south_door_width: float = 6.4
var _exit_label: Label3D
var pickup_root: Node3D
var pickup_tool := 0
var pickup_position := Vector3.ZERO
const PICKUP_MODELS = [preload("res://assets/equipment/ring_caster.glb"),
	preload("res://assets/equipment/flash_camera.glb"), preload("res://assets/equipment/heat_bellows.glb"),
	preload("res://assets/equipment/time_device.glb")]
const PICKUP_NAMES := ["BLUE · DRAWING CUTTER", "YELLOW · FLASH CAMERA", "ORANGE · HEAT BELLOWS", "PURPLE · TIME DEVICE"]
const PICKUP_COLORS := [Color("60dbde"), Color("f0d77b"), Color("ed9966"), Color("ba9ce9")]

func build(_include_cover_decorations: bool = false) -> Node3D:
	return super.build(false)

func show_tool_pickup(tool: int, point: Vector3) -> void:
	clear_tool_pickup()
	pickup_tool = tool
	pickup_position = Vector3(point.x, 0, point.z)
	pickup_root = Node3D.new()
	pickup_root.name = "ToolPickup_%d" % tool
	pickup_root.position = pickup_position
	add_child(pickup_root)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = PICKUP_COLORS[tool - 1]
	mat.emission_enabled = true
	mat.emission = mat.albedo_color
	mat.emission_energy_multiplier = 0.8
	_add_cylinder_mesh(pickup_root, "AcquisitionHalo", 1.5, 1.5, 0.035, Vector3(0, 0.025, 0), mat)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("40454b")
	_add_box_mesh(pickup_root, "ToolPlinth", Vector3(1.3, 0.65, 1.0), Vector3(0, 0.35, 0), stone)
	var prop: Node3D = PICKUP_MODELS[tool - 1].instantiate()
	prop.position = Vector3(0, 1.05, 0)
	prop.rotation_degrees = Vector3(0, -25, 0)
	prop.scale = Vector3.ONE * 1.7
	pickup_root.add_child(prop)
	var label := Label3D.new()
	label.text = "%s\nWalk into the light to collect" % PICKUP_NAMES[tool - 1]
	label.position = Vector3(0, 2.7, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 32
	label.pixel_size = 0.009
	label.modulate = PICKUP_COLORS[tool - 1]
	pickup_root.add_child(label)

func clear_tool_pickup() -> void:
	if is_instance_valid(pickup_root):
		remove_child(pickup_root)
		pickup_root.queue_free()
	pickup_root = null
	pickup_tool = 0

func player_in_exit(point: Vector3) -> bool:
	if not exit_open: return false
	var door: Vector3 = active_definition.exit_door.position
	# The full illuminated threshold is an exit region, with room for approach.
	return absf(point.x - door.x) <= _north_door_width * 0.5 and absf(point.z - door.z) <= 2.2



func _ready() -> void:
	if not _built:
		build(false)
		apply_room(Rooms.definitions()[0])


func apply_room(definition: Dictionary, cover_ref: RefCounted = null, arena_node: Node3D = null) -> void:
	if not _built:
		build(false)
	_ensure_room_roots()
	clear_tool_pickup()

	var def := definition if not definition.is_empty() else Rooms.definitions()[0]
	active_definition = def.duplicate(true)
	active_room_id = def.get("id", &"gallery")

	active_cover_rectangles.clear()
	var raw_cover: Array = def.get("cover", Cover.RECTANGLES)
	for item in raw_cover:
		if item is Rect2:
			active_cover_rectangles.append(item)

	var target_arena := arena_node if arena_node != null else (get_parent() as Node3D)
	var target_cover := cover_ref
	if target_cover == null and target_arena != null and "cover" in target_arena:
		target_cover = target_arena.get("cover")
	if target_cover != null and target_cover.has_method("set_rectangles"):
		target_cover.set_rectangles(active_cover_rectangles)

	_apply_floor_and_lighting(def, target_arena)
	_rebuild_room_cover(def)
	_rebuild_doorways_and_ceremony(def)

	if bool(def.get("is_boss_room", false)):
		start_boss_entrance()
	else:
		boss_ceremony_state = &"inactive"
		boss_ceremony_timer = 0.0
		gates_closed_ratio = 0.0
		boss_activation_glow = 0.0
		set_exit_open(false)
		_update_gate_and_cue_visuals()


func set_exit_open(open: bool) -> void:
	exit_open = open
	if is_instance_valid(_exit_label):
		_exit_label.text = "NEXT GALLERY →\nWalk through the lit doorway" if open else "GALLERY SEALED\nClear the exhibits"
		_exit_label.modulate = Color("91f2bc") if open else Color("a89b85")
	if open and boss_ceremony_state == &"inactive":
		gates_closed_ratio = 0.0
	elif not open and boss_ceremony_state == &"inactive":
		gates_closed_ratio = 1.0
	_update_gate_and_cue_visuals()
	exit_state_changed.emit(exit_open)


func start_boss_entrance() -> void:
	active_definition["is_boss_room"] = true
	exit_open = false
	boss_ceremony_state = &"closing_gates"
	boss_ceremony_timer = 0.0
	gates_closed_ratio = 0.0
	boss_activation_glow = 0.08
	_update_gate_and_cue_visuals()


func is_boss_active() -> bool:
	return boss_ceremony_state == &"active"


func set_boss_ceremony_phase(phase: StringName) -> void:
	boss_ceremony_state = phase
	match phase:
		&"inactive":
			boss_ceremony_timer = 0.0
			gates_closed_ratio = 0.0 if exit_open else 1.0
			boss_activation_glow = 0.0
		&"closing_gates":
			boss_ceremony_timer = GATE_CLOSE_DURATION * 0.5
			gates_closed_ratio = 0.5
			boss_activation_glow = 0.15
		&"pause":
			boss_ceremony_timer = 0.0
			gates_closed_ratio = 1.0
			boss_activation_glow = 0.45
		&"active":
			boss_ceremony_timer = BOSS_PAUSE_DURATION
			gates_closed_ratio = 1.0
			boss_activation_glow = 1.0
	_update_gate_and_cue_visuals()


func step_ceremony(world_delta: float) -> Dictionary:
	var dt := maxf(0.0, world_delta)
	if boss_ceremony_state == &"closing_gates":
		boss_ceremony_timer += dt
		gates_closed_ratio = clampf(boss_ceremony_timer / GATE_CLOSE_DURATION, 0.0, 1.0)
		boss_activation_glow = lerpf(0.08, 0.30, gates_closed_ratio)
		if boss_ceremony_timer >= GATE_CLOSE_DURATION:
			var overflow := boss_ceremony_timer - GATE_CLOSE_DURATION
			boss_ceremony_state = &"pause"
			boss_ceremony_timer = 0.0
			gates_closed_ratio = 1.0
			gates_closed.emit(active_room_id)
			if overflow > 0.0:
				return step_ceremony(overflow)
	elif boss_ceremony_state == &"pause":
		boss_ceremony_timer += dt
		gates_closed_ratio = 1.0
		var pause_t := clampf(boss_ceremony_timer / BOSS_PAUSE_DURATION, 0.0, 1.0)
		boss_activation_glow = lerpf(0.30, 0.85, pause_t)
		if boss_ceremony_timer >= BOSS_PAUSE_DURATION:
			boss_ceremony_state = &"active"
			boss_ceremony_timer = BOSS_PAUSE_DURATION
			boss_activation_glow = 1.0
			boss_activated.emit(active_room_id)
	_update_gate_and_cue_visuals()
	return ceremony_status()


func ceremony_status() -> Dictionary:
	return {
		"room_id": active_room_id,
		"state": boss_ceremony_state,
		"gates_closed": gates_closed_ratio >= 0.999,
		"boss_active": boss_ceremony_state == &"active",
		"gates_closed_ratio": gates_closed_ratio,
		"activation_glow": boss_activation_glow,
		"exit_open": exit_open,
	}


func sync_cover_colliders(target_parent: Node3D, rectangles: Array[Rect2] = []) -> Array[StaticBody3D]:
	var rects := rectangles if not rectangles.is_empty() else active_cover_rectangles
	var created: Array[StaticBody3D] = []
	if target_parent == null or not is_instance_valid(target_parent):
		return created

	var to_remove: Array[Node] = []
	for child in target_parent.get_children():
		if child is StaticBody3D and child.position.y > -0.1:
			to_remove.append(child)
	for node in to_remove:
		target_parent.remove_child(node)
		node.free()

	var idx := 0
	for rectangle in rects:
		idx += 1
		var body := StaticBody3D.new()
		body.name = "RoomCoverBody_%02d" % idx
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(rectangle.size.x, 2.2, rectangle.size.y)
		shape.shape = box
		body.add_child(shape)
		body.position = Vector3(rectangle.get_center().x, 1.1, rectangle.get_center().y)
		target_parent.add_child(body)
		created.append(body)
	return created


func get_collider_world_rectangles(target_parent: Node3D) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if target_parent == null or not is_instance_valid(target_parent):
		return rects
	for child in target_parent.get_children():
		if child is StaticBody3D and child.position.y > -0.1:
			for sub in child.get_children():
				if sub is CollisionShape3D and sub.shape is BoxShape3D:
					var box := sub.shape as BoxShape3D
					var pos: Vector3 = child.position + sub.position
					rects.append(Rect2(pos.x - box.size.x * 0.5, pos.z - box.size.z * 0.5, box.size.x, box.size.z))
	return rects


func _ensure_room_roots() -> void:
	if floor_accents_root == null or not is_instance_valid(floor_accents_root):
		floor_accents_root = Node3D.new()
		floor_accents_root.name = "FloorAccents"
		add_child(floor_accents_root)
	if doors_root == null or not is_instance_valid(doors_root):
		doors_root = Node3D.new()
		doors_root.name = "Doorways"
		add_child(doors_root)
	if ceremony_root == null or not is_instance_valid(ceremony_root):
		ceremony_root = Node3D.new()
		ceremony_root.name = "CeremonyCues"
		add_child(ceremony_root)


func _clear_node_children(node: Node3D) -> void:
	if node == null or not is_instance_valid(node):
		return
	for child in node.get_children():
		node.remove_child(child)
		child.free()


func _apply_floor_and_lighting(def: Dictionary, target_arena: Node3D) -> void:
	_clear_node_children(floor_accents_root)
	var palette: Dictionary = def.get("floor_palette", {})
	var base_col: Color = palette.get("base", Color(0.20, 0.22, 0.24))
	var accent_col: Color = palette.get("accent", Color(0.24, 0.26, 0.28))
	var border_col: Color = palette.get("border", Color(0.17, 0.19, 0.21))
	var style: StringName = palette.get("style", &"aisle")

	if _floor_shader_material != null:
		_floor_shader_material.set_shader_parameter("base_color", Vector3(base_col.r, base_col.g, base_col.b))

	var accent_mat := StandardMaterial3D.new()
	accent_mat.albedo_color = accent_col
	accent_mat.roughness = 0.92

	var border_mat := StandardMaterial3D.new()
	border_mat.albedo_color = border_col
	border_mat.roughness = 0.94

	# Subtle perimeter border strips inside [-19.4, 19.4]
	_add_box_mesh(floor_accents_root, "BorderNorth", Vector3(38.4, 0.008, 0.65), Vector3(0.0, 0.005, -18.8), border_mat)
	_add_box_mesh(floor_accents_root, "BorderSouth", Vector3(38.4, 0.008, 0.65), Vector3(0.0, 0.005, 18.8), border_mat)
	_add_box_mesh(floor_accents_root, "BorderWest", Vector3(0.65, 0.008, 37.0), Vector3(-18.8, 0.005, 0.0), border_mat)
	_add_box_mesh(floor_accents_root, "BorderEast", Vector3(0.65, 0.008, 37.0), Vector3(18.8, 0.005, 0.0), border_mat)

	match style:
		&"aisle":
			_add_box_mesh(floor_accents_root, "CentralAisle", Vector3(5.6, 0.008, 26.0), Vector3(0.0, 0.006, 0.0), accent_mat)
			_add_box_mesh(floor_accents_root, "LoopLaneNorth", Vector3(24.0, 0.008, 2.0), Vector3(0.0, 0.006, -9.8), accent_mat)
			_add_box_mesh(floor_accents_root, "LoopLaneSouth", Vector3(24.0, 0.008, 2.0), Vector3(0.0, 0.006, 6.2), accent_mat)
		&"cross_hall":
			_add_box_mesh(floor_accents_root, "MainCorridor", Vector3(5.8, 0.008, 26.0), Vector3(0.0, 0.006, 0.0), accent_mat)
			_add_box_mesh(floor_accents_root, "CrossWing", Vector3(28.0, 0.008, 4.0), Vector3(0.0, 0.006, -1.0), accent_mat)
		&"work_bays":
			_add_box_mesh(floor_accents_root, "WestBayRunner", Vector3(4.0, 0.008, 25.0), Vector3(-6.5, 0.006, 0.0), accent_mat)
			_add_box_mesh(floor_accents_root, "EastBayRunner", Vector3(4.0, 0.008, 25.0), Vector3(6.0, 0.006, 0.0), accent_mat)
			_add_box_mesh(floor_accents_root, "StaggeredConnector", Vector3(15.0, 0.008, 3.2), Vector3(-0.2, 0.006, -3.5), accent_mat)
		&"boss_court":
			_add_cylinder_mesh(floor_accents_root, "OuterCourtRing", 6.4, 6.4, 0.006, Vector3(0.0, 0.004, -2.0), border_mat)
			_add_cylinder_mesh(floor_accents_root, "InnerCourtDais", 5.4, 5.4, 0.008, Vector3(0.0, 0.005, -2.0), accent_mat)
			_add_box_mesh(floor_accents_root, "SouthApproach", Vector3(5.2, 0.006, 12.0), Vector3(0.0, 0.004, 7.0), accent_mat)

	var lighting: Dictionary = def.get("lighting", {})
	var wall_tint: Color = lighting.get("wall_tint", Color(1.18, 1.12, 1.05))
	for mat in _wall_materials:
		if mat != null:
			mat.albedo_color = wall_tint

	if target_arena != null and is_instance_valid(target_arena):
		for child in target_arena.get_children():
			if child is DirectionalLight3D:
				child.light_color = lighting.get("light_color", Color.WHITE)
				child.light_energy = float(lighting.get("light_energy", 1.0))
			elif child is WorldEnvironment and child.environment != null:
				child.environment.ambient_light_color = lighting.get("ambient_color", Color.WHITE)
				child.environment.ambient_light_energy = float(lighting.get("ambient_energy", 0.65))


func _rebuild_room_cover(def: Dictionary) -> void:
	_clear_node_children(cover_root)
	var pieces: Array = def.get("cover_pieces", [])
	var rects: Array[Rect2] = active_cover_rectangles

	for i in range(rects.size()):
		var rect: Rect2 = rects[i]
		var piece_info: Dictionary = pieces[i] if i < pieces.size() else {}
		var kind: StringName = piece_info.get("kind", &"display_island")
		var height: float = float(piece_info.get("height", 1.5))
		_build_cover_kit_piece(i + 1, rect, kind, height)


func _build_cover_kit_piece(index: int, rect: Rect2, kind: StringName, height: float) -> MeshInstance3D:
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.28, 0.25, 0.23)
	base_mat.roughness = 0.82

	var stone_mat := StandardMaterial3D.new()
	stone_mat.albedo_color = Color(0.44, 0.42, 0.39)
	stone_mat.roughness = 0.78

	var cap_mat := StandardMaterial3D.new()
	cap_mat.albedo_color = Color(0.60, 0.57, 0.52)
	cap_mat.roughness = 0.68

	var brass_mat := StandardMaterial3D.new()
	brass_mat.albedo_color = Color(0.56, 0.48, 0.34)
	brass_mat.roughness = 0.44
	brass_mat.metallic = 0.28

	var root_mesh := MeshInstance3D.new()
	root_mesh.name = "Cover_%02d_%s" % [index, String(kind)]
	var hull_box := BoxMesh.new()

	match kind:
		&"display_island":
			var base_h := 0.80
			hull_box.size = Vector3(rect.size.x, base_h, rect.size.y)
			root_mesh.mesh = hull_box
			root_mesh.material_override = base_mat
			root_mesh.position = Vector3(rect.get_center().x, base_h * 0.5, rect.get_center().y)
			cover_root.add_child(root_mesh)

			# Cream display deck inside cabinet top
			_add_box_mesh(
				root_mesh,
				"DisplayDeck",
				Vector3(rect.size.x * 0.94, 0.08, rect.size.y * 0.92),
				Vector3(0.0, base_h * 0.5 + 0.04, 0.0),
				cap_mat
			)
			# Two exhibit tablets on dark velvet pads inside the vitrine (visible from top-down camera!)
			var tablet_mat := StandardMaterial3D.new()
			tablet_mat.albedo_color = Color(0.36, 0.35, 0.33)
			tablet_mat.roughness = 0.70
			for side in [-1.0, 1.0]:
				_add_box_mesh(
					root_mesh,
					"VelvetPad_%s" % ("L" if side < 0.0 else "R"),
					Vector3(rect.size.x * 0.28, 0.05, rect.size.y * 0.44),
					Vector3(side * rect.size.x * 0.22, base_h * 0.5 + 0.10, 0.0),
					base_mat
				)
				_add_box_mesh(
					root_mesh,
					"ExhibitTablet_%s" % ("L" if side < 0.0 else "R"),
					Vector3(rect.size.x * 0.22, 0.28, rect.size.y * 0.34),
					Vector3(side * rect.size.x * 0.22, base_h * 0.5 + 0.25, 0.0),
					tablet_mat
				)
			# Translucent glass vitrine hood
			var glass_mat := StandardMaterial3D.new()
			glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			glass_mat.albedo_color = Color(0.74, 0.88, 0.94, 0.20)
			glass_mat.roughness = 0.15
			var glass_h := maxf(0.48, height - base_h)
			var vit_w := rect.size.x * 0.90
			var vit_d := rect.size.y * 0.88
			var top_y := base_h * 0.5 + 0.08 + glass_h
			_add_box_mesh(
				root_mesh,
				"GlassVitrine",
				Vector3(vit_w, glass_h, vit_d),
				Vector3(0.0, base_h * 0.5 + 0.08 + glass_h * 0.5, 0.0),
				glass_mat
			)
			# Open 4-rail top frame and 4 corner posts so the interior exhibits remain visible from above
			var rail_t := 0.08
			_add_box_mesh(root_mesh, "FrameNorth", Vector3(vit_w, rail_t, rail_t), Vector3(0.0, top_y, -vit_d * 0.5), brass_mat)
			_add_box_mesh(root_mesh, "FrameSouth", Vector3(vit_w, rail_t, rail_t), Vector3(0.0, top_y, vit_d * 0.5), brass_mat)
			_add_box_mesh(root_mesh, "FrameWest", Vector3(rail_t, rail_t, vit_d), Vector3(-vit_w * 0.5, top_y, 0.0), brass_mat)
			_add_box_mesh(root_mesh, "FrameEast", Vector3(rail_t, rail_t, vit_d), Vector3(vit_w * 0.5, top_y, 0.0), brass_mat)
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					_add_box_mesh(
						root_mesh,
						"CornerPost_%s%s" % ["W" if sx < 0.0 else "E", "N" if sz < 0.0 else "S"],
						Vector3(rail_t, glass_h, rail_t),
						Vector3(sx * vit_w * 0.5, base_h * 0.5 + 0.08 + glass_h * 0.5, sz * vit_d * 0.5),
						brass_mat
					)

		&"partition":
			hull_box.size = Vector3(rect.size.x, height, rect.size.y)
			root_mesh.mesh = hull_box
			root_mesh.material_override = stone_mat
			root_mesh.position = Vector3(rect.get_center().x, height * 0.5, rect.get_center().y)
			cover_root.add_child(root_mesh)

			_add_box_mesh(
				root_mesh,
				"BasePlinth",
				Vector3(rect.size.x * 0.99, 0.24, rect.size.y * 0.99),
				Vector3(0.0, -height * 0.5 + 0.12, 0.0),
				base_mat
			)
			_add_box_mesh(
				root_mesh,
				"TopCoping",
				Vector3(rect.size.x * 0.96, 0.10, rect.size.y * 0.94),
				Vector3(0.0, height * 0.5 + 0.04, 0.0),
				cap_mat
			)
			_add_box_mesh(
				root_mesh,
				"SpineRidge",
				Vector3(rect.size.x * 0.88, 0.06, rect.size.y * 0.36),
				Vector3(0.0, height * 0.5 + 0.11, 0.0),
				base_mat
			)

		&"column":
			hull_box.size = Vector3(rect.size.x, height, rect.size.y)
			root_mesh.mesh = hull_box
			root_mesh.material_override = base_mat
			root_mesh.position = Vector3(rect.get_center().x, height * 0.5, rect.get_center().y)
			cover_root.add_child(root_mesh)

			_add_box_mesh(
				root_mesh,
				"ColumnShaft",
				Vector3(rect.size.x * 0.82, height * 0.88, rect.size.y * 0.82),
				Vector3(0.0, 0.04, 0.0),
				stone_mat
			)
			_add_box_mesh(
				root_mesh,
				"ColumnCapital",
				Vector3(rect.size.x * 0.96, 0.16, rect.size.y * 0.96),
				Vector3(0.0, height * 0.5 + 0.05, 0.0),
				cap_mat
			)
			_add_box_mesh(
				root_mesh,
				"ColumnCapInner",
				Vector3(rect.size.x * 0.72, 0.10, rect.size.y * 0.72),
				Vector3(0.0, height * 0.5 + 0.16, 0.0),
				stone_mat
			)

		&"bench":
			hull_box.size = Vector3(rect.size.x, height, rect.size.y)
			root_mesh.mesh = hull_box
			root_mesh.material_override = base_mat
			root_mesh.position = Vector3(rect.get_center().x, height * 0.5, rect.get_center().y)
			cover_root.add_child(root_mesh)

			var cushion_mat := StandardMaterial3D.new()
			cushion_mat.albedo_color = Color(0.38, 0.31, 0.25)
			cushion_mat.roughness = 0.74
			_add_box_mesh(
				root_mesh,
				"BenchTop",
				Vector3(rect.size.x * 0.94, 0.12, rect.size.y * 0.90),
				Vector3(0.0, height * 0.5 + 0.04, 0.0),
				cushion_mat
			)
			_add_box_mesh(
				root_mesh,
				"BenchCenterRail",
				Vector3(rect.size.x * 0.84, 0.05, rect.size.y * 0.14),
				Vector3(0.0, height * 0.5 + 0.11, 0.0),
				brass_mat
			)

		&"plinth":
			var ped_h := 1.18
			hull_box.size = Vector3(rect.size.x, ped_h, rect.size.y)
			root_mesh.mesh = hull_box
			root_mesh.material_override = stone_mat
			root_mesh.position = Vector3(rect.get_center().x, ped_h * 0.5, rect.get_center().y)
			cover_root.add_child(root_mesh)

			_add_box_mesh(
				root_mesh,
				"PlinthCrown",
				Vector3(rect.size.x * 0.90, 0.12, rect.size.y * 0.90),
				Vector3(0.0, ped_h * 0.5 + 0.06, 0.0),
				cap_mat
			)
			# Classical bust silhouette on top of plinth (matching 11.png PLINTH)
			var bust_mat := StandardMaterial3D.new()
			bust_mat.albedo_color = Color(0.68, 0.66, 0.62)
			bust_mat.roughness = 0.62
			_add_cylinder_mesh(
				root_mesh,
				"BustSocle",
				minf(rect.size.x, rect.size.y) * 0.18,
				minf(rect.size.x, rect.size.y) * 0.22,
				0.14,
				Vector3(0.0, ped_h * 0.5 + 0.18, 0.0),
				base_mat
			)
			_add_box_mesh(
				root_mesh,
				"BustShoulders",
				Vector3(rect.size.x * 0.44, 0.26, rect.size.y * 0.28),
				Vector3(0.0, ped_h * 0.5 + 0.36, 0.0),
				bust_mat
			)
			var head_inst := MeshInstance3D.new()
			head_inst.name = "BustHead"
			var sphere := SphereMesh.new()
			sphere.radius = minf(rect.size.x, rect.size.y) * 0.16
			sphere.height = sphere.radius * 2.3
			head_inst.mesh = sphere
			head_inst.material_override = bust_mat
			head_inst.position = Vector3(0.0, ped_h * 0.5 + 0.66, 0.0)
			root_mesh.add_child(head_inst)

	return root_mesh


func _rebuild_doorways_and_ceremony(def: Dictionary) -> void:
	_clear_node_children(doors_root)
	_clear_node_children(ceremony_root)

	var jamb_mat := StandardMaterial3D.new()
	jamb_mat.albedo_color = Color(0.50, 0.47, 0.43)
	jamb_mat.roughness = 0.74

	var jamb_cap_mat := StandardMaterial3D.new()
	jamb_cap_mat.albedo_color = Color(0.62, 0.59, 0.54)
	jamb_cap_mat.roughness = 0.68

	var gate_mat := StandardMaterial3D.new()
	gate_mat.albedo_color = Color(0.34, 0.30, 0.25)
	gate_mat.roughness = 0.50
	gate_mat.metallic = 0.30

	_exit_beacon_mat = StandardMaterial3D.new()
	_exit_beacon_mat.emission_enabled = true
	_exit_beacon_mat.roughness = 0.65

	_entrance_beacon_mat = StandardMaterial3D.new()
	_entrance_beacon_mat.emission_enabled = true
	_entrance_beacon_mat.roughness = 0.65

	var exit_cfg: Dictionary = def.get("exit_door", {"position": Vector3(0.0, 0.0, -11.8), "width": 6.4})
	var exit_pos: Vector3 = exit_cfg.get("position", Vector3(0.0, 0.0, -11.8))
	_north_door_width = float(exit_cfg.get("width", 6.4))

	# North Exit Doorway (twin doorway piers matching 11.png DOORWAY + threshold + chevrons + sliding gate leaves)
	var north_door := Node3D.new()
	north_door.name = "NorthExitDoorway"
	north_door.position = exit_pos
	doors_root.add_child(north_door)
	_exit_label = Label3D.new()
	_exit_label.position = Vector3(0, 2.3, 0)
	_exit_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_exit_label.font_size = 34
	_exit_label.pixel_size = 0.012
	north_door.add_child(_exit_label)
	set_exit_open(false)

	for side in [-1.0, 1.0]:
		var pier_x: float = float(side) * (_north_door_width * 0.5 + 0.65)
		_add_box_mesh(
			north_door,
			"ExitJamb_%s" % ("L" if side < 0.0 else "R"),
			Vector3(1.2, .08, 1.2),
			Vector3(pier_x, .04, 0.0),
			jamb_mat
		)
		_add_box_mesh(
			north_door,
			"ExitJambCap_%s" % ("L" if side < 0.0 else "R"),
			Vector3(1.32, .035, 1.32),
			Vector3(pier_x, .10, 0.0),
			jamb_cap_mat
		)
	_add_box_mesh(
		north_door,
		"ExitThresholdStrip",
		Vector3(_north_door_width, 0.025, 4.4),
		Vector3(0.0, 0.015, 0.0),
		_exit_beacon_mat
	)
	for c_idx in [-1, 0, 1]:
		_add_box_mesh(
			north_door,
			"ExitChevron_%d" % (c_idx + 2),
			Vector3(0.85, 0.028, 0.30),
			Vector3(float(c_idx) * 1.5, 0.018, 1.25),
			_exit_beacon_mat
		)

	_north_gate_left = _add_box_mesh(
		north_door,
		"NorthGateLeft",
		Vector3(_north_door_width * 0.5, .06, 0.22),
		Vector3(-_north_door_width * 0.25, .045, 0.0),
		gate_mat
	)
	_north_gate_right = _add_box_mesh(
		north_door,
		"NorthGateRight",
		Vector3(_north_door_width * 0.5, .06, 0.22),
		Vector3(_north_door_width * 0.25, .045, 0.0),
		gate_mat
	)

	# South Entrance Doorway (framing player entry passage, no cover inside passage)
	var entrance_cfg: Dictionary = def.get("entrance_door", {"position": Vector3(0.0, 0.0, 12.2), "width": 6.4})
	var entrance_pos: Vector3 = entrance_cfg.get("position", Vector3(0.0, 0.0, 12.2))
	_south_door_width = float(entrance_cfg.get("width", 6.4))

	var south_door := Node3D.new()
	south_door.name = "SouthEntranceDoorway"
	south_door.position = entrance_pos
	doors_root.add_child(south_door)

	for side in [-1.0, 1.0]:
		var s_pier_x: float = float(side) * (_south_door_width * 0.5 + 0.65)
		_add_box_mesh(
			south_door,
			"EntranceJamb_%s" % ("L" if side < 0.0 else "R"),
			Vector3(1.2, .08, 1.2),
			Vector3(s_pier_x, .04, 0.0),
			jamb_mat
		)
		_add_box_mesh(
			south_door,
			"EntranceJambCap_%s" % ("L" if side < 0.0 else "R"),
			Vector3(1.32, .035, 1.32),
			Vector3(s_pier_x, .10, 0.0),
			jamb_cap_mat
		)
	_add_box_mesh(
		south_door,
		"EntranceThresholdStrip",
		Vector3(_south_door_width, 0.025, 0.60),
		Vector3(0.0, 0.015, -0.55),
		_entrance_beacon_mat
	)
	_south_gate_left = _add_box_mesh(
		south_door,
		"SouthGateLeft",
		Vector3(_south_door_width * 0.5, .06, 0.22),
		Vector3(-_south_door_width * 0.25, .045, 0.0),
		gate_mat
	)
	_south_gate_right = _add_box_mesh(
		south_door,
		"SouthGateRight",
		Vector3(_south_door_width * 0.5, .06, 0.22),
		Vector3(_south_door_width * 0.25, .045, 0.0),
		gate_mat
	)

	# Boss court segmented stone/bronze perimeter ring in Burial Exhibition (no solid bright disk!)
	if bool(def.get("is_boss_room", false)):
		_boss_ring_mat = StandardMaterial3D.new()
		_boss_ring_mat.emission_enabled = true
		_boss_ring_mat.roughness = 0.60

		_boss_core_mat = StandardMaterial3D.new()
		_boss_core_mat.emission_enabled = true
		_boss_core_mat.roughness = 0.55

		var seg_count := 16
		var outer_r := 5.6
		var inner_r := 2.6
		for s_i in range(seg_count):
			var angle := (TAU * float(s_i)) / float(seg_count)
			var dir := Vector3(cos(angle), 0.0, sin(angle))
			var outer_seg := _add_box_mesh(
				ceremony_root,
				"BossOuterRingSeg_%02d" % (s_i + 1),
				Vector3(0.26, 0.025, 1.95),
				Vector3(0.0, 0.014, -2.0) + dir * outer_r,
				_boss_ring_mat
			)
			outer_seg.rotation_degrees = Vector3(0.0, -rad_to_deg(angle), 0.0)

			var inner_seg := _add_box_mesh(
				ceremony_root,
				"BossInnerRingSeg_%02d" % (s_i + 1),
				Vector3(0.22, 0.028, 0.92),
				Vector3(0.0, 0.016, -2.0) + dir * inner_r,
				_boss_core_mat
			)
			inner_seg.rotation_degrees = Vector3(0.0, -rad_to_deg(angle), 0.0)
	else:
		_boss_ring_mat = null
		_boss_core_mat = null


func _update_gate_and_cue_visuals() -> void:
	var is_boss := bool(active_definition.get("is_boss_room", false))
	var north_closed := 0.0 if exit_open else (gates_closed_ratio if is_boss else 1.0)
	var south_closed := (0.0 if exit_open else gates_closed_ratio) if is_boss else 0.0

	if _north_gate_left != null and _north_gate_right != null:
		var half_w := _north_door_width * 0.5
		var open_offset := (1.0 - north_closed) * (half_w * 0.92)
		_north_gate_left.position.x = -half_w * 0.5 - open_offset
		_north_gate_right.position.x = half_w * 0.5 + open_offset
		_north_gate_left.visible = north_closed > 0.02
		_north_gate_right.visible = north_closed > 0.02

	if _south_gate_left != null and _south_gate_right != null:
		var s_half_w := _south_door_width * 0.5
		var s_open_offset := (1.0 - south_closed) * (s_half_w * 0.92)
		_south_gate_left.position.x = -s_half_w * 0.5 - s_open_offset
		_south_gate_right.position.x = s_half_w * 0.5 + s_open_offset
		_south_gate_left.visible = south_closed > 0.02
		_south_gate_right.visible = south_closed > 0.02

	if _exit_beacon_mat != null:
		if exit_open:
			var ready_col := Color(0.18, 0.75, 0.42)
			_exit_beacon_mat.albedo_color = ready_col
			_exit_beacon_mat.emission = ready_col
			_exit_beacon_mat.emission_energy_multiplier = 0.65
		else:
			var locked_col := Color(0.42, 0.34, 0.28)
			_exit_beacon_mat.albedo_color = locked_col
			_exit_beacon_mat.emission = locked_col
			_exit_beacon_mat.emission_energy_multiplier = 0.10

	if _entrance_beacon_mat != null:
		var ent_col := Color(0.42, 0.34, 0.28) if (is_boss and south_closed > 0.1) else Color(0.34, 0.36, 0.38)
		_entrance_beacon_mat.albedo_color = ent_col
		_entrance_beacon_mat.emission = ent_col
		_entrance_beacon_mat.emission_energy_multiplier = 0.12 if is_boss else 0.06

	if _boss_ring_mat != null and _boss_core_mat != null:
		var ring_col := Color(0.50, 0.42, 0.32) if boss_ceremony_state == &"active" else Color(0.32, 0.28, 0.25)
		_boss_ring_mat.albedo_color = ring_col
		_boss_ring_mat.emission = ring_col
		_boss_ring_mat.emission_energy_multiplier = lerpf(0.05, 0.24, boss_activation_glow)

		var core_col := Color(0.58, 0.48, 0.36) if boss_ceremony_state == &"active" else Color(0.36, 0.31, 0.27)
		_boss_core_mat.albedo_color = core_col
		_boss_core_mat.emission = core_col
		_boss_core_mat.emission_energy_multiplier = lerpf(0.05, 0.28, boss_activation_glow)


func _add_box_mesh(parent: Node3D, node_name: String, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	inst.name = node_name
	var box := BoxMesh.new()
	box.size = size
	inst.mesh = box
	inst.material_override = mat
	inst.position = pos
	parent.add_child(inst)
	return inst


func _add_cylinder_mesh(parent: Node3D, node_name: String, top_r: float, bottom_r: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	inst.name = node_name
	var cyl := CylinderMesh.new()
	cyl.top_radius = top_r
	cyl.bottom_radius = bottom_r
	cyl.height = height
	cyl.radial_segments = 32
	inst.mesh = cyl
	inst.material_override = mat
	inst.position = pos
	parent.add_child(inst)
	return inst
