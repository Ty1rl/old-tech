extends Node3D

var selected_tool: int = 1


# jam-3 owns this implementation. The arena supplies floor-space aim.
func handle_event(_event: InputEvent, _player: Node3D, _aim: Vector3) -> void:
	pass


func step(_delta: float, _player: Node3D, _aim: Vector3, _enemies: Array) -> void:
	pass


func cancel_input() -> void:
	pass


func reset_state() -> void:
	selected_tool = 1
	cancel_input()


func status_text() -> String:
	return "Weapons pending jam-3"
