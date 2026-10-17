extends Node3D

# jam-4 owns enemy.gd. No independent _process or _physics_process clock.
const Tuning = preload("res://scenes/prototype/tuning.gd")
const PLAYER_CONTACT_RADIUS := 0.5

var kind: StringName = &"target"
var radius: float = 0.7
var max_health: float = 100.0
var health: float = 100.0
var move_speed: float = 0.0
var contact_damage: float = 0.0
var contact_cooldown: float = 0.0

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


func configure(p_kind: StringName, spawn_pos: Vector3, orbit_seed: int = 0) -> void:
	kind = p_kind if Tuning.ENEMIES.has(String(p_kind)) else &"target"
	var cfg: Dictionary = Tuning.ENEMIES[String(kind)]
	max_health = float(cfg.get("health", 100.0))
	health = max_health
	move_speed = float(cfg.get("speed", 0.0))
	radius = float(cfg.get("radius", 0.7))
	contact_damage = float(cfg.get("damage", 0.0))
	contact_cooldown = 0.0
	skirmish_phase = &"orbit"
	skirmish_timer = 0.0
	skirmish_strafe_sign = -1.0 if (orbit_seed % 2 == 1) else 1.0
	position = Vector3(spawn_pos.x, 0.0, spawn_pos.z)
	var to_origin := Vector3(-position.x, 0.0, -position.z)
	if to_origin.length_squared() > 0.001:
		facing = to_origin.normalized()
	else:
		facing = Vector3(0.0, 0.0, 1.0)
	_build_visuals()
	_update_visual_facing()
	_update_health_visuals()


func _make_mat(color: Color, unshaded: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


func _build_visuals() -> void:
	if is_instance_valid(visual_root):
		visual_root.queue_free()
	visual_root = Node3D.new()
	add_child(visual_root)

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

	# Forward facing marker (-Z in local visual_root space aligns with `facing`)
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
	else:
		var rear_tab := MeshInstance3D.new()
		var tab_mesh := BoxMesh.new()
		tab_mesh.size = Vector3(radius * 0.5, 0.18, 0.18)
		rear_tab.mesh = tab_mesh
		rear_tab.position = Vector3(0.0, body_height * 0.35, radius * 0.88)
		rear_tab.material_override = _make_mat(Color("222a35"), true)
		visual_root.add_child(rear_tab)

	# Overhead health bar (kept unrotated in world space on self)
	var bar_y := body_height + 0.45
	var hp_bg := MeshInstance3D.new()
	var bg_mesh := BoxMesh.new()
	bg_mesh.size = Vector3(radius * 2.0, 0.11, 0.11)
	hp_bg.mesh = bg_mesh
	hp_bg.position = Vector3(0.0, bar_y, 0.0)
	hp_bg.material_override = _make_mat(Color("1c222b"), true)
	add_child(hp_bg)

	hp_bar_material = _make_mat(Color("67d97e"), true)
	hp_bar_fill = MeshInstance3D.new()
	var fill_mesh := BoxMesh.new()
	fill_mesh.size = Vector3(radius * 2.0, 0.13, 0.13)
	hp_bar_fill.mesh = fill_mesh
	hp_bar_fill.position = Vector3(0.0, bar_y, 0.0)
	hp_bar_fill.material_override = hp_bar_material
	add_child(hp_bar_fill)

	feedback_label = Label3D.new()
	feedback_label.position = Vector3(0.0, bar_y + 0.38, 0.0)
	feedback_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	feedback_label.no_depth_test = true
	feedback_label.font_size = 28
	feedback_label.outline_size = 6
	feedback_label.text = ""
	add_child(feedback_label)


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


func hit(amount: float, contact_world: Vector3) -> Dictionary:
	if health <= 0.0 or amount <= 0.0:
		return {"dealt": 0.0, "armored": false, "killed": false}

	var armored := false
	var effective := amount
	if kind == &"brute" and is_front_contact(contact_world):
		armored = true
		effective = amount * float(Tuning.ARMOR.front_multiplier)

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


func step_enemy(world_delta: float, player: Node3D, neighbors: Array[Node3D]) -> void:
	if health <= 0.0:
		return

	if flash_timer > 0.0:
		flash_timer = maxf(0.0, flash_timer - world_delta)
		if flash_timer <= 0.0 and is_instance_valid(body_material):
			body_material.albedo_color = base_body_color

	if feedback_timer > 0.0:
		feedback_timer = maxf(0.0, feedback_timer - world_delta)
		if feedback_timer <= 0.0 and is_instance_valid(feedback_label):
			feedback_label.text = ""

	if contact_cooldown > 0.0:
		contact_cooldown = maxf(0.0, contact_cooldown - world_delta)

	if not is_instance_valid(player) or kind == &"target" or world_delta <= 0.0:
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
			var sep := _compute_separation(neighbors, 1.15)
			move_dir = (dir_to_player + sep * 0.55).normalized() if (dir_to_player + sep * 0.55).length_squared() > 0.0001 else dir_to_player
		&"brute":
			# Brute turns steadily toward the player so its sides/rear can be flanked
			facing = _rotate_xz_toward(facing, dir_to_player, 2.4 * world_delta)
			move_dir = dir_to_player
		&"skirmisher":
			facing = dir_to_player
			skirmish_timer += world_delta
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
				move_dir = dir_to_player
			else:
				# Keep moderate distance within cone range (~3.6 units) while sidestepping; never evade faster than player
				var tangent := Vector3(-dir_to_player.z * skirmish_strafe_sign, 0.0, dir_to_player.x * skirmish_strafe_sign)
				var radial_weight := clampf((dist - SKIRMISH_PREFERRED_DIST) * 0.75, -0.35, 1.0)
				var combined := dir_to_player * radial_weight + tangent * 0.75
				move_dir = combined.normalized() if combined.length_squared() > 0.0001 else dir_to_player

	var stop_dist := radius + PLAYER_CONTACT_RADIUS - 0.04
	if dist > stop_dist and move_dir.length_squared() > 0.0001:
		var step_len := move_speed * world_delta
		var next_pos := self_xz + move_dir * step_len
		var limit := float(Tuning.ARENA_HALF_SIZE) - 1.0
		position.x = clampf(next_pos.x, -limit, limit)
		position.z = clampf(next_pos.z, -limit, limit)
		position.y = 0.0

	# Recompute XZ distance for contact damage
	var post_xz := Vector3(position.x, 0.0, position.z)
	var post_dist := post_xz.distance_to(player_xz)
	if contact_damage > 0.0 and post_dist <= (radius + PLAYER_CONTACT_RADIUS + 0.05):
		if float(player.health) > 0.0 and contact_cooldown <= 0.0:
			player.take_damage(contact_damage)
			contact_cooldown = float(Tuning.CONTACT_COOLDOWN)
			if kind == &"skirmisher" and skirmish_phase == &"commit":
				# After landing a committed strike, skirmisher can pivot to a brief sidestep
				skirmish_phase = &"orbit"
				skirmish_timer = 0.0
				skirmish_strafe_sign = -skirmish_strafe_sign


func _compute_separation(neighbors: Array[Node3D], desired_gap: float) -> Vector3:
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
	var rotated := a.rotated( clampf(angle_diff, -max_angle, max_angle) )
	return Vector3(rotated.x, 0.0, rotated.y).normalized()
