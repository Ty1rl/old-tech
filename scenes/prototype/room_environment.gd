extends "res://scenes/prototype/museum_environment.gd"

# Four-room museum presentation and physical campaign wayfinding (Round O Wave A — JAM-2).
# Uses authored kit scenes under res://scenes/rooms/ and a real top/north-wall exit opening
# whose visuals and StaticBody3D colliders agree when closed vs open.

const Rooms = preload("res://scenes/prototype/rooms.gd")

const KIT_SCENES := {
	&"display_island": preload("res://scenes/rooms/display_island.tscn"),
	&"partition": preload("res://scenes/rooms/partition.tscn"),
	&"column": preload("res://scenes/rooms/column.tscn"),
	&"bench": preload("res://scenes/rooms/bench.tscn"),
	&"plinth": preload("res://scenes/rooms/plinth.tscn"),
}
const NORTH_EXIT_SCENE := preload("res://scenes/rooms/north_exit_doorway.tscn")
const SOUTH_ENTRANCE_SCENE := preload("res://scenes/rooms/south_entrance_doorway.tscn")
const FLOOR_ACCENTS_SCENE := preload("res://scenes/rooms/floor_accents.tscn")
const BOSS_COURT_RING_SCENE := preload("res://scenes/rooms/boss_court_ring.tscn")
const PERIMETER_BOUNDARY_SCENE := preload("res://scenes/rooms/perimeter_boundary.tscn")
const TOOL_PICKUP_SCENE := preload("res://scenes/rooms/tool_pickup_pedestal.tscn")

signal exit_state_changed(open: bool)
signal room_completed(room_id: StringName)
signal combat_event(kind: StringName, point: Vector3, strength: float)
signal gates_closed(room_id: StringName)
signal boss_activated(room_id: StringName)

const GATE_CLOSE_DURATION := 0.60
const BOSS_PAUSE_DURATION := 0.50

var floor_accents_root: Node3D
var doors_root: Node3D
var ceremony_root: Node3D
var boundary_root: Node3D

var active_room_id: StringName = &"gallery"
var active_definition: Dictionary = {}
var active_cover_rectangles: Array[Rect2] = []
var _arena_owner: Node3D

var exit_open: bool = false
var boss_ceremony_state: StringName = &"inactive"
var boss_ceremony_timer: float = 0.0
var gates_closed_ratio: float = 0.0
var boss_activation_glow: float = 0.0

var _north_door_node: Node3D
var _south_door_node: Node3D
var _north_gate_left: MeshInstance3D
var _north_gate_right: MeshInstance3D
var _south_gate_left: MeshInstance3D
var _south_gate_right: MeshInstance3D
var _exit_cue_root: Node3D
var _gate_blocker_shape: CollisionShape3D
var _exit_beacon_mat: StandardMaterial3D
var _entrance_beacon_mat: StandardMaterial3D
var _boss_ring_mat: StandardMaterial3D
var _boss_core_mat: StandardMaterial3D
var _north_door_width: float = 4.4
var _south_door_width: float = 4.4
var _exit_label: Label3D

var pickup_root: Node3D
var pickup_tool := 0
var pickup_position := Vector3.ZERO
const PICKUP_MODELS = [
	preload("res://assets/equipment/ring_caster.glb"),
	preload("res://assets/equipment/flash_camera.glb"),
	preload("res://assets/equipment/heat_bellows.glb"),
	preload("res://assets/equipment/time_device.glb"),
]
const PICKUP_NAMES := [
	"BLUE · DRAWING CUTTER",
	"YELLOW · FLASH CAMERA",
	"ORANGE · HEAT BELLOWS",
	"PURPLE · TIME DEVICE",
]
const PICKUP_COLORS := [
	Color("60dbde"),
	Color("f0d77b"),
	Color("ed9966"),
	Color("ba9ce9"),
]


func build(_include_cover_decorations: bool = false) -> Node3D:
	return super.build(false)


func _ready() -> void:
	if not _built:
		build(false)
		apply_room(Rooms.definitions()[0])


