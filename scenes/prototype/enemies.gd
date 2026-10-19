extends Node3D

signal enemy_event(enemy_kind: StringName, event: StringName, point: Vector3, strength: float)
signal combat_event(kind: StringName, point: Vector3, strength: float)

# Arena drives this director with world time; there is no independent clock.
const Tuning = preload("res://scenes/prototype/tuning.gd")
const PatternEnemy = preload("res://scenes/prototype/pattern_enemy.gd")
const EnemyNode = preload("res://scenes/prototype/enemy.gd")
const CoverScript = preload("res://scenes/prototype/cover.gd")
const NavigationScene = preload("res://scenes/navigation/exhibit_navigation.tscn")
var navigation: ExhibitNavigation
var combat_difficulty: CampaignDifficulty
var _movement_time: TimeController

const Flow = preload("res://scenes/prototype/flow.gd")
const MAX_LIVE_ENEMIES := 32
const MAX_PROJECTILES := 24
const PROJECTILE_RADIUS := EnemyNode.HOSTILE_RADIUS
const PROJECTILE_LIFETIME := 6.0
const MAX_OWNER_PROJECTILES := 6
var _projectile_material: StandardMaterial3D
var _trail_mesh: ImmediateMesh
var _projectile_sequence := 0
# Stops a caller's old tick after synchronous emergency restore or room retry.
# Control-flow generation only: never rewind or capture it as world state.
var _world_revision := 0
var _repair_head_layer: CanvasLayer


class RepairShotHeads extends Control:
	var director: Node3D
	var had_shots := false
	func _process(_delta: float) -> void:
		var has_shots: bool = is_instance_valid(director) and not director.projectiles.is_empty()
		if has_shots or had_shots: queue_redraw()
		had_shots = has_shots
	func _draw() -> void:
		if not is_instance_valid(director): return
		for head: Dictionary in director.repair_head_projections():
			# The same projected head/trail, drawn above the opaque repair prop.
			# Input passes through; no targeting, HUD controls or simulation here.
			draw_line(head.tail, head.point, Color("241318"), head.radius * .9, true)
			draw_line(head.tail, head.point, Color("fa5547"), head.radius * .6, true)
			draw_circle(head.point, head.radius, Color("201518"))
			draw_circle(head.point, head.radius * .83, Color("ff4e41"))
			draw_circle(head.point, head.radius * .46, Color("fff5d9"))
var projectiles: Array[Dictionary] = []
var _projectile_visuals: Array[MeshInstance3D] = []
var flow: CombatFlow = Flow.new()
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


func _ready() -> void:
	if cover == null: cover = CoverScript.new()
	navigation = NavigationScene.instantiate()
	navigation.cover = cover
	add_child(navigation)


func _bind_movement_time(player: Node3D) -> void:
	if not is_instance_valid(player): return
	var controller: TimeController = player.time_controller
	if controller == _movement_time: return
	if is_instance_valid(_movement_time):
		_movement_time.emergency_started.disconnect(_on_movement_emergency)
		_movement_time.attempt_exhausted.disconnect(_suspend_navigation)
	_movement_time = controller
	if controller != null:
		controller.emergency_started.connect(_on_movement_emergency)
		controller.attempt_exhausted.connect(_suspend_navigation)

func _on_movement_emergency(_charges: int) -> void: _suspend_navigation()

func _suspend_navigation() -> void:
	for enemy: CombatEnemy in enemies:
		if is_instance_valid(enemy): enemy.navigation.suspend_avoidance()


func _total_scheduled_waves() -> int:
	var duration := float(Tuning.ENCOUNTER.duration)
	var interval := maxf(0.1, float(Tuning.ENCOUNTER.interval))
	return int(floor((duration - 0.001) / interval)) + 1


