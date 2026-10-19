extends Node3D

# Cosmetic only: the arena advances animation in world time. No independent tick
# or rig data enters the bounded gameplay history.
const FootPlant = preload("res://scenes/prototype/foot_plant.gd")
const Character = preload("res://assets/characters/protagonist/protagonist.glb")
const Tuning = preload("res://scenes/prototype/tuning.gd")
const TOOLS = [preload("res://assets/equipment/ring_caster.glb"),
	preload("res://assets/equipment/flash_camera.glb"),
	preload("res://assets/equipment/heat_bellows.glb"),
	preload("res://assets/equipment/time_device.glb")]
const TOOL_IDS: Array[StringName] = [&"ring", &"beam", &"cone", &"clock"]
const HOLDS = ["RingHold", "FlashHold", "ConeHold", "ClockHold"]
# Actual props have different handle spacing from the art-preview stand-ins.
# Lowered carriage clears the protagonist's face and chest in -55 deg perspective
# while keeping both handles comfortably within two-bone arm reach (< 0.016 m grip error).
const MOUNTS = [Vector3(.10, 1.31, -.03), Vector3(.26, 1.28, -.21),
	Vector3(-.04, 1.32, .01), Vector3(.145, 1.27, -.24)]

var foot_plant := FootPlant.new()
var character: Node3D
var skeleton: Skeleton3D
var animation: AnimationPlayer
var held_tool: Node3D
var tool_attachments: Dictionary = {}
var tool_index := 1
var tool_id: StringName = &"ring"
var walk_phase := 0.0
var idle_phase := 0.0
var stride_blend := 0.0
var cadence_hz := 0.0
var playback_rate := 1.0
var force_update_count := 0
var _run_blend := 0.0
var _strafe_blend := 0.0
var _forward_blend := 0.0
var _accel_lean := 0.0
var _stop_settle := 0.0
var _turn_sway := 0.0
var _equip_dip := 0.0
var _prev_speed := 0.0
var _prev_local_vel := Vector3.ZERO
var _last_yaw := 0.0
var _has_last_yaw := false
var _holds: Array[Dictionary] = []
var _sockets: Dictionary = {}
var _prop_sockets: Dictionary = {}
var _bones: Dictionary = {}
var _bone_parents: Dictionary = {}
var _clip_lengths: Dictionary = {}
var _equipped_index := 0
var _kick := 0.0
var _air_active := false
var _charge_ratio := 0.0
var _built := false


func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	build()


func build() -> void:
	if _built: return
	_built = true
	name = "PlayerVisual"
	# The unchanged collider's bottom is at the player root. That root settles
	# onto the floor after reset; model itself is offset +.5 above it.
	position = Vector3(0, -.5, 0)
	character = Character.instantiate()
	add_child(character)
	skeleton = character.find_children("*", "Skeleton3D", true, false)[0]
	animation = character.find_children("*", "AnimationPlayer", true, false)[0]
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for bone_name in ["root", "pelvis", "spine", "chest", "neck", "head"]:
		var b_idx := skeleton.find_bone(bone_name)
		if b_idx >= 0:
			_bones[bone_name] = b_idx
			_bone_parents[b_idx] = skeleton.get_bone_parent(b_idx)
	for side in ["L", "R"]:
		for part in ["clavicle", "upper_arm", "forearm", "hand", "thigh", "shin", "foot"]:
			var id: String = part + "." + side
			var b_idx := skeleton.find_bone(id)
			if b_idx >= 0:
				_bones[id] = b_idx
				_bone_parents[b_idx] = skeleton.get_bone_parent(b_idx)
		var socket: Node3D = character.find_child("Grip_" + side, true, false)
		_sockets[side] = socket.transform
	for clip_name in ["Idle", "Walk", "Run", "BackWalk"]:
		if animation.has_animation(clip_name):
			_clip_lengths[clip_name] = animation.get_animation(clip_name).length
	_cache_holds()
	held_tool = Node3D.new()
	held_tool.name = "HeldEquipment"
	add_child(held_tool)
	for index in range(TOOLS.size()):
		var prop: Node3D = TOOLS[index].instantiate()
		prop.scale = Vector3.ONE * float(Tuning.PLAYER.tool_scale)
		held_tool.add_child(prop)
		tool_attachments[TOOL_IDS[index]] = prop
		_prop_sockets[TOOL_IDS[index]] = {"L": prop.find_child("Grip_L", true, false),
			"R": prop.find_child("Grip_R", true, false), "Emitter": prop.find_child("Emitter", true, false)}
	set_tool_index(tool_index)
	reset_pose()


