extends Node3D

# No independent _process or _physics_process clock.
const Tuning = preload("res://scenes/prototype/tuning.gd")
const CoverScript = preload("res://scenes/prototype/cover.gd")
const WardenVisual = preload("res://scenes/prototype/warden_visual.gd")
const PartVisual = preload("res://scenes/prototype/part_visual.gd")
const PLAYER_CONTACT_RADIUS := 0.5
const MAX_KNOCKBACK_SPEED := 32.0

var cover: RefCounted

var rewind_id: int = 1
var kind: StringName = &"target"
var radius: float = 0.7
var max_health: float = 100.0
var health: float = 100.0
var move_speed: float = 0.0
var contact_damage: float = 0.0
var contact_cooldown: float = 0.0
var cable_cut: bool = false
var shield_heat: float = 0.0
var shield_open_timer: float = 0.0
var core_broken: bool = false
var warden_visual: Node3D
var part_visual: Node3D
var plate_broken := false
var attack_phase: StringName = &"approach"
var attack_timer := 0.0
var status_root: Node3D

# Crowd control / knockback / stagger state (world units and world seconds)
var knockback_vel: Vector3 = Vector3.ZERO
var stagger_timer: float = 0.0

var facing: Vector3 = Vector3(0.0, 0.0, 1.0):
	set(value):
		var flat := Vector3(value.x, 0.0, value.z)
		if flat.length_squared() > 0.000001:
			facing = flat.normalized()
		else:
			facing = Vector3(0.0, 0.0, 1.0)
		_update_visual_facing()

# Skirmisher finite orbit -> commit cycle state (world seconds)
var skirmish_phase: StringName = &"orbit" # &"orbit" or &"commit"
var skirmish_timer: float = 0.0
var skirmish_strafe_sign: float = 1.0
const SKIRMISH_ORBIT_DURATION := 1.4
const SKIRMISH_COMMIT_DURATION := 2.8
const SKIRMISH_PREFERRED_DIST := 3.6

# Visual feedback state
var flash_timer: float = 0.0
var feedback_timer: float = 0.0
var last_hit_result: Dictionary = {"dealt": 0.0, "armored": false, "killed": false}

var visual_root: Node3D
var body_mesh: MeshInstance3D
var body_material: StandardMaterial3D
var base_body_color: Color = Color("5a7696")
var hp_bar_fill: MeshInstance3D
var hp_bar_material: StandardMaterial3D
var feedback_label: Label3D


func combat_id() -> int:
	return rewind_id


func configure(p_kind: StringName, spawn_pos: Vector3, orbit_seed: int = 0) -> void:
	if cover == null:
		cover = CoverScript.new()
	if orbit_seed > 0:
		rewind_id = orbit_seed
	elif rewind_id <= 0:
		rewind_id = 1
	kind = p_kind if Tuning.ENEMIES.has(String(p_kind)) else &"target"
	var cfg: Dictionary = Tuning.ENEMIES[String(kind)]
	max_health = float(cfg.get("health", 100.0))
	health = max_health
	move_speed = float(cfg.get("speed", 0.0))
	radius = float(cfg.get("radius", 0.7))
	contact_damage = float(cfg.get("damage", 0.0))
	contact_cooldown = 0.0
	cable_cut = false
	plate_broken = false
	attack_phase = &"approach"
	attack_timer = 0.0
	shield_heat = 0.0
	shield_open_timer = 0.0
	core_broken = false
	knockback_vel = Vector3.ZERO
	stagger_timer = 0.0
	skirmish_phase = &"orbit"
	skirmish_timer = 0.0
	skirmish_strafe_sign = -1.0 if (orbit_seed % 2 == 1) else 1.0
	flash_timer = 0.0
	feedback_timer = 0.0
	last_hit_result = {"dealt": 0.0, "armored": false, "killed": false}
	position = _resolve_cover_overlap(_clamp_to_arena(Vector3(spawn_pos.x, 0.0, spawn_pos.z)))
	var to_origin := Vector3(-position.x, 0.0, -position.z)
	if to_origin.length_squared() > 0.001:
		facing = to_origin.normalized()
	else:
		facing = Vector3(0.0, 0.0, 1.0)
	_build_visuals()
	_update_visual_facing()
	_update_health_visuals()


func is_staggered() -> bool:
	return stagger_timer > 0.0