func step(world_delta: float, player: Node3D) -> void:
	var revision := _world_revision
	_bind_movement_time(player)
	if world_delta <= 0 or (is_instance_valid(player) and not player.can_act): _suspend_navigation()
	if _suspend_for_player(player): return
	if world_delta > 0:
		var previous_navigation := navigation.generation
		navigation.sync_region()
		if navigation.generation != previous_navigation: _suspend_navigation()
	_prune_dead_enemies()
	_discard_orphaned_projectiles()
	_step_projectiles(maxf(0, world_delta), player)
	if revision != _world_revision or _suspend_for_player(player): return

	if encounter_state == &"running":
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
	var cohesion: Dictionary = flow.cohesion(world_delta, snapshot, holds)
	for enemy in snapshot:
		if is_instance_valid(enemy) and enemy.health > 0.0 and (not is_instance_valid(player) or player.can_act):
			var hold := float(holds.get(int(enemy.combat_id()), 0.0))
			if hold > 0:
				var speed := float(enemy.move_speed)
				enemy.move_speed = 0.0
				enemy.step_enemy(hold, player, snapshot)
				enemy.move_speed = speed
				if revision != _world_revision or _suspend_for_player(player): return
			if world_delta - hold > 0:
				var speed := float(enemy.move_speed)
				enemy.move_speed = speed * flow.approach_scale(int(enemy.combat_id()))
				enemy.step_enemy(world_delta - hold, player, snapshot, cohesion.get(int(enemy.combat_id()), Vector3.ZERO))
				enemy.move_speed = speed
			if revision != _world_revision or _suspend_for_player(player): return
	_draw_arrivals()
	_prune_dead_enemies()

	if encounter_state == &"running" and encounter_elapsed >= float(Tuning.ENCOUNTER.duration) and enemies.is_empty():
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
	var enemy: CombatEnemy = PatternEnemy.new() if PatternEnemy.handles(kind) else EnemyNode.new()
	enemy.combat_difficulty = combat_difficulty
	enemy.cover = cover
	_spawn_counter += 1
	enemy.rewind_id = _spawn_counter
	var limit := float(Tuning.ARENA_HALF_SIZE) - 1.0
	var clamped_pos := Vector3(
		clampf(spawn_position.x, -limit, limit),
		0.0,
		clampf(spawn_position.z, -limit, limit)
	)
	_bind_enemy(enemy)
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
	# Ranged arrivals take independent, seeded flanks instead of joining the
	# melee clump. Reuse the same bounded cover/spacing/escape-lane placement.
	var melee: Array = []
	var ranged_count := 0
	for kind in kinds.slice(0, Flow.MAX_MEMBERS):
		if kind == &"ranged": ranged_count += 1
		else: melee.append(kind)
	var slots: Array = flow.layout(formation, melee, player.position, cover, seed, enemies)
	for slot: Dictionary in slots:
		var enemy := spawn(StringName(slot.kind), slot.position)
		if enemy != null: result.append(enemy)
	for index in range(ranged_count):
		var ranged_slots: Array = flow.layout(&"mixed", [&"ranged"], player.position, cover, seed + 17 + index * 31, enemies)
		if not ranged_slots.is_empty():
			var enemy := spawn(&"ranged", ranged_slots[0].position)
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
	_world_revision += 1
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
		"projectile_sequence": _projectile_sequence,
		"flow": flow.capture_state(),
		"spawn_counter": int(_spawn_counter),
		"encounter_active": bool(encounter_active),
		"encounter_state": String(encounter_state),
		"encounter_elapsed": float(encounter_elapsed),
		"encounter_wave_index": int(encounter_wave_index),
		"enemies": roster_data,
	}