func _cache_holds() -> void:
	for clip in HOLDS:
		var pose := {}
		var source := animation.get_animation(clip)
		for track in range(source.get_track_count()):
			var path := source.track_get_path(track)
			if path.get_subname_count() != 1 or source.track_get_type(track) != Animation.TYPE_ROTATION_3D:
				continue
			var bone := String(path.get_subname(0))
			if bone in _bones and (bone.begins_with("upper_arm.") or bone.begins_with("forearm.") or bone.begins_with("hand.")):
				pose[_bones[bone]] = source.track_get_key_value(track, 0)
		_holds.append(pose)


func set_tool_index(index: int) -> void:
	build()
	tool_index = clampi(index, 1, 4)
	if _equipped_index == tool_index: return
	var had_previous := _equipped_index != 0
	_equipped_index = tool_index
	tool_id = TOOL_IDS[tool_index - 1]
	for id: StringName in tool_attachments:
		tool_attachments[id].visible = id == tool_id
	if had_previous:
		_equip_dip = 1.0
	_fit_equipment()


func reset_pose() -> void:
	build()
	foot_plant.reset()
	walk_phase = 0
	idle_phase = 0
	stride_blend = 0
	cadence_hz = 0
	playback_rate = 1.0
	force_update_count = 0
	_run_blend = 0
	_strafe_blend = 0
	_forward_blend = 0
	_accel_lean = 0
	_stop_settle = 0
	_turn_sway = 0
	_equip_dip = 0
	_prev_speed = 0
	_prev_local_vel = Vector3.ZERO
	_has_last_yaw = false
	_kick = 0
	_air_active = false
	_charge_ratio = 0
	animation.play("Idle")
	animation.seek(0, true)
	animation.advance(0)
	_fit_equipment()