func apply_control(direction: Vector3, impulse: float, stagger_seconds: float) -> void:
	if health <= 0.0:
		return
	var dir_xz := Vector3(direction.x, 0.0, direction.z)
	if dir_xz.length_squared() <= 0.000001:
		return
	dir_xz = dir_xz.normalized()

	var impulse_resist := float(Tuning.CONTROL.get("brute_resistance", 0.4)) if kind == &"brute" else 1.0
	var stagger_resist := float(Tuning.CONTROL.get("brute_stagger_resistance", 0.8)) if kind == &"brute" else 1.0
	if kind == &"warden":
		# A braced shield carrier can be heated without every pulse ejecting it
		# from cone range. It still moves and visibly staggers.
		impulse_resist = _part("push_resistance", 0.25)
		stagger_resist = _part("stagger_resistance", 0.8)
	if mechanism() != &"":
		impulse_resist = float(Tuning.MATCHUPS.push_heavy if mechanism() in [&"heat", &"open"] else Tuning.MATCHUPS.push_light)
		stagger_resist = float(Tuning.MATCHUPS.stagger_scale)
	var eff_impulse := maxf(0.0, impulse) * impulse_resist
	var eff_stagger := maxf(0.0, stagger_seconds) * stagger_resist

	if eff_impulse > 0.0:
		knockback_vel += dir_xz * eff_impulse
		if knockback_vel.length() > MAX_KNOCKBACK_SPEED:
			knockback_vel = knockback_vel.normalized() * MAX_KNOCKBACK_SPEED

	if eff_stagger > 0.0:
		var base_max := maxf(float(Tuning.CONTROL.get("stagger", 0.85)) * 1.5, stagger_seconds)
		var max_bound := base_max * stagger_resist
		stagger_timer = clampf(maxf(stagger_timer, eff_stagger), 0.0, max_bound)

	if eff_stagger > 0.0 or eff_impulse >= 2.0:
		flash_timer = maxf(flash_timer, 0.12)
		feedback_timer = maxf(feedback_timer, 0.45)
		if is_instance_valid(body_material):
			body_material.albedo_color = Color("8de8ff")
		if is_instance_valid(feedback_label):
			feedback_label.text = "STAGGER" if eff_stagger > 0.0 else "SHOVE"
			feedback_label.modulate = Color("8de8ff")


func capture_state() -> Dictionary:
	var state := {
		"rewind_id": int(rewind_id),
		"kind": String(kind),
		"position": position,
		"facing": facing,
		"health": float(health),
		"contact_cooldown": float(contact_cooldown),
		"knockback_vel": knockback_vel,
		"stagger_timer": float(stagger_timer),
		"skirmish_phase": String(skirmish_phase),
		"skirmish_timer": float(skirmish_timer),
		"skirmish_strafe_sign": float(skirmish_strafe_sign),
		"flash_timer": float(flash_timer),
		"feedback_timer": float(feedback_timer),
	}
	if kind == &"warden" or mechanism() != &"":
		state["cable_cut"] = cable_cut
		state["shield_heat"] = shield_heat
		state["shield_open_timer"] = shield_open_timer
		state["core_broken"] = core_broken
	if mechanism() != &"":
		state["plate_broken"] = plate_broken
		state["attack_phase"] = String(attack_phase)
		state["attack_timer"] = attack_timer
	if flash_timer > 0.0 or feedback_timer > 0.0:
		state["feedback_text"] = feedback_label.text if is_instance_valid(feedback_label) else ""
		state["feedback_color"] = feedback_label.modulate if is_instance_valid(feedback_label) else Color.WHITE
		state["last_hit_armored"] = bool(last_hit_result.get("armored", false))
	return state


func restore_state(data: Dictionary) -> void:
	if cover == null:
		cover = CoverScript.new()
	var target_kind := StringName(String(data.get("kind", kind)))
	if not Tuning.ENEMIES.has(String(target_kind)):
		target_kind = &"target"
	var kind_changed := (kind != target_kind) or not is_instance_valid(visual_root)
	kind = target_kind
	var cfg: Dictionary = Tuning.ENEMIES[String(kind)]
	max_health = float(cfg.get("health", 100.0))
	move_speed = float(cfg.get("speed", 0.0))
	radius = float(cfg.get("radius", 0.7))
	contact_damage = float(cfg.get("damage", 0.0))
	if kind_changed:
		_build_visuals()

	rewind_id = maxi(1, int(data.get("rewind_id", data.get("id", rewind_id))))
	var raw_pos: Vector3 = data.get("position", position)
	position = _resolve_cover_overlap(_clamp_to_arena(Vector3(raw_pos.x, 0.0, raw_pos.z)))
	facing = data.get("facing", facing)
	health = clampf(float(data.get("health", max_health)), 0.0, max_health)
	contact_cooldown = maxf(0.0, float(data.get("contact_cooldown", data.get("contact_timer", 0.0))))
	cable_cut = bool(data.get("cable_cut", false))
	plate_broken = bool(data.get("plate_broken", false))
	attack_phase = StringName(data.get("attack_phase", "approach"))
	attack_timer = maxf(0.0, float(data.get("attack_timer", 0.0)))
	shield_heat = maxf(0.0, float(data.get("shield_heat", 0.0)))
	shield_open_timer = maxf(0.0, float(data.get("shield_open_timer", 0.0)))
	core_broken = bool(data.get("core_broken", false))
	var raw_kb: Vector3 = data.get("knockback_vel", Vector3.ZERO)
	knockback_vel = Vector3(raw_kb.x, 0.0, raw_kb.z)
	stagger_timer = maxf(0.0, float(data.get("stagger_timer", 0.0)))
	var phase_str := String(data.get("skirmish_phase", "orbit"))
	skirmish_phase = &"commit" if phase_str == "commit" else &"orbit"
	skirmish_timer = maxf(0.0, float(data.get("skirmish_timer", 0.0)))
	skirmish_strafe_sign = -1.0 if float(data.get("skirmish_strafe_sign", 1.0)) < 0.0 else 1.0
	flash_timer = maxf(0.0, float(data.get("flash_timer", 0.0)))
	feedback_timer = maxf(0.0, float(data.get("feedback_timer", 0.0)))
	last_hit_result = {
		"dealt": float(data.get("last_hit_dealt", 0.0)),
		"armored": bool(data.get("last_hit_armored", false)),
		"killed": bool(data.get("last_hit_killed", false)),
	}
	var default_fb_text := "STAGGER" if stagger_timer > 0.0 else ""
	var default_fb_col := Color("8de8ff") if stagger_timer > 0.0 else Color.WHITE
	_sync_derived_visuals(
		String(data.get("feedback_text", default_fb_text)),
		data.get("feedback_color", default_fb_col)
	)


