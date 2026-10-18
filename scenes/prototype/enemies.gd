extends Node3D

# Arena drives this director with world time; there is no independent clock.
const Tuning = preload("res://scenes/prototype/tuning.gd")
const PatternEnemy = preload("res://scenes/prototype/pattern_enemy.gd")
const EnemyNode = preload("res://scenes/prototype/enemy.gd")
const CoverScript = preload("res://scenes/prototype/cover.gd")
const Flow = preload("res://scenes/prototype/flow.gd")
const MAX_LIVE_ENEMIES := 32
const MAX_PROJECTILES := 24
var projectiles: Array[Dictionary] = []
var _projectile_visuals: Array[MeshInstance3D] = []
var flow: RefCounted = Flow.new()
var _arrival_mesh: ImmediateMesh

var enemies: Array[Node3D] = []
var cover: RefCounted
var _spawn_counter: int = 0

# Bounded encounter state (world seconds)
var encounter_active: bool = false
var encounter_state: StringName = &"sandbox" # &"sandbox", &"running", &"victory", &"defeat"
var encounter_elapsed: float = 0.0
var encounter_wave_index: int = 0

# A blue pack first; later mixed arrivals and a quiet reinforcement interval.
const WAVE_TEMPLATES: Array[Array] = [
	[
		{"kind": &"blue", "pos": Vector3(-2.8, 0, -9.0)},
		{"kind": &"blue", "pos": Vector3(0, 0, -9.6)},
		{"kind": &"blue", "pos": Vector3(2.8, 0, -9.0)},
	],
	[
		{"kind": &"yellow", "pos": Vector3(-4.5, 0, -11.5)},
		{"kind": &"orange", "pos": Vector3(4.5, 0, -11.5)},
	],
	[
		{"kind": &"side_guard", "pos": Vector3(-2, 0, -11)},
		{"kind": &"front_guard", "pos": Vector3(2, 0, -11)},
	],
	[],
	[
		{"kind": &"blue", "pos": Vector3(-2.8, 0, 10)},
		{"kind": &"blue", "pos": Vector3(0, 0, 10.6)},
		{"kind": &"blue", "pos": Vector3(2.8, 0, 10)},
	],
	[
		{"kind": &"yellow", "pos": Vector3(-4, 0, -11.5)},
		{"kind": &"orange", "pos": Vector3(4, 0, -11.5)},
	],
	[
		{"kind": &"front_guard", "pos": Vector3(0, 0, -11)},
	],
]


func _total_scheduled_waves() -> int:
	var duration := float(Tuning.ENCOUNTER.duration)
	var interval := maxf(0.1, float(Tuning.ENCOUNTER.interval))
	return int(floor((duration - 0.001) / interval)) + 1


func step(world_delta: float, player: Node3D) -> void:
	_prune_dead_enemies()
	_step_projectiles(maxf(0, world_delta), player)

	if encounter_state == &"running":
		if is_instance_valid(player) and float(player.health) <= 0.0:
			encounter_active = false
			encounter_state = &"defeat"
		else:
			var duration := float(Tuning.ENCOUNTER.duration)
			var interval := maxf(0.1, float(Tuning.ENCOUNTER.interval))
			var total_waves := _total_scheduled_waves()
			encounter_elapsed = minf(duration, encounter_elapsed + maxf(0.0, world_delta))
			while encounter_wave_index < total_waves and encounter_elapsed >= float(encounter_wave_index) * interval:
				_spawn_encounter_wave(encounter_wave_index)
				encounter_wave_index += 1

	var snapshot: Array[Node3D] = enemies.duplicate()
	var burst: Dictionary = flow.next_burst(world_delta, player)
	if not burst.is_empty():
		spawn_formation(burst.formation, burst.kinds, player, burst.seed)
		snapshot = enemies.duplicate()
	var holds: Dictionary = flow.advance(world_delta, snapshot, player)
	for enemy in snapshot:
		if is_instance_valid(enemy) and enemy.health > 0.0:
			var hold := float(holds.get(int(enemy.combat_id()), 0.0))
			if hold > 0:
				var speed := float(enemy.move_speed)
				enemy.move_speed = 0.0
				enemy.step_enemy(hold, player, snapshot)
				enemy.move_speed = speed
			if world_delta - hold > 0: enemy.step_enemy(world_delta - hold, player, snapshot)
	flow.cohere(world_delta, snapshot, cover, holds)
	_draw_arrivals()
	_prune_dead_enemies()

	if encounter_state == &"running":
		if is_instance_valid(player) and float(player.health) <= 0.0:
			encounter_active = false
			encounter_state = &"defeat"
		elif encounter_elapsed >= float(Tuning.ENCOUNTER.duration) and enemies.is_empty():
			encounter_active = false
			encounter_state = &"victory"