func step_visual(world_delta: float, planar_speed: float, max_speed: float = 6.0, movement: Vector3 = Vector3.ZERO) -> void:
	build()
	if world_delta <= 0: return
	force_update_count = 0
	var dt := minf(world_delta, .25)
	var ratio := clampf(planar_speed / maxf(.001, max_speed), 0, 1)
	var blend_rate := 9.0 if ratio >= stride_blend else 6.5
	stride_blend = move_toward(stride_blend, ratio, dt * blend_rate)
	var moving := stride_blend > .04 and planar_speed > .05
	var local_dir := Vector3(movement.x, 0, movement.z)
	if local_dir.length_squared() < .0001 and moving:
		local_dir = Vector3(0, 0, -planar_speed)
	var norm_dir := local_dir.normalized() if local_dir.length_squared() > .0001 else Vector3.FORWARD

	# Track acceleration, braking settle, and facing-turn sway.
	var speed_delta := (planar_speed - _prev_speed) / maxf(dt, .004)
	var target_accel := clampf(speed_delta * .0024, -.075, .075)
	_accel_lean = move_toward(_accel_lean, target_accel if moving else 0.0, dt * .55)
	if _prev_speed > 1.8 and planar_speed <= .25:
		_stop_settle = maxf(_stop_settle, clampf(_prev_speed / maxf(max_speed, 1.0), .25, 1.0))
	elif _prev_local_vel.length_squared() > 2.25 and local_dir.length_squared() > 2.25 and _prev_local_vel.normalized().dot(norm_dir) < -.25:
		_stop_settle = maxf(_stop_settle, .75)
	_stop_settle = move_toward(_stop_settle, 0.0, dt * 5.2)
	_equip_dip = move_toward(_equip_dip, 0.0, dt * 6.5)
	_prev_speed = planar_speed
	_prev_local_vel = local_dir

	var parent_node := get_parent() as Node3D
	if parent_node != null:
		var yaw := parent_node.global_rotation.y
		if _has_last_yaw:
			var yaw_rate := clampf(angle_difference(_last_yaw, yaw) / maxf(dt, .004), -12.0, 12.0)
			_turn_sway = move_toward(_turn_sway, clampf(yaw_rate * .022, -.16, .16), dt * 1.4)
		else:
			_has_last_yaw = true
		_last_yaw = yaw
	_turn_sway = move_toward(_turn_sway, 0.0, dt * .85)

	# Hysteresis on clip selection prevents Walk/Run/BackWalk chatter on diagonal/threshold speeds.
	var cur_clip := animation.current_animation
	var back_thresh := .16 if cur_clip == "BackWalk" else .24
	var backing := moving and norm_dir.z > back_thresh
	var strafe_x_thresh := .66 if cur_clip == "Walk" else .74
	var mostly_strafe := moving and absf(norm_dir.x) > strafe_x_thresh and absf(norm_dir.z) < .58
	var run_speed_thresh := 3.55 if cur_clip == "Run" else 3.95
	var run_target := clampf((planar_speed - 3.2) / maxf(.5, max_speed - 3.2), 0, 1) if (moving and not backing and not mostly_strafe) else 0.0
	_run_blend = move_toward(_run_blend, run_target, dt * 6.5)
	_strafe_blend = move_toward(_strafe_blend, norm_dir.x * stride_blend if moving else 0.0, dt * 7.5)
	_forward_blend = move_toward(_forward_blend, -norm_dir.z * stride_blend if moving else 0.0, dt * 7.5)

	var clip := "Idle"
	if moving:
		clip = "BackWalk" if backing else ("Run" if (planar_speed > run_speed_thresh and not mostly_strafe) else "Walk")
	if cur_clip != clip:
		var prev_len: float = _clip_lengths.get(cur_clip, 1.0)
		var norm_pos := fposmod(animation.current_animation_position / maxf(prev_len, .001), 1.0) if cur_clip in ["Walk", "Run"] else 0.0
		var xfade := .20 if clip == "Idle" else .15
		animation.play(clip, xfade)
		if cur_clip in ["Walk", "Run"] and clip in ["Walk", "Run"]:
			var next_len: float = _clip_lengths.get(clip, 1.0)
			animation.seek(norm_pos * next_len, false)

	var cycle: float = _clip_lengths.get(clip, 1.0)
	if moving:
		if backing:
			cadence_hz = lerpf(.85, 1.48, ratio)
		elif clip == "Run":
			cadence_hz = lerpf(1.36, 1.76, run_target)
		else:
			cadence_hz = lerpf(.88, 1.52, ratio)
		playback_rate = clampf(cadence_hz * cycle, .35, 1.85)
	else:
		cadence_hz = 0.0
		playback_rate = 1.0

	skeleton.reset_bone_poses()
	animation.advance(dt * playback_rate)

	if moving:
		walk_phase += dt * cadence_hz * TAU
	else:
		idle_phase += dt

	var has_residual_motion := moving or stride_blend > .005 or _stop_settle > .005 or absf(_turn_sway) > .003
	if has_residual_motion:
		_apply_gait_shaping()
	foot_plant.reset()
	_fit_equipment()


func _apply_gait_shaping() -> void:
	var root_idx: int = _bones.get("root", -1)
	if root_idx >= 0:
		var root_pos := skeleton.get_bone_pose_position(root_idx)
		# Keep authored root bounce bounded while preserving braking settle.
		root_pos.y = clampf(root_pos.y * .72 - _stop_settle * .018 - absf(_turn_sway) * .015, -.056, .02)
		root_pos.x = root_pos.x * .65 - _strafe_blend * .016 - _turn_sway * .028
		root_pos.z = root_pos.z * .65 - _accel_lean * .12 + _stop_settle * .014
		skeleton.set_bone_pose_position(root_idx, root_pos)

	# Keep thigh, shin, and foot rotations strictly on the authored AnimationPlayer clips.
	# Steer pelvis horizontally (Y-yaw only) into lateral strafes without pitching or rolling
	# the hip sockets, and counter-twist spine/chest so the upper body and weapon stay aimed forward.
	var strafe_sign := -1.0 if _forward_blend < -.1 else 1.0
	var strafe_yaw := clampf(-_strafe_blend * strafe_sign * .44, -.42, .42)
	var forward_lean := -_forward_blend * (.046 + .044 * _run_blend) - _accel_lean * .42 + _stop_settle * .052
	var pelvis_idx: int = _bones.get("pelvis", -1)
	if pelvis_idx >= 0:
		var p_model := Quaternion(Vector3.UP, strafe_yaw + _turn_sway * .28)
		_rotate_bone_model_space(pelvis_idx, p_model)
	var spine_idx: int = _bones.get("spine", -1)
	if spine_idx >= 0:
		var sp_model := Quaternion(Vector3.UP, -strafe_yaw * .55 - _turn_sway * .20) * Quaternion(Vector3.BACK, -_strafe_blend * .028 - _turn_sway * .16) * Quaternion(Vector3.RIGHT, forward_lean * .65)
		_rotate_bone_model_space(spine_idx, sp_model)
	var chest_idx: int = _bones.get("chest", -1)
	if chest_idx >= 0:
		var ch_model := Quaternion(Vector3.UP, -strafe_yaw * .45 - _turn_sway * .16) * Quaternion(Vector3.BACK, -_strafe_blend * .022 - _turn_sway * .14) * Quaternion(Vector3.RIGHT, forward_lean * .60)
		_rotate_bone_model_space(chest_idx, ch_model)
	var neck_idx: int = _bones.get("neck", -1)
	if neck_idx >= 0:
		# Keep head and eyes level looking downrange rather than pitching toward the floor during run lean.
		var neck_model := Quaternion(Vector3.UP, _turn_sway * .22) * Quaternion(Vector3.BACK, _strafe_blend * .030) * Quaternion(Vector3.RIGHT, -forward_lean * .75)
		_rotate_bone_model_space(neck_idx, neck_model)