func _sync_derived_visuals(fb_text: String, fb_color: Color) -> void:
	_update_visual_facing()
	_update_health_visuals()
	_update_warden_visuals()
	if is_instance_valid(body_material):
		if flash_timer > 0.0:
			if stagger_timer > 0.0 or fb_text == "STAGGER" or fb_text == "SHOVE":
				body_material.albedo_color = Color("8de8ff")
			elif bool(last_hit_result.get("armored", false)):
				body_material.albedo_color = Color("a8d0f0")
			else:
				body_material.albedo_color = Color.WHITE
		elif stagger_timer > 0.0:
			body_material.albedo_color = Color("7aa8c9")
		else:
			body_material.albedo_color = base_body_color
	if is_instance_valid(feedback_label):
		if feedback_timer > 0.0:
			feedback_label.text = fb_text
			feedback_label.modulate = fb_color
		else:
			feedback_label.text = ""


func _make_mat(color: Color, unshaded: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


func _build_visuals() -> void:
	if is_instance_valid(visual_root):
		visual_root.queue_free()
	if is_instance_valid(status_root):
		status_root.queue_free()
	warden_visual = null
	part_visual = null
	visual_root = Node3D.new()
	add_child(visual_root)
	status_root = Node3D.new()
	add_child(status_root)

	var body_height := 1.2
	match kind:
		&"target":
			base_body_color = Color("4f7cac")
			body_height = 1.3
		&"swarmer":
			base_body_color = Color("d9534f")
			body_height = 0.85
		&"brute":
			base_body_color = Color("c97a3e")
			body_height = 1.75
		&"skirmisher":
			base_body_color = Color("45b69c")
			body_height = 1.25
		&"warden":
			base_body_color = Color("495962")
			body_height = 1.7
		_:
			base_body_color = Color("6d7882")
			body_height = 1.4

	body_material = _make_mat(base_body_color)
	body_mesh = MeshInstance3D.new()
	if kind == &"brute" or kind == &"swarmer":
		var box := BoxMesh.new()
		box.size = Vector3(radius * 1.75, body_height, radius * 1.75)
		body_mesh.mesh = box
	else:
		var cyl := CylinderMesh.new()
		cyl.top_radius = radius * 0.9
		cyl.bottom_radius = radius
		cyl.height = body_height
		body_mesh.mesh = cyl
	body_mesh.position = Vector3(0.0, body_height * 0.5, 0.0)
	body_mesh.material_override = body_material
	visual_root.add_child(body_mesh)
	if kind == &"warden":
		body_mesh.scale = Vector3(0.73, 0.82, 0.67)
		warden_visual = WardenVisual.new()
		visual_root.add_child(warden_visual)
		warden_visual.build(radius)
		_update_warden_visuals()

	# Forward facing marker (-Z in local visual_root space aligns with `facing`)
	if kind != &"warden":
		var nose := MeshInstance3D.new()
		var nose_mesh := BoxMesh.new()
		nose_mesh.size = Vector3(radius * 0.55, 0.24, radius * 0.65)
		nose.mesh = nose_mesh
		nose.position = Vector3(0.0, body_height * 0.62, -radius * 0.92)
		nose.material_override = _make_mat(Color("f4f7fa"), true)
		visual_root.add_child(nose)

	# Distinct front shield & rear vulnerable marker for Brute (and subtle rear marker for others)
	if kind == &"brute":
		var shield := MeshInstance3D.new()
		var shield_mesh := BoxMesh.new()
		shield_mesh.size = Vector3(radius * 2.05, body_height * 0.88, 0.26)
		shield.mesh = shield_mesh
		shield.position = Vector3(0.0, body_height * 0.5, -radius * 0.95)
		shield.material_override = _make_mat(Color("8ea4b8"))
		visual_root.add_child(shield)

		var rear_core := MeshInstance3D.new()
		var core_mesh := BoxMesh.new()
		core_mesh.size = Vector3(radius * 0.95, body_height * 0.55, 0.28)
		rear_core.mesh = core_mesh
		rear_core.position = Vector3(0.0, body_height * 0.5, radius * 0.92)
		rear_core.material_override = _make_mat(Color("7be08a"), true)
		visual_root.add_child(rear_core)
	elif kind != &"warden":
		var rear_tab := MeshInstance3D.new()
		var tab_mesh := BoxMesh.new()
		tab_mesh.size = Vector3(radius * 0.5, 0.18, 0.18)
		rear_tab.mesh = tab_mesh
		rear_tab.position = Vector3(0.0, body_height * 0.35, radius * 0.88)
		rear_tab.material_override = _make_mat(Color("222a35"), true)
		visual_root.add_child(rear_tab)

	if mechanism() != &"":
		for old in visual_root.get_children():
			old.visible = false
		part_visual = PartVisual.new()
		visual_root.add_child(part_visual)
		part_visual.build(mechanism(), part_layout(), radius, body_material)
		_update_warden_visuals()

	# Overhead health bar (kept unrotated in world space on self)
	var bar_y := body_height + (0.85 if kind == &"warden" else 0.45)
	var hp_bg := MeshInstance3D.new()
	var bg_mesh := BoxMesh.new()
	bg_mesh.size = Vector3(radius * 2.0, 0.11, 0.11)
	hp_bg.mesh = bg_mesh
	hp_bg.position = Vector3(0.0, bar_y, 0.0)
	hp_bg.material_override = _make_mat(Color("1c222b"), true)
	status_root.add_child(hp_bg)

	hp_bar_material = _make_mat(Color("67d97e"), true)
	hp_bar_fill = MeshInstance3D.new()
	var fill_mesh := BoxMesh.new()
	fill_mesh.size = Vector3(radius * 2.0, 0.13, 0.13)
	hp_bar_fill.mesh = fill_mesh
	hp_bar_fill.position = Vector3(0.0, bar_y, 0.0)
	hp_bar_fill.material_override = hp_bar_material
	status_root.add_child(hp_bar_fill)

	feedback_label = Label3D.new()
	feedback_label.position = Vector3(0.0, bar_y + 0.38, 0.0)
	feedback_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	feedback_label.no_depth_test = true
	feedback_label.font_size = 28
	feedback_label.outline_size = 6
	feedback_label.text = ""
	status_root.add_child(feedback_label)


func _update_visual_facing() -> void:
	if not is_instance_valid(visual_root):
		return
	var dir := Vector3(facing.x, 0.0, facing.z)
	if dir.length_squared() > 0.000001:
		visual_root.basis = Basis.looking_at(dir.normalized(), Vector3.UP)


func _update_health_visuals() -> void:
	if not is_instance_valid(hp_bar_fill):
		return
	var ratio := clampf(health / maxf(1.0, max_health), 0.0, 1.0)
	hp_bar_fill.visible = ratio > 0.0
	hp_bar_fill.scale.x = maxf(0.001, ratio)
	hp_bar_fill.position.x = -radius * (1.0 - ratio)
	if ratio > 0.5:
		hp_bar_material.albedo_color = Color("67d97e")
	elif ratio > 0.25:
		hp_bar_material.albedo_color = Color("e6b347")
	else:
		hp_bar_material.albedo_color = Color("e05a52")


func is_front_contact(contact_world: Vector3) -> bool:
	var to_contact := Vector3(contact_world.x - position.x, 0.0, contact_world.z - position.z)
	if to_contact.length_squared() <= 0.000001:
		return false
	var f := Vector3(facing.x, 0.0, facing.z).normalized()
	var dir := to_contact.normalized()
	var cos_limit := cos(float(Tuning.ARMOR.front_half_angle))
	return f.dot(dir) >= cos_limit


func _part(key: String, fallback: float) -> float:
	return float(Tuning.PARTS.get(key, fallback))


func mechanism() -> StringName:
	return StringName(Tuning.ENEMIES[String(kind)].get("mechanism", ""))


func part_layout() -> StringName:
	return StringName(Tuning.ENEMIES[String(kind)].get("layout", "bridge"))


func is_core_exposed() -> bool:
	if mechanism() != &"":
		return mechanism() == &"shot" or (mechanism() == &"open" and (cable_cut or plate_broken))
	return cable_cut or shield_open_timer > 0.0


func _update_warden_visuals() -> void:
	if kind == &"warden" and is_instance_valid(warden_visual):
		warden_visual.sync(cable_cut, is_core_exposed(), core_broken, shield_heat / maxf(0.01, _part("heat_threshold", 1.1)))
	if is_instance_valid(part_visual):
		part_visual.sync(cable_cut, is_core_exposed() or plate_broken, core_broken, shield_heat / float(Tuning.MATCHUPS.heat_seconds))


func attack_radius(tool: StringName) -> float:
	return radius + 0.65 if tool == &"ring" and has_cuttable_part() else radius


func has_cuttable_part() -> bool:
	return (kind == &"warden" or mechanism() in [&"cut", &"open"]) and not cable_cut and health > 0.0


func _local_part_world(local: Vector3) -> Vector3:
	var orientation := Basis.looking_at(facing, Vector3.UP)
	return position + orientation * local


func cable_world_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	if mechanism() != &"":
		for point: Vector3 in PartVisual.cable_points(part_layout(), radius):
			points.append(_local_part_world(point))
		return points
	for point: Vector3 in [Vector3(radius * 0.9, 0.0, -0.48), Vector3(radius + 0.38, 0.0, -0.48), Vector3(radius + 0.38, 0.0, 0.48), Vector3(radius * 0.9, 0.0, 0.48)]:
		points.append(_local_part_world(point))
	return points


func core_world_position() -> Vector3:
	return _local_part_world(PartVisual.core_point(radius) if mechanism() != &"" else Vector3(0.0, 1.05, -0.74))


func _point_segment_distance(point: Vector3, a: Vector3, b: Vector3) -> float:
	var p := Vector2(point.x, point.z)
	var start := Vector2(a.x, a.z)
	var end := Vector2(b.x, b.z)
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, start, end))