func show_tool_pickup(tool: int, point: Vector3) -> void:
	clear_tool_pickup()
	pickup_tool = tool
	pickup_position = Vector3(point.x, 0.0, point.z)
	pickup_root = TOOL_PICKUP_SCENE.instantiate() as Node3D
	pickup_root.name = "ToolPickup_%d" % tool
	pickup_root.position = pickup_position
	pickup_root.visible = true
	add_child(pickup_root)

	var col: Color = PICKUP_COLORS[clampi(tool - 1, 0, PICKUP_COLORS.size() - 1)]
	var ring := pickup_root.get_node_or_null("GlowRing") as MeshInstance3D
	if ring != null:
		var ring_mat := ring.get_surface_override_material(0) as StandardMaterial3D
		if ring_mat != null:
			ring_mat.albedo_color = col
			ring_mat.emission = col
	var light := pickup_root.get_node_or_null("PickupLight") as OmniLight3D
	if light != null:
		light.light_color = col

	var holder := pickup_root.get_node_or_null("ToolHolder") as Node3D
	var prop_parent: Node3D = holder if holder != null else pickup_root
	var prop: Node3D = PICKUP_MODELS[clampi(tool - 1, 0, PICKUP_MODELS.size() - 1)].instantiate()
	prop.position = Vector3.ZERO if holder != null else Vector3(0.0, 1.05, 0.0)
	prop.rotation_degrees = Vector3(0.0, -25.0, 0.0)
	prop.scale = Vector3.ONE * 1.7
	prop_parent.add_child(prop)

	var label := Label3D.new()
	label.text = "%s\nWalk into the light to collect" % PICKUP_NAMES[clampi(tool - 1, 0, PICKUP_NAMES.size() - 1)]
	label.position = Vector3(0.0, 2.7, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 32
	label.pixel_size = 0.009
	label.modulate = col
	pickup_root.add_child(label)


func clear_tool_pickup() -> void:
	if is_instance_valid(pickup_root):
		remove_child(pickup_root)
		pickup_root.queue_free()
	pickup_root = null
	pickup_tool = 0


func player_in_exit(point: Vector3) -> bool:
	if not exit_open:
		return false
	var exit_cfg: Dictionary = active_definition.get("exit_door", {})
	var door: Vector3 = exit_cfg.get("position", Vector3(0.0, 0.0, -19.5))
	# Trigger region sits inside the open north-wall doorway threshold/gap.
	# Closed GateBlockerBody stops the player south of door.z + 0.85 (around z = door.z + 1.22).
	return (
		absf(point.x - door.x) <= _north_door_width * 0.45
		and point.z <= door.z + 0.85
		and point.z >= door.z - 2.4
	)


func is_exit_physically_blocked() -> bool:
	return _gate_blocker_shape != null and not _gate_blocker_shape.disabled


func apply_room(definition: Dictionary, cover_ref: RefCounted = null, arena_node: Node3D = null) -> void:
	if not _built:
		build(false)
	_ensure_room_roots()
	clear_tool_pickup()

	var def := definition if not definition.is_empty() else Rooms.definitions()[0]
	active_definition = def.duplicate(true)
	active_room_id = def.get("id", &"gallery")
	_arena_owner = arena_node if arena_node != null else (get_parent() as Node3D)

	active_cover_rectangles.clear()
	var raw_cover: Array = def.get("cover", Cover.RECTANGLES)
	for item in raw_cover:
		if item is Rect2:
			active_cover_rectangles.append(item)

	var target_cover := cover_ref
	if target_cover == null and _arena_owner != null and "cover" in _arena_owner:
		target_cover = _arena_owner.get("cover")
	if target_cover != null and target_cover.has_method("set_rectangles"):
		target_cover.set_rectangles(active_cover_rectangles)

	_apply_floor_and_lighting(def, _arena_owner)
	_rebuild_room_cover(def)
	_rebuild_doorways_and_ceremony(def)

	if bool(def.get("is_boss_room", false)):
		start_boss_entrance()
	else:
		boss_ceremony_state = &"inactive"
		boss_ceremony_timer = 0.0
		gates_closed_ratio = 1.0
		boss_activation_glow = 0.0
		exit_open = false
		_update_gate_and_cue_visuals()


func set_exit_open(open: bool) -> void:
	var was_open := exit_open
	exit_open = open
	if open and boss_ceremony_state == &"inactive":
		gates_closed_ratio = 0.0
	elif not open and boss_ceremony_state == &"inactive":
		gates_closed_ratio = 1.0
	_update_gate_and_cue_visuals()
	exit_state_changed.emit(exit_open)
	if exit_open and not was_open:
		var exit_pos: Vector3 = active_definition.get("exit_door", {}).get("position", Vector3(0.0, 0.0, -19.5))
		room_completed.emit(active_room_id)
		combat_event.emit(&"room_complete", exit_pos, 1.0)


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
	if boundary_root == null or not is_instance_valid(boundary_root):
		boundary_root = Node3D.new()
		boundary_root.name = "PerimeterBoundaryRoot"
		add_child(boundary_root)


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

	var accents_inst := FLOOR_ACCENTS_SCENE.instantiate() as Node3D
	floor_accents_root.add_child(accents_inst)

	for border_name in ["BorderNorth", "BorderSouth", "BorderWest", "BorderEast"]:
		var b_mesh := accents_inst.get_node_or_null(border_name) as MeshInstance3D
		if b_mesh != null:
			var b_mat := b_mesh.get_surface_override_material(0) as StandardMaterial3D
			if b_mat != null:
				b_mat.albedo_color = border_col

	for style_key in [&"aisle", &"cross_hall", &"work_bays", &"boss_court"]:
		var group := accents_inst.get_node_or_null("Style_" + String(style_key)) as Node3D
		if group != null:
			group.visible = (style_key == style)
			for child in group.get_children():
				if child is MeshInstance3D:
					var mat := child.get_surface_override_material(0) as StandardMaterial3D
					if mat != null:
						mat.albedo_color = border_col if child.name == "OuterCourtRing" else accent_col

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
		var packed: PackedScene = KIT_SCENES.get(kind, KIT_SCENES[&"display_island"])
		var kit_node := packed.instantiate() as Node3D
		kit_node.name = "Cover_%02d_%s" % [i + 1, String(kind)]
		kit_node.position = Vector3(rect.get_center().x, 0.0, rect.get_center().y)
		var scale_root := kit_node.get_node_or_null("ScaleRoot") as Node3D
		if scale_root != null:
			scale_root.scale = Vector3(rect.size.x, 1.0, rect.size.y)
		else:
			kit_node.scale = Vector3(rect.size.x, 1.0, rect.size.y)
		cover_root.add_child(kit_node)


func _rebuild_doorways_and_ceremony(def: Dictionary) -> void:
	_clear_node_children(doors_root)
	_clear_node_children(ceremony_root)
	_clear_node_children(boundary_root)

	var exit_cfg: Dictionary = def.get("exit_door", {"position": Vector3(0.0, 0.0, -19.5), "width": 4.4})
	var exit_pos: Vector3 = exit_cfg.get("position", Vector3(0.0, 0.0, -19.5))
	_north_door_width = float(exit_cfg.get("width", 4.4))

	var entrance_cfg: Dictionary = def.get("entrance_door", {"position": Vector3(0.0, 0.0, 19.2), "width": 4.4})
	var entrance_pos: Vector3 = entrance_cfg.get("position", Vector3(0.0, 0.0, 19.2))
	_south_door_width = float(entrance_cfg.get("width", 4.4))

	# Open architectural gap in NorthWall/NorthColumn at the north exit doorway
	set_perimeter_openings(exit_pos.x, _north_door_width, entrance_pos.x, _south_door_width)

	# Instantiate authored North Exit Doorway at room north boundary
	_north_door_node = NORTH_EXIT_SCENE.instantiate() as Node3D
	_north_door_node.name = "NorthExitDoorway"
	_north_door_node.position = exit_pos
	doors_root.add_child(_north_door_node)

	_north_gate_left = _north_door_node.get_node_or_null("NorthGateLeft") as MeshInstance3D
	_north_gate_right = _north_door_node.get_node_or_null("NorthGateRight") as MeshInstance3D
	_exit_cue_root = _north_door_node.get_node_or_null("ExitCueRoot") as Node3D
	_exit_label = _north_door_node.get_node_or_null("ExitCueRoot/ExitLabel") as Label3D
	_gate_blocker_shape = _north_door_node.get_node_or_null("GateBlockerBody/GateBlockerShape") as CollisionShape3D
	var exit_beacon := _north_door_node.get_node_or_null("ExitCueRoot/ExitBeacon") as MeshInstance3D
	_exit_beacon_mat = exit_beacon.get_surface_override_material(0) as StandardMaterial3D if exit_beacon != null else null

	# Instantiate authored South Entrance Doorway at room south boundary
	_south_door_node = SOUTH_ENTRANCE_SCENE.instantiate() as Node3D
	_south_door_node.name = "SouthEntranceDoorway"
	_south_door_node.position = entrance_pos
	doors_root.add_child(_south_door_node)

	_south_gate_left = _south_door_node.get_node_or_null("SouthGateLeft") as MeshInstance3D
	_south_gate_right = _south_door_node.get_node_or_null("SouthGateRight") as MeshInstance3D
	var ceremony_beacon := _south_door_node.get_node_or_null("CeremonyBeacon") as MeshInstance3D
	_entrance_beacon_mat = ceremony_beacon.get_surface_override_material(0) as StandardMaterial3D if ceremony_beacon != null else null

	# Instantiate authored PerimeterBoundary colliders with north-wall gap aligned to exit_pos.x
	var boundary := PERIMETER_BOUNDARY_SCENE.instantiate() as Node3D
	boundary_root.add_child(boundary)
	_configure_north_wall_collider_gap(boundary, exit_pos.x, _north_door_width)

	# Boss court ring in Burial Exhibition
	if bool(def.get("is_boss_room", false)):
		var court_ring := BOSS_COURT_RING_SCENE.instantiate() as Node3D
		ceremony_root.add_child(court_ring)
		var outer_ring := court_ring.get_node_or_null("OuterRing") as MeshInstance3D
		var inner_ring := court_ring.get_node_or_null("InnerRing") as MeshInstance3D
		_boss_ring_mat = outer_ring.get_surface_override_material(0) as StandardMaterial3D if outer_ring != null else null
		_boss_core_mat = inner_ring.get_surface_override_material(0) as StandardMaterial3D if inner_ring != null else null
	else:
		_boss_ring_mat = null
		_boss_core_mat = null


func _configure_north_wall_collider_gap(boundary: Node3D, gap_x: float, gap_width: float) -> void:
	var half_gap := gap_width * 0.45
	var left_edge := -20.5
	var right_edge := 20.5
	var left_end := gap_x - half_gap
	var right_start := gap_x + half_gap

	var nw_body := boundary.get_node_or_null("NorthWestWallBody") as StaticBody3D
	var nw_shape := boundary.get_node_or_null("NorthWestWallBody/NorthWestWallShape") as CollisionShape3D
	if nw_body != null and nw_shape != null and nw_shape.shape is BoxShape3D:
		var nw_w := maxf(0.5, left_end - left_edge)
		(nw_shape.shape as BoxShape3D).size = Vector3(nw_w, 3.0, 1.8)
		nw_body.position = Vector3(left_edge + nw_w * 0.5, 1.5, -19.6)

	var ne_body := boundary.get_node_or_null("NorthEastWallBody") as StaticBody3D
	var ne_shape := boundary.get_node_or_null("NorthEastWallBody/NorthEastWallShape") as CollisionShape3D
	if ne_body != null and ne_shape != null and ne_shape.shape is BoxShape3D:
		var ne_w := maxf(0.5, right_edge - right_start)
		(ne_shape.shape as BoxShape3D).size = Vector3(ne_w, 3.0, 1.8)
		ne_body.position = Vector3(right_start + ne_w * 0.5, 1.5, -19.6)


func _update_gate_and_cue_visuals() -> void:
	var is_boss := bool(active_definition.get("is_boss_room", false))
	var north_closed := 0.0 if exit_open else (gates_closed_ratio if is_boss else 1.0)
	var south_closed := (0.0 if exit_open else gates_closed_ratio) if is_boss else 0.0

	if _north_gate_left != null and _north_gate_right != null:
		var half_w := _north_door_width * 0.5
		var open_offset := (1.0 - north_closed) * (half_w * 0.92)
		_north_gate_left.position.x = -0.95 - open_offset
		_north_gate_right.position.x = 0.95 + open_offset
		_north_gate_left.visible = north_closed > 0.02
		_north_gate_right.visible = north_closed > 0.02

	if _gate_blocker_shape != null:
		_gate_blocker_shape.disabled = exit_open

	if _exit_cue_root != null:
		_exit_cue_root.visible = exit_open

	if _south_gate_left != null and _south_gate_right != null:
		var s_half_w := _south_door_width * 0.5
		var s_open_offset := (1.0 - south_closed) * (s_half_w * 0.92)
		_south_gate_left.position.x = -0.75 - s_open_offset
		_south_gate_right.position.x = 0.75 + s_open_offset
		_south_gate_left.visible = south_closed > 0.02
		_south_gate_right.visible = south_closed > 0.02

	if _exit_beacon_mat != null:
		if exit_open:
			var ready_col := Color(0.24, 0.84, 0.52)
			_exit_beacon_mat.albedo_color = ready_col
			_exit_beacon_mat.emission = ready_col
			_exit_beacon_mat.emission_energy_multiplier = 1.15
		else:
			var locked_col := Color(0.32, 0.28, 0.24)
			_exit_beacon_mat.albedo_color = locked_col
			_exit_beacon_mat.emission = locked_col
			_exit_beacon_mat.emission_energy_multiplier = 0.0

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


func get_cover_world_rectangles() -> Array[Rect2]:
	return active_cover_rectangles.duplicate()
