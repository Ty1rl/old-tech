extends "res://scenes/player.gd"

const Tuning = preload("res://scenes/prototype/tuning.gd")
var equipment: RefCounted
var health: float = Tuning.PLAYER.health
var slow_charge: float:
	get:
		return equipment.remaining(&"clock") if equipment != null else 0.0
# Effective enemy-clock multiplier for the current arena tick. On the tick
# that runs out of charge it averages the slowed and normal portions.
var world_scale: float = 1.0
var _slow_held := false
var _slow_release_required := false
var _last_repair: StringName = &""


func _ready() -> void:
	set_physics_process(false)


# The arena is the only simulation clock. Do not also run the inherited tick.
func _physics_process(_delta: float) -> void:
	pass


func _unhandled_input(_event: InputEvent) -> void:
	pass


func step(delta: float, aim: Vector3, slow_held: Variant = null, repair_slow: bool = false) -> void:
	_step_slow(delta, Input.is_physical_key_pressed(KEY_SPACE) if slow_held == null else bool(slow_held), repair_slow)
	_input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	speed = Tuning.PLAYER.speed
	_update_velocity(delta)
	move_and_slide()
	var direction := aim - global_position
	direction.y = 0.0
	if direction.length_squared() > 0.001 and is_instance_valid(model):
		model.global_basis = Basis.looking_at(direction)


func _step_slow(delta: float, held: bool, automatic: bool = false) -> void:
	# A small input/charge helper shared with checks; only step() calls it in
	# gameplay, using the arena's real delta. It has no independent clock.
	var dt := maxf(delta, 0.0)
	_slow_held = held or automatic
	world_scale = 1.0
	if equipment == null:
		_slow_release_required = true
		return
	if _last_repair != equipment.repairing:
		_last_repair = equipment.repairing
		_slow_release_required = true
	if not held and not automatic:
		_slow_release_required = false
		return
	if equipment.repairing == &"clock":
		_slow_release_required = true
		return
	if _slow_release_required and not automatic:
		return
	if slow_charge <= 0.0:
		_slow_release_required = true
		return
	if dt <= 0.0:
		world_scale = Tuning.SLOW.scale
		return
	var spent: float = equipment.spend(&"clock", Tuning.SLOW.drain * dt)
	var active_seconds: float = spent / Tuning.SLOW.drain
	world_scale = lerpf(1.0, Tuning.SLOW.scale, active_seconds / dt)
	if not equipment.can_use(&"clock"):
		_slow_release_required = true


func take_damage(amount: float) -> void:
	health = maxf(0.0, health - maxf(0.0, amount))


func reset_state() -> void:
	global_position = Vector3(0, 0.55, 0)
	reset_physics_interpolation()
	velocity = Vector3.ZERO
	health = Tuning.PLAYER.health
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
	_last_repair = equipment.repairing if equipment != null else &""


func status_text() -> String:
	var hint := "hold Space"
	if equipment != null and equipment.repairing == &"clock":
		hint = "clock repair; slow disabled"
	elif slow_charge <= 0.0:
		hint = "empty; 4 then hold E to repair clock"
	elif _slow_release_required:
		hint = "release Space to re-arm"
	elif _slow_held:
		hint = "slowing world"
	var capacity: float = equipment.capacity(&"clock") if equipment != null else 0.0
	return "Slow %.1f / %.1fs | %s" % [slow_charge, capacity, hint]


func capture_state() -> Dictionary:
	return {"position": position, "velocity": velocity, "health": health,
		"facing": model.basis if is_instance_valid(model) else Basis.IDENTITY}


func restore_state(data: Dictionary) -> void:
	reset_input()
	position = data.position
	velocity = data.velocity
	health = float(data.health)
	if is_instance_valid(model):
		model.basis = data.facing
	reset_physics_interpolation()