func _segment_distance(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> float:
	if Geometry2D.segment_intersects_segment(Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z), Vector2(d.x, d.z)) != null:
		return 0.0
	return minf(minf(_point_segment_distance(a, c, d), _point_segment_distance(b, c, d)), minf(_point_segment_distance(c, a, b), _point_segment_distance(d, a, b)))


func receive_attack(tool: StringName, amount: float, contact_world: Vector3, context: Dictionary = {}) -> Dictionary:
	var miss := {"dealt": 0.0, "armored": false, "killed": false, "connected": false, "cue": &""}
	if health <= 0.0 or amount <= 0.0:
		return miss
	if mechanism() != &"":
		return _variant_attack(tool, amount, contact_world, context)
	if kind != &"warden":
		var ordinary := hit(amount, contact_world)
		ordinary["connected"] = true
		ordinary["cue"] = &""
		return ordinary

	var has_segment := context.has("segment_start") and context.has("segment_end")
	var start: Vector3 = context.get("segment_start", contact_world)
	var end: Vector3 = context.get("segment_end", contact_world)
	var sweep_radius := maxf(0.0, float(context.get("radius", 0.0)))
	var body_connected := _point_segment_distance(position, start, end) <= radius + sweep_radius + 0.001
	var cable_connected := false
	if tool == &"ring" and not cable_cut and has_segment:
		var points := cable_world_points()
		for i in range(points.size() - 1):
			if _segment_distance(start, end, points[i], points[i + 1]) <= sweep_radius + _part("cable_radius", 0.1):
				cable_connected = true
				break
	if not body_connected and not cable_connected:
		return miss
	var already_hit := tool == &"ring" and bool(context.get("already_hit", false))
	if already_hit and not cable_connected:
		return miss

	var bonus := 0.0
	var cue: StringName = &""
	if cable_connected:
		cable_cut = true
		shield_heat = 0.0
		bonus += _part("cable_bonus", 65.0)
		cue = &"cable_cut"
	elif tool == &"cone" and not is_core_exposed():
		shield_heat += maxf(0.0, float(context.get("dt", 0.0)))
		if shield_heat >= _part("heat_threshold", 1.1):
			shield_heat = 0.0
			shield_open_timer = _part("open_seconds", 4.0)
			cue = &"vent"
	elif tool == &"beam" and is_core_exposed() and not core_broken and has_segment and float(context.get("charge", 0.0)) >= _part("core_min_charge", 0.6):
		# Extend the incoming ray through the chassis, preserving its actual aim.
		var direction := Vector3(end.x - start.x, 0.0, end.z - start.z)
		if direction.length_squared() > 0.000001:
			direction = direction.normalized()
			var core_pos := core_world_position()
			var along := (core_pos - start).dot(direction)
			var ray_end := start + direction * maxf(start.distance_to(end), along + radius * 2.0)
			if along >= 0.0 and _point_segment_distance(core_pos, start, ray_end) <= _part("core_radius", 0.28) + sweep_radius:
				core_broken = true
				bonus += _part("core_bonus", 140.0)
				cue = &"core_break"

	var result := hit((0.0 if already_hit else amount) + bonus, contact_world)
	result["connected"] = true
	result["cue"] = cue
	_update_warden_visuals()
	return result