func _spawn_encounter_wave(wave_idx: int) -> void:
	var max_live: int = mini(int(Tuning.ENCOUNTER.max_enemies), MAX_LIVE_ENEMIES)
	var template: Array = WAVE_TEMPLATES[wave_idx % WAVE_TEMPLATES.size()]
	for entry in template:
		if enemies.size() >= max_live:
			break
		spawn(entry["kind"], entry["pos"])


func _retire_enemy_node(enemy: Node3D) -> void:
	if not is_instance_valid(enemy):
		return
	if enemy.get_parent() == self:
		remove_child(enemy)
	enemy.queue_free()


func _prune_dead_enemies() -> void:
	var live: Array[Node3D] = []
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy.health <= 0.0:
			_retire_enemy_node(enemy)
			continue
		live.append(enemy)
	enemies = live


func spawn(kind: StringName, spawn_position: Vector3) -> Node3D:
	_prune_dead_enemies()
	if enemies.size() >= MAX_LIVE_ENEMIES:
		return null
	if cover == null:
		cover = CoverScript.new()
	var enemy: Node3D = PatternEnemy.new() if PatternEnemy.handles(kind) else EnemyNode.new()
	enemy.cover = cover
	_spawn_counter += 1
	enemy.rewind_id = _spawn_counter
	var limit := float(Tuning.ARENA_HALF_SIZE) - 1.0
	var clamped_pos := Vector3(
		clampf(spawn_position.x, -limit, limit),
		0.0,
		clampf(spawn_position.z, -limit, limit)
	)
	add_child(enemy)
	enemy.configure(kind, clamped_pos, _spawn_counter)
	enemies.append(enemy)
	return enemy


func spawn_group() -> void:
	spawn(&"blue", Vector3(-3.0, 0, -7.0))
	spawn(&"blue", Vector3(-1.1, 0, -7.8))
	spawn(&"side_guard", Vector3(1.1, 0, -7.8))
	spawn(&"front_guard", Vector3(3.0, 0, -7.0))
	spawn(&"yellow", Vector3(-4, 0, -10.5))
	spawn(&"orange", Vector3(4, 0, -10.5))


func spawn_formation(formation: StringName, kinds: Array, player: Node3D, seed: int = 0) -> Array[Node3D]:
	var result: Array[Node3D] = []
	if not is_instance_valid(player) or kinds.is_empty(): return result
	if cover == null: cover = CoverScript.new()
	var slots: Array = flow.layout(formation, kinds, player.position, cover, seed, enemies)
	for slot: Dictionary in slots:
		var enemy := spawn(StringName(slot.kind), slot.position)
		if enemy != null: result.append(enemy)
	flow.add(formation, result)
	_draw_arrivals()
	return result


# Optional finite three-burst sandbox exercise, not a room/campaign controller.
# Existing start_encounter/debug paths keep their legacy scheduling and counts.
func start_flow(player: Node3D, seed: int = 0) -> void:
	clear()
	flow.start_pressure(seed)
	var burst: Dictionary = flow.next_burst(0, player)
	if not burst.is_empty(): spawn_formation(burst.formation, burst.kinds, player, burst.seed)


func _draw_arrivals() -> void:
	if _arrival_mesh == null:
		_arrival_mesh = ImmediateMesh.new()
		var instance := MeshInstance3D.new()
		instance.name = "FormationArrivalWarnings"
		instance.mesh = _arrival_mesh
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		instance.material_override = mat
		add_child(instance)
	_arrival_mesh.clear_surfaces()
	var warnings: Array[Dictionary] = []
	for cohort: Dictionary in flow.cohorts:
		if cohort.warning > 0: warnings.append(cohort)
	if warnings.is_empty(): return
	_arrival_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for cohort: Dictionary in warnings:
		var color := Color("479cff")
		if cohort.formation == &"line": color = Color("ffe066")
		elif cohort.formation == &"cluster": color = Color("f9974b")
		color.a = 0.55 + 0.35 * (1.0 - float(cohort.warning) / Flow.WARNING_SECONDS)
		for offset: Vector3 in cohort.offsets:
			var center: Vector3 = cohort.center + offset + Vector3.UP * 0.035
			for i in range(24):
				var a := TAU * float(i) / 24
				var b := TAU * float(i + 1) / 24
				var v0 := Vector3(cos(a), 0, sin(a))
				var v1 := Vector3(cos(b), 0, sin(b))
				for point in [v0 * 1.01, v0 * 1.09, v1 * 1.01, v0 * 1.09, v1 * 1.09, v1 * 1.01]:
					_arrival_mesh.surface_set_color(color)
					_arrival_mesh.surface_add_vertex(center + point)
	_arrival_mesh.surface_end()


