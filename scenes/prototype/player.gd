class_name CombatPlayer
extends CharacterBody3D
## The playable museum restorer: movement, aim facing and the hit-to-time bridge.
##
## There is no player health. take_damage() forwards the hit to the shared
## TimeController (scripts/time/CONTRACT.md) and reports what it actually cost.
## World time comes from the controller too: world_scale is a getter, never a
## stored copy. The arena calls step() once per physics tick; this node does not
## run its own simulation clock.

## Emitted when a hit actually spent time (grace-absorbed hits emit nothing).
signal wounded(amount: float)

const Tuning = preload("res://scenes/prototype/tuning.gd")
const SPAWN_HEIGHT := 0.55

@export var camera: Camera3D
## Facing root; the rig lives under it and turns with aim.
@export var model: Node3D
## Rigged visual (player_visual.gd, owned by the animation seat).
@export var visual: Node3D
## The arena's single TimeController. Unset only in isolated previews/tests.
@export var time_controller: TimeController

## Multiplier for world deltas this tick. 0.0 while an emergency freezes the world.
var world_scale: float:
	get: return time_controller.world_scale if is_instance_valid(time_controller) else 1.0
## False while an emergency is frozen or the room attempt is exhausted.
var can_act: bool:
	get: return not is_instance_valid(time_controller) or not (time_controller.emergency_active or time_controller.exhausted)
var visual_tool: int:
	get: return _visual_tool

var _visual_tool := 1


func _ready() -> void:
	set_visual_tool(_visual_tool)


## Movement and aim for one physics tick. `real_delta` is the engine tick; world
## time scaling is applied here. Nothing moves while the world is frozen.
func step(real_delta: float, aim: Vector3) -> void:
	var time_scale := world_scale
	var world_delta := real_delta * time_scale
	if not (world_delta > 0.0):
		return
	_update_velocity(world_delta, _move_input())
	# CharacterBody3D integrates with the engine's real delta: scale only the move,
	# then keep velocity in world units for snapshots and gait cadence.
	velocity *= time_scale
	move_and_slide()
	velocity /= time_scale
	_face(aim)
	if is_instance_valid(visual):
		var local_motion := model.global_basis.inverse() * Vector3(velocity.x, 0.0, velocity.z)
		visual.step_visual(world_delta, local_motion.length(), Tuning.PLAYER.speed, local_motion)


## Applies a hostile hit as time cost. Returns the time actually spent.
func take_damage(amount: float) -> float:
	if not is_instance_valid(time_controller):
		return 0.0
	var spent := time_controller.apply_hit(amount)
	if spent > 0.0:
		wounded.emit(spent)
	return spent


func set_visual_tool(index: int) -> void:
	_visual_tool = clampi(index, 1, 3)
	if is_instance_valid(visual):
		visual.set_tool_index(_visual_tool)


## Clears movement intent (popups, mode changes, restores). Time is untouched.
func reset_input() -> void:
	velocity = Vector3.ZERO


## Places the player for a room or sandbox start. Never creates an attempt or
## replenishes time/charges; that is TimeController.begin_attempt().
func reset_state(spawn: Vector3 = Vector3(0.0, SPAWN_HEIGHT, 0.0)) -> void:
	global_position = spawn
	reset_physics_interpolation()
	reset_input()
	if is_instance_valid(model):
		model.basis = Basis.IDENTITY
	set_visual_tool(1)
	if is_instance_valid(visual):
		visual.reset_pose()


## Value-only world snapshot. Time, charges and equipment are not player state.
func capture_state() -> Dictionary:
	return {"position": position, "velocity": velocity,
		"facing": model.basis if is_instance_valid(model) else Basis.IDENTITY}


func restore_state(data: Dictionary) -> void:
	if is_instance_valid(visual):
		visual.foot_plant.reset()
	reset_input()
	position = data.get("position", position)
	velocity = data.get("velocity", Vector3.ZERO)
	if is_instance_valid(model):
		model.basis = data.get("facing", Basis.IDENTITY)
	reset_physics_interpolation()


func _move_input() -> Vector3:
	var input := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	# Screen-relative: input "up" (-Y) is camera forward on the floor.
	var yaw := camera.global_rotation.y if is_instance_valid(camera) else 0.0
	return Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, yaw)


func _update_velocity(world_delta: float, direction: Vector3) -> void:
	var target := direction * float(Tuning.PLAYER.speed)
	var planar := Vector3(velocity.x, 0.0, velocity.z)
	var rate := float(Tuning.MOVEMENT.acceleration)
	if target.length_squared() < 0.0001:
		rate = float(Tuning.MOVEMENT.braking)
	elif target.dot(planar) < 0.0:
		rate = float(Tuning.MOVEMENT.reversal)
	planar = planar.move_toward(target, rate * world_delta)
	velocity.x = planar.x
	velocity.z = planar.z
	if not is_on_floor():
		velocity += get_gravity() * world_delta


func _face(aim: Vector3) -> void:
	if not is_instance_valid(model):
		return
	var direction := aim - global_position
	direction.y = 0.0
	if direction.length_squared() > 0.001:
		model.global_basis = Basis.looking_at(direction)