func _variant_attack(tool: StringName, amount: float, contact: Vector3, context: Dictionary) -> Dictionary:
	var mode := mechanism()
	var start: Vector3 = context.get("segment_start", contact)
	var finish: Vector3 = context.get("segment_end", contact)
	var width := float(context.get("radius", 0.0))
	var connected := _point_segment_distance(position, start, finish) <= radius + width + 0.001
	var cut := false
	if tool == &"ring" and has_cuttable_part() and context.has("segment_start"):
		var points := cable_world_points()
		cut = _segment_distance(start, finish, points[0], points[1]) <= width + float(Tuning.MATCHUPS.cut_radius)
	var already_hit := tool == &"ring" and bool(context.get("already_hit", false))
	if (not connected and not cut) or (already_hit and not cut):
		return {"dealt": 0.0, "armored": false, "killed": false, "connected": false, "cue": &""}
	var cue: StringName = &""
	var decisive := false
	if cut:
		cable_cut = true
		cue = &"cable_cut"
		decisive = mode == &"cut"
	if tool == &"cone" and mode in [&"heat", &"open"] and not plate_broken:
		shield_heat += maxf(0.0, float(context.get("dt", 0.0)))
		if shield_heat >= float(Tuning.MATCHUPS.heat_seconds):
			plate_broken = true
			cue = &"vent"
			decisive = mode == &"heat"
	if tool == &"beam" and is_core_exposed() and not core_broken and context.has("segment_start"):
		var direction := Vector3(finish.x - start.x, 0, finish.z - start.z).normalized()
		var core_position := core_world_position()
		var along := (core_position - start).dot(direction)
		var ray_end := start + direction * maxf(start.distance_to(finish), along + radius * 2)
		if along >= 0 and _point_segment_distance(core_position, start, ray_end) <= width + float(Tuning.MATCHUPS.core_radius):
			core_broken = true
			cue = &"core_break"
			decisive = true
	# Every body hit progresses, but consumes far more condition than a part hit.
	var damage := health if decisive else (0.0 if already_hit else amount * float(Tuning.MATCHUPS.body_damage))
	var result := hit(damage, contact)
	result["connected"] = true
	result["cue"] = cue
	result["armored"] = not decisive
	if not decisive and is_instance_valid(feedback_label) and damage > 0:
		feedback_label.text = "-%.0f BODY" % result.dealt
	_update_warden_visuals()
	return result


