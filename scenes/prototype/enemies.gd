extends Node3D

# jam-4 owns this implementation and enemy.gd. No independent process clock.
const Tuning = preload("res://scenes/prototype/tuning.gd")
const EnemyNode = preload("res://scenes/prototype/enemy.gd")
const CoverScript = preload("res://scenes/prototype/cover.gd")
const MAX_LIVE_ENEMIES := 32

var enemies: Array[Node3D] = []
var cover: RefCounted
var _spawn_counter: int = 0

# Bounded encounter state (world seconds)
var encounter_active: bool = false
var encounter_state: StringName = &"sandbox" # &"sandbox", &"running", &"victory", &"defeat"
var encounter_elapsed: float = 0.0
var encounter_wave_index: int = 0

const WAVE_TEMPLATES: Array[Array] = [
	[
		{"kind": &"swarmer", "pos": Vector3(-7.5, 0.0, -9.5)},
		{"kind": &"swarmer", "pos": Vector3(7.5, 0.0, -9.5)},
		{"kind": &"skirmisher", "pos": Vector3(0.0, 0.0, -11.5)},
	],
	[
		{"kind": &"swarmer", "pos": Vector3(-9.5, 0.0, -4.0)},
		{"kind": &"swarmer", "pos": Vector3(9.5, 0.0, -4.0)},
		{"kind": &"brute", "pos": Vector3(0.0, 0.0, -12.0)},
	],
	[
		{"kind": &"skirmisher", "pos": Vector3(-8.5, 0.0, 5.5)},
		{"kind": &"skirmisher", "pos": Vector3(8.5, 0.0, 5.5)},
		{"kind": &"swarmer", "pos": Vector3(0.0, 0.0, -10.5)},
	],
	[
		{"kind": &"swarmer", "pos": Vector3(-8.0, 0.0, -8.5)},
		{"kind": &"swarmer", "pos": Vector3(8.0, 0.0, -8.5)},
		{"kind": &"brute", "pos": Vector3(-2.5, 0.0, -12.0)},
	],
	[
		{"kind": &"swarmer", "pos": Vector3(-9.0, 0.0, 6.0)},
		{"kind": &"swarmer", "pos": Vector3(9.0, 0.0, 6.0)},
		{"kind": &"skirmisher", "pos": Vector3(-6.5, 0.0, -10.5)},
		{"kind": &"brute", "pos": Vector3(2.5, 0.0, -12.0)},
	],
	[
		{"kind": &"swarmer", "pos": Vector3(-7.0, 0.0, -10.0)},
		{"kind": &"swarmer", "pos": Vector3(7.0, 0.0, -10.0)},
		{"kind": &"skirmisher", "pos": Vector3(0.0, 0.0, 9.5)},
		{"kind": &"brute", "pos": Vector3(0.0, 0.0, -12.5)},
	],
]


func _total_scheduled_waves() -> int:
	var duration := float(Tuning.ENCOUNTER.duration)
	var interval := maxf(0.1, float(Tuning.ENCOUNTER.interval))
	return int(floor((duration - 0.001) / interval)) + 1


func step(world_delta: float, player: Node3D) -> void:
	_prune_dead_enemies()

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
	for enemy in snapshot:
		if is_instance_valid(enemy) and enemy.health > 0.0:
			enemy.step_enemy(world_delta, player, snapshot)
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
	var enemy := EnemyNode.new()
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
	spawn(&"swarmer", Vector3(-6.0, 0.0, -7.5))
	spawn(&"swarmer", Vector3(6.0, 0.0, -7.5))
	spawn(&"brute", Vector3(0.0, 0.0, -10.5))
	spawn(&"skirmisher", Vector3(-7.5, 0.0, 4.0))


func _cancel_encounter() -> void:
	encounter_active = false
	encounter_state = &"sandbox"
	encounter_elapsed = 0.0
	encounter_wave_index = 0


func clear() -> void:
	_cancel_encounter()
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
		else:
			enemy = EnemyNode.new()
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