func _rotate_bone_model_space(bone: int, model_q: Quaternion) -> void:
	var g_q := skeleton.get_bone_global_pose(bone).basis.get_rotation_quaternion()
	var local_q := skeleton.get_bone_pose_rotation(bone)
	skeleton.set_bone_pose_rotation(bone, (local_q * g_q.inverse() * model_q * g_q).normalized())


func set_combat_pose(flash_timer: float, air_active: bool, charge_ratio: float = 0.0) -> void:
	_kick = clampf(flash_timer / .14, 0, 1) * .055
	_air_active = air_active
	_charge_ratio = clampf(charge_ratio, 0, 1)


func muzzle_position(index: int) -> Vector3:
	return (_prop_sockets[TOOL_IDS[clampi(index,1,4)-1]]["Emitter"] as Node3D).global_position


func _fit_equipment() -> void:
	if held_tool == null: return
	# Apply upper-body recoil/bellows/charge brace before solving arm grips.
	var recoil := _kick if tool_index == 2 else 0.0
	var pump_wave := sin(idle_phase * 15.0 + walk_phase * 2.0) if (tool_index == 3 and _air_active) else 0.0
	if recoil > .001 or (tool_index == 3 and _air_active) or _charge_ratio > .01:
		var torso_pitch := recoil * 1.65 - (.05 - .028 * pump_wave) * (1.0 if (tool_index == 3 and _air_active) else 0.0) - .04 * _charge_ratio
		var torso_yaw := -recoil * .45
		var spine_idx: int = _bones.get("spine", -1)
		var chest_idx: int = _bones.get("chest", -1)
		if spine_idx >= 0:
			_rotate_bone_model_space(spine_idx, Quaternion(Vector3.RIGHT, torso_pitch * .45) * Quaternion(Vector3.UP, torso_yaw * .4))
		if chest_idx >= 0:
			_rotate_bone_model_space(chest_idx, Quaternion(Vector3.RIGHT, torso_pitch * .55) * Quaternion(Vector3.UP, torso_yaw * .6))

	# Preserve animated torso/legs, overlay the authored arm pose, then fit each
	# hand to its actual equipment grip using a single-pass two-bone solve.
	for bone: int in _holds[tool_index - 1]:
		skeleton.set_bone_pose_rotation(bone, _holds[tool_index - 1][bone])

	var root_bone: int = _bones.get("root", 0)
	var bob := skeleton.get_bone_pose_position(root_bone).y
	var breath := sin(idle_phase * 2.2) * .005 * (1.0 - stride_blend)
	var step_dip := cos(walk_phase * 2.0) * .009 * stride_blend - _equip_dip * .028 - _stop_settle * .014
	var sway_x := sin(walk_phase) * .011 * stride_blend - _strafe_blend * .014 - _turn_sway * .045
	var surge_z := recoil + (.020 * pump_wave if (tool_index == 3 and _air_active) else 0.0) - _forward_blend * .010
	var lift_y := recoil * .28 + (absf(pump_wave) * .012 if (tool_index == 3 and _air_active) else 0.0)
	held_tool.position = MOUNTS[tool_index - 1] + Vector3(sway_x, bob + breath + step_dip + lift_y, surge_z)
	var pitch_x := -recoil * 1.45 + (.065 * pump_wave if (tool_index == 3 and _air_active) else 0.0) - _forward_blend * .022 + _equip_dip * .08
	var yaw_y := -_turn_sway * .14 + cos(walk_phase) * .016 * stride_blend
	var roll_z := -_strafe_blend * .028 - _turn_sway * .10
	held_tool.rotation = Vector3(pitch_x, yaw_y, roll_z)

	var skel_inv := skeleton.global_transform.affine_inverse()
	for side in ["R", "L"]:
		var socket: Node3D = _prop_sockets[tool_id][side]
		var raw := skel_inv * socket.global_transform
		var target := Transform3D(raw.basis.orthonormalized(), raw.origin)
		_solve_arm(side, target * (_sockets[side] as Transform3D).affine_inverse())
	skeleton.force_update_all_bone_transforms()
	force_update_count += 1


