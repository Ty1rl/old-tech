extends "res://scenes/prototype/museum_environment.gd"

# Four-room museum presentation, partner prop integration, green floor exit arrows,
# and per-room NavigationRegion3D in group museum_navigation (Round P Wave A — JAM-2).

const Rooms = preload("res://scenes/prototype/rooms.gd")
const ToolStyle = preload("res://scenes/prototype/tool_style.gd")

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
const WALL_BANNER_SCENE := preload("res://scenes/rooms/wall_banner.tscn")
const EXIT_FLOOR_ARROW_SCENE := preload("res://scenes/rooms/exit_floor_arrow.tscn")

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
var banners_root: Node3D
var exit_arrows_root: Node3D

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
var _prepared_archway_mesh: ArrayMesh

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
	"DRAWING CUTTER",
	"FLASH CAMERA",
	"HEAT BELLOWS",
	"TIME DEVICE",
]
const PICKUP_COLORS := [
	ToolStyle.RING,
	ToolStyle.BEAM,
	ToolStyle.CONE,
	ToolStyle.CLOCK,
]


func build(_include_cover_decorations: bool = false) -> Node3D:
	return super.build(false)


func _ready() -> void:
	if not _built:
		build(false)
		apply_room(Rooms.definitions()[0])
	if get_world_3d() != null:
		NavigationServer3D.map_set_active(get_world_3d().navigation_map, true)