func _cancel_encounter() -> void:
	encounter_active = false
	encounter_state = &"sandbox"
	encounter_elapsed = 0.0
	encounter_wave_index = 0


func clear() -> void:
	_cancel_encounter()
	projectiles.clear()
	_sync_projectile_visuals()
	flow.reset()
	if _arrival_mesh != null: _arrival_mesh.clear_surfaces()
	for enemy in enemies:
		_retire_enemy_node(enemy)
	enemies.clear()


func reset_state() -> void:
	clear()
	_spawn_counter = 0
	spawn(&"target", Vector3(0.0, 0.0, -6.0))


func start_encounter() -> void:
	clear()
	_spawn_counter = 0
	encounter_active = true
	encounter_state = &"running"
	encounter_elapsed = 0.0
	encounter_wave_index = 0
	_spawn_encounter_wave(0)
	encounter_wave_index = 1


func capture_state() -> Dictionary:
	var roster_data: Array = []
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.health > 0.0:
			roster_data.append(enemy.capture_state())
			if roster_data.size() >= MAX_LIVE_ENEMIES:
				break
	return {
		"projectiles": projectiles.duplicate(true),
		"flow": flow.capture_state(),
		"spawn_counter": int(_spawn_counter),
		"encounter_active": bool(encounter_active),
		"encounter_state": String(encounter_state),
		"encounter_elapsed": float(encounter_elapsed),
		"encounter_wave_index": int(encounter_wave_index),
		"enemies": roster_data,
	}


func restore_state(data: Dictionary) -> void:
	if cover == null:
		cover = CoverScript.new()
	projectiles.clear()
	for raw: Variant in data.get("projectiles", []):
		if projectiles.size() >= MAX_PROJECTILES: break
		if raw is Dictionary and raw.get("position") is Vector3 and raw.get("velocity") is Vector3:
			projectiles.append({"position": raw.position, "velocity": raw.velocity,
				"damage": clampf(float(raw.get("damage", 10)), 0, 100),
				"life": clampf(float(raw.get("life", 0)), 0, 6)})
	_sync_projectile_visuals()

	var state_str := String(data.get("encounter_state", "sandbox"))
	if state_str in ["sandbox", "running", "victory", "defeat"]:
		encounter_state = StringName(state_str)
	else:
		encounter_state = &"sandbox"
	encounter_active = bool(data.get("encounter_active", encounter_state == &"running"))
	encounter_elapsed = maxf(0.0, float(data.get("encounter_elapsed", 0.0)))
	encounter_wave_index = maxi(0, int(data.get("encounter_wave_index", 0)))

	var existing_by_id: Dictionary = {}
	for enemy in enemies:
		if is_instance_valid(enemy):
			var eid: int = int(enemy.combat_id())
			if eid > 0 and not existing_by_id.has(eid):
				existing_by_id[eid] = enemy
			else:
				_retire_enemy_node(enemy)

	var raw_roster: Array = data.get("enemies", data.get("roster", []))
	var restored_enemies: Array[Node3D] = []
	var used_ids: Dictionary = {}
	var max_restored_id: int = 0

	for entry_var in raw_roster:
		if restored_enemies.size() >= MAX_LIVE_ENEMIES:
			break
		if not (entry_var is Dictionary):
			continue
		var entry: Dictionary = entry_var
		if float(entry.get("health", 100.0)) <= 0.0:
			continue
		var eid: int = maxi(1, int(entry.get("rewind_id", entry.get("id", 0))))
		if used_ids.has(eid):
			continue
		used_ids[eid] = true
		max_restored_id = maxi(max_restored_id, eid)

		var enemy: Node3D = null
		if existing_by_id.has(eid):
			enemy = existing_by_id[eid]
			existing_by_id.erase(eid)
			if PatternEnemy.handles(StringName(entry.get("kind", "target"))) != (enemy.get_script() == PatternEnemy):
				_retire_enemy_node(enemy)
				enemy = null
		if enemy == null:
			enemy = PatternEnemy.new() if PatternEnemy.handles(StringName(entry.get("kind", "target"))) else EnemyNode.new()
			enemy.cover = cover
			enemy.rewind_id = eid
			add_child(enemy)
			var entry_kind := StringName(String(entry.get("kind", "target")))
			var entry_pos: Vector3 = entry.get("position", Vector3.ZERO)
			enemy.configure(entry_kind, entry_pos, eid)

		enemy.restore_state(entry)
		restored_enemies.append(enemy)

	for leftover_id in existing_by_id.keys():
		var leftover: Node3D = existing_by_id[leftover_id]
		_retire_enemy_node(leftover)

	enemies = restored_enemies
	var saved_counter: int = maxi(0, int(data.get("spawn_counter", _spawn_counter)))
	_spawn_counter = maxi(saved_counter, max_restored_id)
	flow.restore_state(data.get("flow", {}))
	_draw_arrivals()