func restore_state(data: Dictionary) -> void:
	_world_revision += 1
	if cover == null:
		cover = CoverScript.new()
	projectiles.clear()
	_projectile_sequence = maxi(0, int(data.get("projectile_sequence", 0)))
	for raw: Variant in data.get("projectiles", []):
		if projectiles.size() >= MAX_PROJECTILES: break
		if raw is Dictionary and raw.get("position") is Vector3 and raw.get("velocity") is Vector3 and raw.position.is_finite() and raw.velocity.is_finite():
			var velocity := Vector3(raw.velocity.x, 0, raw.velocity.z).limit_length(9)
			if velocity.length_squared() < .0001 or float(raw.get("life", 0)) <= 0: continue
			projectiles.append({"position": raw.position, "velocity": velocity,
				"damage": maxf(0, float(raw.get("damage", 10))),
				"life": clampf(float(raw.get("life", 0)), 0, PROJECTILE_LIFETIME),
				"age": clampf(float(raw.get("age", 0)), 0, PROJECTILE_LIFETIME),
				"radius": PROJECTILE_RADIUS, "owner_id": maxi(0, int(raw.get("owner_id", 0))),
				"id": maxi(0, int(raw.get("id", 0)))})
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

		var enemy: CombatEnemy = null
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

		_bind_enemy(enemy)
		enemy.combat_difficulty = combat_difficulty
		enemy.restore_state(entry)
		restored_enemies.append(enemy)

	for leftover_id in existing_by_id.keys():
		var leftover: Node3D = existing_by_id[leftover_id]
		_retire_enemy_node(leftover)

	enemies = restored_enemies
	var saved_counter: int = maxi(0, int(data.get("spawn_counter", _spawn_counter)))
	_spawn_counter = maxi(saved_counter, max_restored_id)
	flow.restore_state(data.get("flow", {}))
	_discard_orphaned_projectiles()
	_sync_projectile_visuals()
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
			return "Time depleted - Press R to reset or F6 to retry"
		_:
			return "Sandbox"


# Emissions are actor-owned; flight/visuals/snapshots are director-owned values.
# Owner=0 is reserved for explicit standalone probes, not live enemy emissions.
# damage is the base hostile time cost; TimeController applies hit tuning once.
func launch_projectile(origin: Vector3, direction: Vector3, damage: float, speed := 7.5, owner_id: int = 0) -> bool:
	var flat := Vector3(direction.x, 0, direction.z)
	if projectiles.size() >= MAX_PROJECTILES or not origin.is_finite() or not flat.is_finite() or flat.length_squared() < .0001 or speed <= 0: return false
	if owner_id > 0:
		var owner_alive := false
		var owner_position := origin
		var owned := 0
		for enemy in enemies:
			if is_instance_valid(enemy) and enemy.combat_id() == owner_id and enemy.health > 0:
				owner_alive = true
				owner_position = enemy.position
		for shot: Dictionary in projectiles:
			if int(shot.get("owner_id", 0)) == owner_id: owned += 1
		if not owner_alive or owned >= MAX_OWNER_PROJECTILES: return false
		if cover == null: cover = CoverScript.new()
		if cover.clip_segment(owner_position, origin, PROJECTILE_RADIUS).blocked: return false
	_projectile_sequence += 1
	projectiles.append({"position": origin, "velocity": flat.normalized() * clampf(speed, 1, 9),
		"damage": maxf(0, damage), "life": PROJECTILE_LIFETIME, "age": 0.0,
		"radius": PROJECTILE_RADIUS, "owner_id": owner_id, "id": _projectile_sequence})
	_sync_projectile_visuals()
	return true


# Jam-1 connects this signal to CombatFeedback.enemy_cue. No audio implementation,
# replayed barks or private feedback lookup is needed for these semantic events.
func _bind_enemy(enemy: CombatEnemy) -> void:
	enemy._ensure_navigation()
	enemy.navigation.maps = navigation
	if not enemy.enemy_event.is_connected(_on_enemy_event):
		enemy.enemy_event.connect(_on_enemy_event)


func _on_enemy_event(enemy_kind: StringName, event: StringName, point: Vector3, strength: float) -> void:
	enemy_event.emit(enemy_kind, event, point, strength)


func hostile_cue(kind: StringName, point: Vector3, strength: float = 1.0) -> void:
	combat_event.emit(kind, point, strength)
	# Existing arena/campaign feedback is optional for standalone probes. Route
	# through its established cue method without adding another audio system.
	var stage := get_parent()
	if stage != null and "feedback" in stage:
		var feedback: Variant = stage.get("feedback")
		if is_instance_valid(feedback) and feedback.has_method("cue"):
			var callback := Callable(feedback, "cue")
			if not combat_event.is_connected(callback): callback.call(kind, point, strength)


