extends Node3D

# jam-4 owns this implementation and enemy.gd. No independent process clock.
const Tuning = preload("res://scenes/prototype/tuning.gd")
const EnemyNode = preload("res://scenes/prototype/enemy.gd")

var enemies: Array[Node3D] = []
var _spawn_counter: int = 0


func step(world_delta: float, player: Node3D) -> void:
	_prune_dead_enemies()
	var snapshot: Array[Node3D] = enemies.duplicate()
	for enemy in snapshot:
		if is_instance_valid(enemy) and enemy.health > 0.0:
			enemy.step_enemy(world_delta, player, snapshot)
	_prune_dead_enemies()


func _prune_dead_enemies() -> void:
	var live: Array[Node3D] = []
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy.health <= 0.0:
			enemy.queue_free()
			continue
		live.append(enemy)
	enemies = live


func spawn(kind: StringName, spawn_position: Vector3) -> Node3D:
	var enemy := EnemyNode.new()
	_spawn_counter += 1
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


func clear() -> void:
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	enemies.clear()


func reset_state() -> void:
	clear()
	_spawn_counter = 0
	spawn(&"target", Vector3(0.0, 0.0, -6.0))