func hit(amount: float, contact_world: Vector3) -> Dictionary:
	if health <= 0.0 or amount <= 0.0:
		return {"dealt": 0.0, "armored": false, "killed": false}

	var armored := false
	var effective := amount
	if kind == &"brute" and is_front_contact(contact_world):
		armored = true
		effective = amount * float(Tuning.ARMOR.front_multiplier)
	elif kind == &"warden" and not is_core_exposed() and is_front_contact(contact_world):
		armored = true
		effective = amount * _part("armor_multiplier", 0.35)

	var dealt := minf(health, maxf(0.0, effective))
	health = maxf(0.0, health - dealt)
	var killed := health <= 0.0

	flash_timer = 0.15
	feedback_timer = 0.65
	if is_instance_valid(body_material):
		body_material.albedo_color = Color("a8d0f0") if armored else Color.WHITE
	if is_instance_valid(feedback_label):
		feedback_label.text = "-%.0f ARMOR" % dealt if armored else "-%.0f" % dealt
		feedback_label.modulate = Color("99c8f2") if armored else Color("ffe885")
	_update_health_visuals()

	last_hit_result = {"dealt": dealt, "armored": armored, "killed": killed}
	return last_hit_result


func step_enemy(world_delta: float, player: Node3D, neighbors: Array = []) -> void:
	if health <= 0.0:
		return
	if mechanism() != &"" and world_delta > 0.0:
		shield_heat = maxf(0.0, shield_heat - world_delta * float(Tuning.MATCHUPS.heat_decay))
		_update_warden_visuals()
	if kind == &"warden" and world_delta > 0.0:
		shield_open_timer = maxf(0.0, shield_open_timer - world_delta)
		shield_heat = maxf(0.0, shield_heat - world_delta * _part("heat_decay", 0.25))
		_update_warden_visuals()

	if flash_timer > 0.0:
		flash_timer = maxf(0.0, flash_timer - world_delta)
		if flash_timer <= 0.0 and is_instance_valid(body_material):
			body_material.albedo_color = Color("7aa8c9") if stagger_timer > 0.0 else base_body_color

	if feedback_timer > 0.0:
		feedback_timer = maxf(0.0, feedback_timer - world_delta)
		if feedback_timer <= 0.0 and is_instance_valid(feedback_label):
			feedback_label.text = ""

	if contact_cooldown > 0.0:
		contact_cooldown = maxf(0.0, contact_cooldown - world_delta)

	if world_delta <= 0.0:
		return

	if cover == null:
		cover = CoverScript.new()

	# 1. Exact exponential knockback integration & cover-safe displacement on world_delta
	if knockback_vel.length_squared() > 0.00001:
		var drag := maxf(0.001, float(Tuning.CONTROL.drag))
		var decay := exp(-drag * world_delta)
		var kb_disp := knockback_vel * ((1.0 - decay) / drag)
		knockback_vel *= decay
		if knockback_vel.length_squared() < 0.0001:
			knockback_vel = Vector3.ZERO
		position = _move_step_cover_safe(position, kb_disp, true)

	# 2. Stagger timer splits the tick so mid-tick recovery is frame-delta invariant
	var stagger_consumed := minf(world_delta, stagger_timer)
	stagger_timer = maxf(0.0, stagger_timer - world_delta)
	if stagger_timer <= 0.0 and flash_timer <= 0.0 and is_instance_valid(body_material):
		body_material.albedo_color = base_body_color

	var active_ai_delta := world_delta - stagger_consumed
	if active_ai_delta <= 0.0 or not is_instance_valid(player) or kind == &"target":
		return

	var player_xz := Vector3(player.position.x, 0.0, player.position.z)
	var self_xz := Vector3(position.x, 0.0, position.z)
	var to_player := player_xz - self_xz
	var dist := to_player.length()
	var dir_to_player := to_player / dist if dist > 0.0001 else facing

	var move_dir := Vector3.ZERO
	match kind:
		&"swarmer":
			facing = dir_to_player
			var steered := _steer_around_cover(self_xz, dir_to_player, player_xz)
			var sep := _compute_separation(neighbors, 1.15)
			move_dir = (steered + sep * 0.55).normalized() if (steered + sep * 0.55).length_squared() > 0.0001 else steered
		&"brute", &"warden":
			# Brute turns steadily toward the player so its sides/rear can be flanked
			facing = _rotate_xz_toward(facing, dir_to_player, (1.15 if kind == &"warden" else 2.4) * active_ai_delta)
			move_dir = _steer_around_cover(self_xz, dir_to_player, player_xz)
		&"skirmisher":
			facing = dir_to_player
			skirmish_timer += active_ai_delta
			if skirmish_phase == &"orbit":
				if skirmish_timer >= SKIRMISH_ORBIT_DURATION:
					skirmish_phase = &"commit"
					skirmish_timer = 0.0
			else:
				if skirmish_timer >= SKIRMISH_COMMIT_DURATION:
					skirmish_phase = &"orbit"
					skirmish_timer = 0.0
					skirmish_strafe_sign = -skirmish_strafe_sign

			if skirmish_phase == &"commit":
				move_dir = _steer_around_cover(self_xz, dir_to_player, player_xz)
			else:
				# Keep moderate distance within cone range (~3.6 units) while sidestepping; never evade faster than player
				var tangent := Vector3(-dir_to_player.z * skirmish_strafe_sign, 0.0, dir_to_player.x * skirmish_strafe_sign)
				var radial_weight := clampf((dist - SKIRMISH_PREFERRED_DIST) * 0.75, -0.35, 1.0)
				var combined := dir_to_player * radial_weight + tangent * 0.75
				var raw_dir := combined.normalized() if combined.length_squared() > 0.0001 else dir_to_player
				move_dir = _steer_around_cover(self_xz, raw_dir, self_xz + raw_dir * 3.0)

	if mechanism() != &"":
		facing = _rotate_xz_toward(facing, dir_to_player, 3.0 * active_ai_delta)
		var destination := pack_target(player_xz, neighbors)
		var pack_direction := destination - self_xz
		var blend := float(Tuning.PACK.strength) if mechanism() in [&"cut", &"open"] else 0.0
		var approach := dir_to_player.lerp(pack_direction.normalized(), blend)
		var separation := _compute_separation(neighbors, radius * 2.0 + 0.15)
		approach += separation * float(Tuning.PACK.separation)
		move_dir = _steer_around_cover(self_xz, approach.normalized(), destination)
		if attack_phase != &"approach":
			move_dir = Vector3.ZERO

	var stop_dist := radius + PLAYER_CONTACT_RADIUS - 0.04
	if dist > stop_dist and move_dir.length_squared() > 0.0001:
		var step_len := move_speed * active_ai_delta
		position = _move_step_cover_safe(self_xz, move_dir * step_len, false)

	# Recompute XZ distance for contact damage (suppressed while staggered)
	var post_xz := Vector3(position.x, 0.0, position.z)
	var post_dist := post_xz.distance_to(player_xz)
	if mechanism() != &"":
		_step_part_attack(active_ai_delta, player, post_dist)
		return
	if stagger_timer <= 0.0 and contact_damage > 0.0 and post_dist <= (radius + PLAYER_CONTACT_RADIUS + 0.05):
		if float(player.health) > 0.0 and contact_cooldown <= 0.0:
			player.take_damage(contact_damage)
			contact_cooldown = float(Tuning.CONTACT_COOLDOWN)
			if kind == &"skirmisher" and skirmish_phase == &"commit":
				skirmish_phase = &"orbit"
				skirmish_timer = 0.0
				skirmish_strafe_sign = -skirmish_strafe_sign