func _solve_arm(side: String, target: Transform3D) -> void:
	var upper: int = _bones["upper_arm." + side]
	var lower: int = _bones["forearm." + side]
	var hand: int = _bones["hand." + side]
	var upper_pose := skeleton.get_bone_global_pose(upper)
	var lower_pose := skeleton.get_bone_global_pose(lower)
	var hand_pose := skeleton.get_bone_global_pose(hand)
	var shoulder := upper_pose.origin
	var elbow := lower_pose.origin
	var wrist := hand_pose.origin
	var a := shoulder.distance_to(elbow)
	var b := elbow.distance_to(wrist)
	var delta := target.origin - shoulder
	var distance := clampf(delta.length(), absf(a - b) + .001, a + b - .001)
	var axis := delta / maxf(delta.length(), .0001)
	var bend := elbow - shoulder
	bend -= axis * bend.dot(axis)
	if bend.length_squared() < .0001: bend = axis.cross(Vector3.FORWARD)
	if bend.length_squared() < .0001: bend = axis.cross(Vector3.UP)
	var along := (a * a + distance * distance - b * b) / (2.0 * distance)
	var joint := shoulder + axis * along + bend.normalized() * sqrt(maxf(0.0, a * a - along * along))

	var from_upper := elbow - shoulder
	var to_upper := joint - shoulder
	var upper_global_basis := upper_pose.basis
	var turn_upper := Quaternion.IDENTITY
	if from_upper.length_squared() >= .0001 and to_upper.length_squared() >= .0001:
		turn_upper = Quaternion(from_upper.normalized(), to_upper.normalized())
		upper_global_basis = Basis(turn_upper) * upper_pose.basis
	var upper_parent: int = _bone_parents.get(upper, -1)
	var upper_parent_basis := skeleton.get_bone_global_pose(upper_parent).basis if upper_parent >= 0 else Basis.IDENTITY
	skeleton.set_bone_pose_rotation(upper, (upper_parent_basis.inverse() * upper_global_basis).get_rotation_quaternion())

	var lower_mid_basis := Basis(turn_upper) * lower_pose.basis
	var wrist_mid := joint + Basis(turn_upper) * (wrist - elbow)
	var from_lower := wrist_mid - joint
	var to_lower := (shoulder + axis * distance) - joint
	var lower_global_basis := lower_mid_basis
	if from_lower.length_squared() >= .0001 and to_lower.length_squared() >= .0001:
		var turn_lower := Quaternion(from_lower.normalized(), to_lower.normalized())
		lower_global_basis = Basis(turn_lower) * lower_mid_basis
	skeleton.set_bone_pose_rotation(lower, (upper_global_basis.inverse() * lower_global_basis).get_rotation_quaternion())
	skeleton.set_bone_pose_rotation(hand, (lower_global_basis.inverse() * target.basis.orthonormalized()).get_rotation_quaternion())


func grip_error(side: String) -> float:
	var bone: int = _bones["hand." + side]
	var hand := skeleton.global_transform * skeleton.get_bone_global_pose(bone) * (_sockets[side] as Transform3D)
	var grip: Node3D = _prop_sockets[tool_id][side]
	return hand.origin.distance_to(grip.global_position)
