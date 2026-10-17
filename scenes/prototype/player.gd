extends "res://scenes/player.gd"

const Tuning = preload("res://scenes/prototype/tuning.gd")
var equipment: RefCounted
var health: float = Tuning.PLAYER.health
var slow_charge: float = Tuning.SLOW.capacity
# Effective enemy-clock multiplier for the current arena tick. On the tick
# that runs out of charge it averages the slowed and normal portions.
var world_scale: float = 1.0
var _slow_held := false
var _slow_release_required := false


func _ready() -> void:
	set_physics_process(false)


# The arena is the only simulation clock. Do not also run the inherited tick.
func _physics_process(_delta: float) -> void:
	pass


func _unhandled_input(_event: InputEvent) -> void:
	pass


func step(delta: float, aim: Vector3) -> void:
	_step_slow(delta, Input.is_physical_key_pressed(KEY_SPACE))
	_input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	speed = Tuning.PLAYER.speed
	_update_velocity(delta)
	move_and_slide()
	var direction := aim - global_position
	direction.y = 0.0
	if direction.length_squared() > 0.001 and is_instance_valid(model):
		model.global_basis = Basis.looking_at(direction)


func _step_slow(delta: float, held: bool) -> void:
	# A small input/charge helper shared with checks; only step() calls it in
	# gameplay, using the arena's real delta. It has no independent clock.
	var dt := maxf(delta, 0.0)
	var capacity: float = Tuning.SLOW.capacity
	slow_charge = clampf(slow_charge, 0.0, capacity)
	_slow_held = held
	world_scale = 1.0
	if not held:
		_slow_release_required = false
		slow_charge = minf(capacity, slow_charge + Tuning.SLOW.regeneration * dt)
		return
	if _slow_release_required:
		return
	if slow_charge <= 0.0:
		_slow_release_required = true
		return
	if dt <= 0.0:
		world_scale = Tuning.SLOW.scale
		return
	var active_seconds := minf(dt, slow_charge / Tuning.SLOW.drain)
	slow_charge = maxf(0.0, slow_charge - Tuning.SLOW.drain * active_seconds)
	world_scale = lerpf(1.0, Tuning.SLOW.scale, active_seconds / dt)
	if slow_charge <= 0.000001:
		slow_charge = 0.0
		_slow_release_required = true


func take_damage(amount: float) -> void:
	health = maxf(0.0, health - maxf(0.0, amount))


func reset_state() -> void:
	global_position = Vector3(0, 0.55, 0)
	reset_physics_interpolation()
	velocity = Vector3.ZERO
	health = Tuning.PLAYER.health
	slow_charge = Tuning.SLOW.capacity
	world_scale = 1.0
	reset_input()
	if is_instance_valid(model):
		model.basis = Basis.IDENTITY


func reset_input() -> void:
	_input_dir = Vector2.ZERO
	velocity = Vector3.ZERO
	_slow_held = false
	_slow_release_required = true
	world_scale = 1.0


func status_text() -> String:
	var hint := "hold Space"
	if _slow_release_required:
		hint = "release Space to re-arm"
	elif _slow_held:
		hint = "slowing enemies"
	elif slow_charge < Tuning.SLOW.capacity:
		hint = "recharging; hold Space to slow"
	return "Slow %.1f / %.1f | %s" % [slow_charge, Tuning.SLOW.capacity, hint]