func _discard_orphaned_projectiles() -> void:
	var living := {}
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.health > 0: living[int(enemy.combat_id())] = true
	var live: Array[Dictionary] = []
	for shot: Dictionary in projectiles:
		if int(shot.get("owner_id", 0)) == 0 or living.has(int(shot.owner_id)): live.append(shot)
	projectiles = live


func _player_entry(start: Vector3, finish: Vector3, point: Vector3, radius: float) -> float:
	var a := Vector2(start.x - point.x, start.z - point.z)
	var movement := Vector2(finish.x - start.x, finish.z - start.z)
	if a.length_squared() <= radius * radius: return 0.0
	var length_sq := movement.length_squared()
	if length_sq < .000001: return -1.0
	var linear := 2 * a.dot(movement)
	var discriminant := linear * linear - 4 * length_sq * (a.length_squared() - radius * radius)
	if discriminant < 0: return -1.0
	var entry := (-linear - sqrt(discriminant)) / (2 * length_sq)
	return entry if entry >= 0 and entry <= 1 else -1.0


# An emergency is a suspended encounter, not defeat. Remaining flight is kept
# for NOW/rewind; only exhausted attempts discard it and finish the encounter.
func _suspend_for_player(player: Node3D) -> bool:
	if not is_instance_valid(player) or player.can_act: return false
	var controller: TimeController = player.time_controller
	if controller.exhausted:
		flow.pressure_active = false
		projectiles.clear()
		if encounter_state == &"running":
			encounter_active = false
			encounter_state = &"defeat"
	_sync_projectile_visuals()
	return true


func _step_projectiles(dt: float, player: Node3D) -> void:
	var revision := _world_revision
	if _suspend_for_player(player): return
	if dt <= 0:
		_sync_projectile_visuals()
		return
	if cover == null: cover = CoverScript.new()
	var index := 0
	while index < projectiles.size():
		var shot: Dictionary = projectiles[index]
		if float(shot.life) <= 0:
			projectiles.remove_at(index)
			continue
		var travel_dt := minf(dt, float(shot.life))
		var start: Vector3 = shot.position
		var end: Vector3 = start + shot.velocity * travel_dt
		var radius := float(shot.get("radius", PROJECTILE_RADIUS))
		var obstacle: Dictionary = cover.clip_segment(start, end, radius)
		var entry := -1.0
		if is_instance_valid(player): entry = _player_entry(start, end, player.position, EnemyNode.PLAYER_CONTACT_RADIUS + radius)
		# Cover wins exact ties and also shields a player already overlapping a
		# blocked muzzle. A wall behind the player cannot absorb an earlier hit.
		if entry >= 0 and (not obstacle.blocked or entry < float(obstacle.fraction) - .000001):
			# Retire this impact BEFORE apply_hit can emit emergency_started and
			# capture/restore NOW synchronously. Unprocessed shots stay frozen.
			projectiles.remove_at(index)
			_sync_projectile_visuals()
			var controller: TimeController = player.time_controller
			var before := controller.meter
			player.take_damage(float(shot.damage))
			var spent := before - controller.meter
			if spent > 0:
				hostile_cue(&"player_hurt", player.position, clampf(spent / 15, .65, 1.25))
			if revision != _world_revision or _suspend_for_player(player): return
			continue
		shot.life = maxf(0, float(shot.life) - dt)
		if obstacle.blocked or shot.life <= 0:
			projectiles.remove_at(index)
			continue
		shot.position = end
		shot.age = minf(PROJECTILE_LIFETIME, float(shot.get("age", 0)) + travel_dt)
		index += 1
	_sync_projectile_visuals()


func _head_material() -> StandardMaterial3D:
	if _projectile_material != null: return _projectile_material
	# A single procedural camera-facing head: dark rim, hostile warm red,
	# ivory centre. Its world-space diameter is exactly the collision diameter.
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(64):
			var d := Vector2(float(x) + .5 - 32, float(y) + .5 - 32).length() / 32
			var color := Color.TRANSPARENT
			if d < 1.0:
				color = Color("201518") if d > .83 else (Color("ff4e41") if d > .46 else Color("fff5d9"))
			image.set_pixel(x, y, color)
	_projectile_material = StandardMaterial3D.new()
	_projectile_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_projectile_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_projectile_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_projectile_material.alpha_scissor_threshold = .1
	_projectile_material.albedo_texture = ImageTexture.create_from_image(image)
	_projectile_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _projectile_material