func status_text() -> String:
	match encounter_state:
		&"running":
			var duration := float(Tuning.ENCOUNTER.duration)
			var total_waves := _total_scheduled_waves()
			if encounter_elapsed >= duration:
				return "Encounter Final Clear (%d left)" % enemies.size()
			return "Encounter Wave %d/%d (%.0fs/%.0fs)" % [encounter_wave_index, total_waves, encounter_elapsed, duration]
		&"victory":
			return "Encounter Victory! (F6 replay | R sandbox)"
		&"defeat":
			return "Player Down (0 HP) — Press R to reset or F6 to retry"
		_:
			return "Sandbox"


# Value-only hostile shots belong to the director, including after their owner dies.
# World time drives both their sweep and lifetime; rewind restores the whole list.
func launch_projectile(origin: Vector3, direction: Vector3, damage: float, speed := 7.5) -> bool:
	if projectiles.size() >= MAX_PROJECTILES or direction.length_squared() < .0001: return false
	projectiles.append({"position": Vector3(origin.x, 1.0, origin.z),
		"velocity": Vector3(direction.x, 0, direction.z).normalized() * speed,
		"damage": maxf(0, damage), "life": 6.0})
	_sync_projectile_visuals()
	return true


func _step_projectiles(dt: float, player: Node3D) -> void:
	if dt <= 0: return
	if cover == null: cover = CoverScript.new()
	var live: Array[Dictionary] = []
	for shot: Dictionary in projectiles:
		var start: Vector3 = shot.position
		var end: Vector3 = start + shot.velocity * minf(dt, shot.life)
		var obstacle: Dictionary = cover.clip_segment(start, end, .18)
		var fraction := float(obstacle.fraction)
		var hit_player := false
		if is_instance_valid(player) and float(player.health) > 0:
			var a := Vector2(start.x, start.z)
			var b := Vector2(end.x, end.z)
			var p := Vector2(player.position.x, player.position.z)
			var movement := b - a
			var offset := a - p
			var length_sq := movement.length_squared()
			# Earliest segment/circle entry, so cover behind the player cannot absorb it.
			var discriminant := pow(2 * offset.dot(movement), 2) - 4 * length_sq * (offset.length_squared() - .68 * .68)
			if offset.length_squared() <= .68 * .68:
				hit_player = true
			elif length_sq > .000001 and discriminant >= 0:
				var entry := (-2 * offset.dot(movement) - sqrt(discriminant)) / (2 * length_sq)
				hit_player = entry >= 0 and entry <= fraction and entry <= 1
		if hit_player:
			player.take_damage(float(shot.damage))
			continue
		shot.life = maxf(0, float(shot.life) - dt)
		if obstacle.blocked or shot.life <= 0: continue
		shot.position = end
		live.append(shot)
	projectiles = live
	_sync_projectile_visuals()


func _sync_projectile_visuals() -> void:
	while _projectile_visuals.size() < projectiles.size():
		var node := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = .2
		mesh.height = .4
		node.mesh = mesh
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color("ff684d")
		node.material_override = material
		add_child(node)
		_projectile_visuals.append(node)
	for i in range(_projectile_visuals.size()):
		_projectile_visuals[i].visible = i < projectiles.size()
		if i < projectiles.size(): _projectile_visuals[i].position = projectiles[i].position