func pack_target(player_position: Vector3, neighbors: Array) -> Vector3:
	if mechanism() not in [&"cut", &"open"]:
		return player_position
	var members: Array = []
	var pack_size := int(Tuning.PACK.size)
	var cohort := floori(float(combat_id() - 1) / pack_size)
	for other in neighbors:
		if not is_instance_valid(other) or other.health <= 0 or not other.has_method("mechanism"):
			continue
		if other.mechanism() not in [&"cut", &"open"] or floori(float(other.combat_id() - 1) / pack_size) != cohort:
			continue
		if position.distance_to(other.position) <= float(Tuning.PACK.neighbor_range):
			members.append(other)
	if members.size() < 2 or not members.has(self):
		return player_position
	members.sort_custom(func(a, b): return a.combat_id() < b.combat_id())
	var center := Vector3.ZERO
	for other in members:
		center += other.position
	center /= members.size()
	var radial := Vector2(center.x - player_position.x, center.z - player_position.z)
	# Release the formation near contact so cohesion never prevents an attack.
	if radial.length() < float(Tuning.PACK.break_distance):
		return player_position
	var distance := maxf(1.7, radial.length() - float(Tuning.PACK.advance))
	var slot := float(members.find(self)) - float(members.size() - 1) * 0.5
	var angle := radial.angle() + slot * float(Tuning.PACK.spacing) / distance
	return player_position + Vector3(cos(angle), 0, sin(angle)) * distance


func _step_part_attack(world_delta: float, player: Node3D, distance: float) -> void:
	var reach := radius + PLAYER_CONTACT_RADIUS + 0.1
	if attack_phase == &"approach":
		if distance <= reach:
			attack_phase = &"windup"
			attack_timer = float(Tuning.MATCHUPS.attack_windup)
			feedback_label.text = "!"
			feedback_timer = attack_timer
		return
	attack_timer = maxf(0.0, attack_timer - world_delta)
	if attack_timer > 0.0:
		return
	if attack_phase == &"windup":
		if distance <= reach and player.health > 0:
			player.take_damage(contact_damage)
		attack_phase = &"recover"
		attack_timer = float(Tuning.MATCHUPS.attack_recovery)
	else:
		attack_phase = &"approach"


func overlaps_cover(margin: float = -0.01) -> bool:
	if cover == null:
		return false
	var pt := Vector2(position.x, position.z)
	for rect: Rect2 in cover.RECTANGLES:
		if rect.grow(maxf(0.0, radius + margin)).has_point(pt):
			return true
	return false


func _clamp_to_arena(pos: Vector3) -> Vector3:
	var limit := float(Tuning.ARENA_HALF_SIZE) - 1.0
	return Vector3(clampf(pos.x, -limit, limit), 0.0, clampf(pos.z, -limit, limit))


func _resolve_cover_overlap(pos: Vector3) -> Vector3:
	if cover == null:
		return pos
	var out := Vector3(pos.x, 0.0, pos.z)
	for rect: Rect2 in cover.RECTANGLES:
		var expanded := rect.grow(radius + 0.003)
		if expanded.has_point(Vector2(out.x, out.z)):
			var d_left := absf(out.x - expanded.position.x)
			var d_right := absf(expanded.end.x - out.x)
			var d_top := absf(out.z - expanded.position.y)
			var d_bottom := absf(expanded.end.y - out.z)
			var min_d := minf(minf(d_left, d_right), minf(d_top, d_bottom))
			if is_equal_approx(min_d, d_left):
				out.x = expanded.position.x - 0.002
			elif is_equal_approx(min_d, d_right):
				out.x = expanded.end.x + 0.002
			elif is_equal_approx(min_d, d_top):
				out.z = expanded.position.y - 0.002
			else:
				out.z = expanded.end.y + 0.002
	return _clamp_to_arena(out)


