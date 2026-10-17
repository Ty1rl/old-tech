extends CharacterBody3D

const MOVE_ACTIONS: Array[StringName] = [&"move_left", &"move_right", &"move_up", &"move_down"]

@export var camera: Camera3D
@export var model: Node3D
@export var speed: float = 6.0
@export var acceleration: float = 40.0
@export var turn_speed: float = 14.0
@export var mouse_active_time: float = 0.5

var _input_dir: Vector2
var _mouse_pos: Vector2
var _mouse_active_until_msec: int


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_mouse_pos = event.position
		_mouse_active_until_msec = Time.get_ticks_msec() + int(mouse_active_time * 1000.0)
	elif MOVE_ACTIONS.any(event.is_action):
		_input_dir = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")


func _physics_process(delta: float) -> void:
	_update_velocity(delta)
	move_and_slide()
	_update_facing(delta)


func _update_velocity(delta: float) -> void:
	var target := _get_move_direction() * speed
	target.y = velocity.y
	velocity = velocity.move_toward(target, acceleration * delta)
	if not is_on_floor():
		velocity += get_gravity() * delta


func _update_facing(delta: float) -> void:
	var dir := _get_facing_direction()
	if dir.is_zero_approx():
		return
	model.global_basis = model.global_basis.slerp(Basis.looking_at(dir), turn_speed * delta)


func _get_move_direction() -> Vector3:
	# Input "up" is -Y, which maps to -Z (forward). Rotated by the camera's yaw to make it screen-relative.
	return Vector3(_input_dir.x, 0.0, _input_dir.y).rotated(Vector3.UP, camera.global_rotation.y)


func _get_facing_direction() -> Vector3:
	if Time.get_ticks_msec() < _mouse_active_until_msec:
		return _get_mouse_direction()
	return _get_move_direction()


func _get_mouse_direction() -> Vector3:
	var origin := camera.project_ray_origin(_mouse_pos)
	var ray := camera.project_ray_normal(_mouse_pos)
	var hit: Variant = Plane(Vector3.UP, global_position.y).intersects_ray(origin, ray)
	return Vector3.ZERO if hit == null else (hit as Vector3) - global_position
