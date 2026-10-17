extends "res://scenes/player.gd"

const Tuning = preload("res://scenes/prototype/tuning.gd")
var health: float = Tuning.PLAYER.health
var slow_charge: float = Tuning.SLOW.capacity
var world_scale: float = 1.0


# The arena is the only simulation clock. Do not also run the inherited tick.
func _physics_process(_delta: float) -> void:
	pass


func _unhandled_input(_event: InputEvent) -> void:
	pass


func step(delta: float, aim: Vector3) -> void:
	_input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	speed = Tuning.PLAYER.speed
	_update_velocity(delta)
	move_and_slide()
	var direction := aim - global_position
	direction.y = 0.0
	if direction.length_squared() > 0.001:
		model.global_basis = Basis.looking_at(direction)


func take_damage(amount: float) -> void:
	health = maxf(0.0, health - amount)


func reset_state() -> void:
	global_position = Vector3(0, 0.55, 0)
	reset_physics_interpolation()
	velocity = Vector3.ZERO
	health = Tuning.PLAYER.health
	slow_charge = Tuning.SLOW.capacity
	world_scale = 1.0
	reset_input()


func reset_input() -> void:
	_input_dir = Vector2.ZERO
	velocity = Vector3.ZERO


func status_text() -> String:
	return "Movement ready; time slow pending jam-2"