func _move_step_cover_safe(start_pos: Vector3, delta_vec: Vector3, is_knockback: bool) -> Vector3:
	var clean_start := _resolve_cover_overlap(start_pos)
	var flat_delta := Vector3(delta_vec.x, 0.0, delta_vec.z)
	if flat_delta.length_squared() <= 0.0000001 or cover == null:
		return _clamp_to_arena(clean_start + flat_delta)

	var finish := clean_start + flat_delta
	var hit: Dictionary = cover.clip_segment(clean_start, finish, radius)
	if not hit.get("blocked", false):
		return _resolve_cover_overlap(_clamp_to_arena(finish))

	var frac := clampf(float(hit.get("fraction", 0.0)), 0.0, 1.0)
	var normal: Vector3 = hit.get("normal", Vector3.ZERO)
	var safe_pos := clean_start + flat_delta * maxf(0.0, frac - 0.002) + normal * 0.003
	safe_pos = _resolve_cover_overlap(safe_pos)

	if is_knockback and knockback_vel.dot(normal) < 0.0:
		knockback_vel -= normal * knockback_vel.dot(normal)

	var remaining := flat_delta * (1.0 - frac)
	var slide := remaining - normal * remaining.dot(normal)
	if slide.length_squared() > 0.000001:
		var hit2: Dictionary = cover.clip_segment(safe_pos, safe_pos + slide, radius)
		if not hit2.get("blocked", false):
			safe_pos += slide
		else:
			var frac2 := clampf(float(hit2.get("fraction", 0.0)), 0.0, 1.0)
			var normal2: Vector3 = hit2.get("normal", Vector3.ZERO)
			safe_pos += slide * maxf(0.0, frac2 - 0.002) + normal2 * 0.003

	return _resolve_cover_overlap(_clamp_to_arena(safe_pos))


func _steer_around_cover(self_xz: Vector3, desired_dir: Vector3, goal_xz: Vector3) -> Vector3:
	if cover == null or desired_dir.length_squared() <= 0.0001:
		return desired_dir
	var dist_to_goal := self_xz.distance_to(goal_xz)
	var lookahead := minf(maxf(dist_to_goal, 0.5), 2.6)
	var probe: Dictionary = cover.clip_segment(self_xz, self_xz + desired_dir * lookahead, radius + 0.04)
	if not probe.get("blocked", false):
		return desired_dir

	# Evaluate expanded corners of the two cover rectangles to pick a clean detour around the box
	var best_dir := Vector3.ZERO
	var best_cost := INF
	for rect: Rect2 in cover.RECTANGLES:
		var wp_rect := rect.grow(radius + 0.32)
		var corners: Array[Vector3] = [
			Vector3(wp_rect.position.x, 0.0, wp_rect.position.y),
			Vector3(wp_rect.end.x, 0.0, wp_rect.position.y),
			Vector3(wp_rect.end.x, 0.0, wp_rect.end.y),
			Vector3(wp_rect.position.x, 0.0, wp_rect.end.y),
		]
		for c in corners:
			var d_self := self_xz.distance_to(c)
			if d_self < 0.18:
				continue
			var to_c: Dictionary = cover.clip_segment(self_xz, c, radius + 0.01)
			if to_c.get("blocked", false):
				continue
			var to_goal: Dictionary = cover.clip_segment(c, goal_xz, radius + 0.01)
			var penalty := 4.0 if to_goal.get("blocked", false) else 0.0
			var cost := d_self + c.distance_to(goal_xz) + penalty
			if cost < best_cost:
				best_cost = cost
				best_dir = (c - self_xz) / d_self

	if best_dir.length_squared() > 0.0001:
		return best_dir

	# Fallback tangent slide along hit normal
	var n: Vector3 = probe.get("normal", Vector3.ZERO)
	var t1 := Vector3(-n.z, 0.0, n.x)
	var t2 := -t1
	var p1 := (self_xz + t1).distance_squared_to(goal_xz)
	var p2 := (self_xz + t2).distance_squared_to(goal_xz)
	return t1 if p1 <= p2 else t2


func _compute_separation(neighbors: Array, desired_gap: float) -> Vector3:
	var push := Vector3.ZERO
	var self_xz := Vector3(position.x, 0.0, position.z)
	for other in neighbors:
		if other == self or not is_instance_valid(other) or other.health <= 0.0:
			continue
		var diff := self_xz - Vector3(other.position.x, 0.0, other.position.z)
		var d := diff.length()
		if d > 0.0001 and d < desired_gap:
			push += (diff / d) * ((desired_gap - d) / desired_gap)
	return push


func _rotate_xz_toward(from_dir: Vector3, to_dir: Vector3, max_angle: float) -> Vector3:
	var a := Vector2(from_dir.x, from_dir.z).normalized()
	var b := Vector2(to_dir.x, to_dir.z).normalized()
	var angle_diff := a.angle_to(b)
	if absf(angle_diff) <= max_angle:
		return Vector3(b.x, 0.0, b.y)
	var rotated := a.rotated(clampf(angle_diff, -max_angle, max_angle))
	return Vector3(rotated.x, 0.0, rotated.y).normalized()