func repair_head_projections() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if get_tree().paused or projectiles.is_empty(): return result
	var stage := get_parent()
	if stage == null or not "equipment" in stage or stage.get("equipment").repairing == &"": return result
	var manager := get_node_or_null("/root/SceneManager")
	if manager == null or not manager.has_popup(&"Repair"): return result
	for key in manager.POPUPS:
		if key != &"Repair" and manager.has_popup(key): return result
	var camera := get_viewport().get_camera_3d()
	if camera == null: return result
	for shot: Dictionary in projectiles:
		var point: Vector3 = shot.position
		if camera.is_position_behind(point): continue
		if cover != null and "player" in stage and cover.clip_segment(point, stage.get("player").position).blocked: continue
		var screen := camera.unproject_position(point)
		if not get_viewport().get_visible_rect().has_point(screen): continue
		var radius := screen.distance_to(camera.unproject_position(point + camera.global_basis.x * float(shot.get("radius", PROJECTILE_RADIUS))))
		var velocity: Vector3 = shot.velocity
		var tail := point - velocity.normalized() * minf(.8, velocity.length() * float(shot.get("age", 0)))
		result.append({"point": screen, "radius": radius, "tail":camera.unproject_position(tail)})
	return result


func _trail_triangle(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	for point in [a, b, c]:
		_trail_mesh.surface_set_color(color)
		_trail_mesh.surface_add_vertex(point)


func _trail_ribbon(start: Vector3, finish: Vector3, half_width: float, color: Color) -> void:
	var side := (finish - start).cross(Vector3.UP).normalized() * half_width
	_trail_triangle(start - side, start + side, finish - side, color)
	_trail_triangle(start + side, finish + side, finish - side, color)


func _sync_projectile_visuals() -> void:
	if _repair_head_layer == null:
		_repair_head_layer = CanvasLayer.new()
		_repair_head_layer.name = "HostileHeadsDuringRepair"
		var manager := get_node_or_null("/root/SceneManager")
		_repair_head_layer.layer = int(manager.POPUP_LAYER) + 1 if manager != null else 101
		var heads := RepairShotHeads.new()
		heads.director = self
		heads.mouse_filter = Control.MOUSE_FILTER_IGNORE
		heads.process_mode = Node.PROCESS_MODE_ALWAYS
		_repair_head_layer.add_child(heads)
		add_child(_repair_head_layer)
	while _projectile_visuals.size() < projectiles.size():
		var node := MeshInstance3D.new()
		var mesh := QuadMesh.new()
		mesh.size = Vector2.ONE * PROJECTILE_RADIUS * 2
		node.mesh = mesh
		node.material_override = _head_material()
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		_projectile_visuals.append(node)
	for i in range(_projectile_visuals.size()):
		_projectile_visuals[i].visible = i < projectiles.size()
		if i < projectiles.size():
			_projectile_visuals[i].position = projectiles[i].position
			_projectile_visuals[i].mesh.size = Vector2.ONE * float(projectiles[i].get("radius", PROJECTILE_RADIUS)) * 2
	if _trail_mesh == null:
		_trail_mesh = ImmediateMesh.new()
		var node := MeshInstance3D.new()
		node.name = "HostileShortTrails"
		node.mesh = _trail_mesh
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.vertex_color_use_as_albedo = true
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
	_trail_mesh.clear_surfaces()
	if projectiles.is_empty(): return
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for shot: Dictionary in projectiles:
		var head: Vector3 = shot.position
		var velocity: Vector3 = shot.velocity
		var direction := velocity.normalized()
		var tail := head - direction * minf(.8, velocity.length() * float(shot.get("age", 0)))
		_trail_ribbon(tail, head, .11, Color("241318"))
		_trail_ribbon(tail, head, .075, Color("fa5547"))
		_trail_ribbon(tail, head, .022, Color("fff1cf"))
	_trail_mesh.surface_end()
