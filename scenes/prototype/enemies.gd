extends Node3D

var enemies: Array[Node3D] = []


# jam-4 owns this implementation and enemy.gd. No independent process clock.
func step(_world_delta: float, _player: Node3D) -> void:
	pass


func spawn(_kind: StringName, _position: Vector3) -> void:
	pass


func spawn_group() -> void:
	pass


func clear() -> void:
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	enemies.clear()


func reset_state() -> void:
	clear()
	spawn(&"target", Vector3(0, 0, -6))