func apply_to_arena(arena: Node3D, hide_placeholder_meshes: bool = true) -> void:
	if is_instance_valid(arena):
		for child in arena.get_children():
			if child != self and child is Node3D:
				for sub in child.find_children("*", "NavigationRegion3D", true, false):
					if sub is NavigationRegion3D:
						(sub as NavigationRegion3D).remove_from_group(&"museum_navigation")
						(sub as NavigationRegion3D).enabled = false
	super.apply_to_arena(arena, hide_placeholder_meshes)


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
	label.text = PICKUP_NAMES[clampi(tool - 1, 0, PICKUP_NAMES.size() - 1)]
	label.position = Vector3(0.0, 2.55, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 30
	label.pixel_size = 0.0085
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

	_sync_navigation_region()


func set_exit_open(open: bool) -> void:
	var was_open := exit_open
	exit_open = open
	if open and boss_ceremony_state == &"inactive":
		gates_closed_ratio = 0.0
	elif not open and boss_ceremony_state == &"inactive":
		gates_closed_ratio = 1.0
	_update_gate_and_cue_visuals()
	_sync_navigation_region()
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
	_sync_navigation_region()


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
	_sync_navigation_region()


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
	if banners_root == null or not is_instance_valid(banners_root):
		banners_root = Node3D.new()
		banners_root.name = "WallBanners"
		add_child(banners_root)
	if exit_arrows_root == null or not is_instance_valid(exit_arrows_root):
		exit_arrows_root = Node3D.new()
		exit_arrows_root.name = "ExitFloorArrows"
		add_child(exit_arrows_root)


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
	_clear_node_children(banners_root)
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
			if kind == &"bench":
				# Keep the partner bench's long backrest aligned with the longer dimension of rect
				# and facing inward toward the central combat floor while preserving the exact Rect2 footprint.
				if rect.size.x > rect.size.y:
					scale_root.rotation_degrees = Vector3(0.0, -90.0 if rect.get_center().y < 0.0 else 90.0, 0.0)
					scale_root.scale = Vector3(rect.size.y, 1.0, rect.size.x)
				else:
					scale_root.rotation_degrees = Vector3(0.0, 180.0 if rect.get_center().x > 0.0 else 0.0, 0.0)
					scale_root.scale = Vector3(rect.size.x, 1.0, rect.size.y)
			else:
				scale_root.scale = Vector3(rect.size.x, 1.0, rect.size.y)
		else:
			kit_node.scale = Vector3(rect.size.x, 1.0, rect.size.y)

		var part_banner := kit_node.get_node_or_null("BannerModel") as Node3D
		if part_banner != null:
			# Mount partition banner facing inward toward the room center
			var inward_sign: float = 1.0 if rect.get_center().x < 0.0 else -1.0
			part_banner.position = Vector3(inward_sign * (rect.size.x * 0.5 + 0.14), 1.36, 0.0)
			part_banner.rotation_degrees = Vector3(0.0, 90.0 if inward_sign > 0.0 else -90.0, 0.0)

		_prepare_partner_prop_materials(kit_node)
		cover_root.add_child(kit_node)

	# Place perimeter wall banners along West and East colonnade bays
	var banner_slots := [
		{"name": "WestNorthBanner", "pos": Vector3(-19.2, 0.0, -6.5), "rot_y": 90.0},
		{"name": "WestSouthBanner", "pos": Vector3(-19.2, 0.0, 5.5), "rot_y": 90.0},
		{"name": "EastNorthBanner", "pos": Vector3(19.2, 0.0, -6.5), "rot_y": -90.0},
		{"name": "EastSouthBanner", "pos": Vector3(19.2, 0.0, 5.5), "rot_y": -90.0},
	]
	for slot in banner_slots:
		var wb := WALL_BANNER_SCENE.instantiate() as Node3D
		wb.name = String(slot["name"])
		wb.position = slot["pos"] as Vector3
		wb.rotation_degrees = Vector3(0.0, float(slot["rot_y"]), 0.0)
		_prepare_partner_prop_materials(wb)
		banners_root.add_child(wb)


func _prepare_partner_prop_materials(root_node: Node) -> void:
	for child in root_node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if mi.get_surface_override_material_count() > 0 and mi.get_surface_override_material(0) != null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			var src_mat: Material = mi.mesh.surface_get_material(s)
			if src_mat is StandardMaterial3D:
				var dup := (src_mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				dup.cull_mode = BaseMaterial3D.CULL_DISABLED
				dup.roughness = clampf(dup.roughness, 0.45, 0.82)
				mi.set_surface_override_material(s, dup)


func _prepare_archway_visuals(door_node: Node3D) -> void:
	if door_node == null:
		return
	var arch_root := door_node.get_node_or_null("ArchwayModel") as Node3D
	if arch_root != null:
		for child in arch_root.find_children("*", "MeshInstance3D", true, false):
			var mi := child as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			if _prepared_archway_mesh == null:
				_prepared_archway_mesh = _prepare_mesh(
					mi.mesh,
					true,
					Color(1.42, 1.32, 1.18),
					0.68,
					false
				)
			mi.mesh = _prepared_archway_mesh
	_prepare_partner_prop_materials(door_node)


func _rebuild_doorways_and_ceremony(def: Dictionary) -> void:
	_clear_node_children(doors_root)
	_clear_node_children(ceremony_root)
	_clear_node_children(boundary_root)
	_clear_node_children(exit_arrows_root)

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
	_prepare_archway_visuals(_north_door_node)
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
	_prepare_archway_visuals(_south_door_node)
	doors_root.add_child(_south_door_node)

	_south_gate_left = _south_door_node.get_node_or_null("SouthGateLeft") as MeshInstance3D
	_south_gate_right = _south_door_node.get_node_or_null("SouthGateRight") as MeshInstance3D
	var ceremony_beacon := _south_door_node.get_node_or_null("CeremonyBeacon") as MeshInstance3D
	_entrance_beacon_mat = ceremony_beacon.get_surface_override_material(0) as StandardMaterial3D if ceremony_beacon != null else null

	# Instantiate authored PerimeterBoundary colliders with north-wall gap aligned to exit_pos.x
	var boundary := PERIMETER_BOUNDARY_SCENE.instantiate() as Node3D
	boundary_root.add_child(boundary)
	_configure_north_wall_collider_gap(boundary, exit_pos.x, _north_door_width)

	# Build modest green floor arrows guiding toward the actual open north door
	_rebuild_exit_floor_arrows(def, exit_pos)

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


func _rebuild_exit_floor_arrows(def: Dictionary, exit_pos: Vector3) -> void:
	_clear_node_children(exit_arrows_root)
	var waypoints := _compute_exit_arrow_waypoints(def, exit_pos)
	for i in range(waypoints.size()):
		var pt: Vector3 = waypoints[i]
		var next_pt: Vector3 = waypoints[i + 1] if (i + 1) < waypoints.size() else Vector3(exit_pos.x, 0.018, exit_pos.z)
		var arrow := EXIT_FLOOR_ARROW_SCENE.instantiate() as Node3D
		arrow.name = "ExitArrow_%02d" % (i + 1)
		arrow.position = Vector3(pt.x, 0.018, pt.z)
		var dir := Vector3(next_pt.x - pt.x, 0.0, next_pt.z - pt.z)
		if dir.length_squared() > 0.0001:
			# Local -Z points along dir toward the next waypoint / open north doorway
			arrow.rotation = Vector3(0.0, atan2(-dir.x, -dir.z), 0.0)
		for sub in arrow.find_children("*", "MeshInstance3D", true, false):
			var mi := sub as MeshInstance3D
			if mi != null:
				var mat := mi.get_surface_override_material(0) as StandardMaterial3D
				if mat != null:
					mat.albedo_color = ToolStyle.EXIT
					mat.emission = ToolStyle.EXIT
		exit_arrows_root.add_child(arrow)
	exit_arrows_root.visible = exit_open


func _compute_exit_arrow_waypoints(def: Dictionary, exit_pos: Vector3) -> Array[Vector3]:
	var spawn: Vector3 = def.get("player_spawn", Vector3(0.0, 0.55, 8.5))
	var start_x: float = clampf(spawn.x * 0.12 + exit_pos.x * 0.12, -3.5, 3.5)
	var z_steps: Array[float] = [2.2, -4.4, -11.0, -16.8]
	var pts: Array[Vector3] = []
	var prev_x: float = start_x
	for idx in range(z_steps.size()):
		var t: float = float(idx + 1) / float(z_steps.size() + 1)
		var z_val: float = z_steps[idx]
		var desired_x: float = lerpf(start_x, exit_pos.x, t)
		var clear_x: float = _resolve_clear_arrow_x(desired_x, z_val, prev_x, z_steps[idx - 1] if idx > 0 else 5.0)
		pts.append(Vector3(clear_x, 0.018, z_val))
		prev_x = clear_x
	return pts


func _resolve_clear_arrow_x(desired_x: float, z_val: float, prev_x: float, prev_z: float) -> float:
	if not _segment_hits_any_cover(Vector2(prev_x, prev_z), Vector2(desired_x, z_val), 0.85):
		return desired_x
	for offset in [0.0, -2.5, 2.5, -5.0, 5.0, -7.5, 7.5, -9.5, 9.5]:
		var cand_x: float = clampf(desired_x + offset, -10.5, 10.5)
		if not _segment_hits_any_cover(Vector2(prev_x, prev_z), Vector2(cand_x, z_val), 0.85):
			return cand_x
	return desired_x


func _segment_hits_any_cover(a: Vector2, b: Vector2, margin: float = 0.65) -> bool:
	for rect in active_cover_rectangles:
		var grown: Rect2 = rect.grow(margin)
		if grown.has_point(a) or grown.has_point(b):
			return true
		for s_i in range(1, 16):
			var p: Vector2 = a.lerp(b, float(s_i) / 16.0)
			if grown.has_point(p):
				return true
	return false


func get_exit_arrow_nodes() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if exit_arrows_root == null or not is_instance_valid(exit_arrows_root):
		return out
	for child in exit_arrows_root.get_children():
		if child is Node3D:
			out.append(child as Node3D)
	return out


func _sync_navigation_region() -> void:
	var exit_cfg: Dictionary = active_definition.get("exit_door", {"position": Vector3(0.0, 0.0, -19.5), "width": 4.4})
	var exit_pos: Vector3 = exit_cfg.get("position", Vector3(0.0, 0.0, -19.5))
	var exit_w: float = float(exit_cfg.get("width", 4.4))
	_ensure_navigation_region(active_cover_rectangles, exit_open, exit_pos, exit_w)


func find_navigation_path(from_point: Vector3, to_point: Vector3) -> PackedVector3Array:
	if navigation_region == null or not is_instance_valid(navigation_region):
		_sync_navigation_region()
	if get_world_3d() == null:
		return PackedVector3Array()
	var map_rid: RID = navigation_region.get_navigation_map()
	NavigationServer3D.map_set_active(map_rid, true)
	return NavigationServer3D.map_get_path(map_rid, from_point, to_point, true)


func get_placed_partner_asset_counts() -> Dictionary:
	var counts := {
		"archway": 0,
		"bench": 0,
		"displaycase": 0,
		"planetDiorama": 0,
		"banner": 0,
	}
	for node in find_children("*", "Node3D", true, false):
		var path: String = node.scene_file_path
		if path == "res://assets/archway/archway.glb" or node.name == "ArchwayModel":
			counts["archway"] += 1
		elif path == "res://assets/props/bench.glb" or node.name == "BenchModel":
			counts["bench"] += 1
		elif path == "res://assets/props/displaycase.glb" or node.name == "DisplayCaseModel":
			counts["displaycase"] += 1
		elif path == "res://assets/props/planetDiorama.glb" or node.name == "PlanetDioramaModel":
			counts["planetDiorama"] += 1
		elif path == "res://assets/props/banner_V5_TEMP.001.glb" or node.name == "BannerModel":
			counts["banner"] += 1
	return counts


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

	if exit_arrows_root != null and is_instance_valid(exit_arrows_root):
		exit_arrows_root.visible = exit_open

	if _exit_label != null:
		_exit_label.modulate = ToolStyle.EXIT

	if _south_gate_left != null and _south_gate_right != null:
		var s_half_w := _south_door_width * 0.5
		var s_open_offset := (1.0 - south_closed) * (s_half_w * 0.92)
		_south_gate_left.position.x = -0.75 - s_open_offset
		_south_gate_right.position.x = 0.75 + s_open_offset
		_south_gate_left.visible = south_closed > 0.02
		_south_gate_right.visible = south_closed > 0.02

	if _exit_beacon_mat != null:
		if exit_open:
			var ready_col: Color = ToolStyle.EXIT
			_exit_beacon_mat.albedo_color = ready_col
			_exit_beacon_mat.emission = ready_col
			_exit_beacon_mat.emission_energy_multiplier = 0.95
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
