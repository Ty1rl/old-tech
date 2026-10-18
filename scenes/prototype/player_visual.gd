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
# These grip positions keep both handles within reach of the exported rig.
const MOUNTS = [Vector3(.10, 1.36, -.02), Vector3(.265, 1.34, -.19),
	Vector3(-.04, 1.40, .02), Vector3(.145, 1.32, -.23)]

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
var _run_blend := 0.0
var _strafe_blend := 0.0
var _forward_blend := 0.0
var _holds: Array[Dictionary] = []
var _sockets: Dictionary = {}
var _prop_sockets: Dictionary = {}
var _bones: Dictionary = {}
var _rest_rot: Dictionary = {}
var _equipped_index := 0
var _kick := 0.0
var _air_active := false
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
			_rest_rot[b_idx] = skeleton.get_bone_rest(b_idx).basis.get_rotation_quaternion()
	for side in ["L", "R"]:
		for part in ["upper_arm", "forearm", "hand", "thigh", "shin", "foot"]:
			var id: String = part + "." + side
			var b_idx := skeleton.find_bone(id)
			_bones[id] = b_idx
			if b_idx >= 0:
				_rest_rot[b_idx] = skeleton.get_bone_rest(b_idx).basis.get_rotation_quaternion()
		var socket: Node3D = character.find_child("Grip_" + side, true, false)
		_sockets[side] = socket.transform
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
	_equipped_index = tool_index
	tool_id = TOOL_IDS[tool_index - 1]
	for id: StringName in tool_attachments:
		tool_attachments[id].visible = id == tool_id
	_fit_equipment()


func reset_pose() -> void:
	build()
	foot_plant.reset()
	walk_phase = 0
	idle_phase = 0
	stride_blend = 0
	cadence_hz = 0
	playback_rate = 1.0
	_run_blend = 0
	_strafe_blend = 0
	_forward_blend = 0
	_kick = 0
	_air_active = false
	animation.play("Idle")
	animation.seek(0, true)
	animation.advance(0)
	_fit_equipment()


func step_visual(world_delta: float, planar_speed: float, max_speed: float = 6.0, movement: Vector3 = Vector3.ZERO) -> void:
	build()
	if world_delta <= 0: return
	var dt := minf(world_delta, .25)
	var ratio := clampf(planar_speed / maxf(.001, max_speed), 0, 1)
	stride_blend = move_toward(stride_blend, ratio, dt * 8)
	var moving := stride_blend > .05 and planar_speed > .05
	var local_dir := Vector3(movement.x, 0, movement.z)
	if local_dir.length_squared() < .0001 and moving:
		local_dir = Vector3(0, 0, -planar_speed)
	var norm_dir := local_dir.normalized() if local_dir.length_squared() > .0001 else Vector3.FORWARD
	var backing := moving and norm_dir.z > .22
	var mostly_strafe := moving and absf(norm_dir.x) > .72 and absf(norm_dir.z) < .55
	var run_target := clampf((planar_speed - 3.2) / maxf(.5, max_speed - 3.2), 0, 1) if (moving and not backing and not mostly_strafe) else 0.0
	_run_blend = move_toward(_run_blend, run_target, dt * 6.0)
	_strafe_blend = move_toward(_strafe_blend, norm_dir.x * stride_blend if moving else 0.0, dt * 7.5)
	_forward_blend = move_toward(_forward_blend, -norm_dir.z * stride_blend if moving else 0.0, dt * 7.5)
	var clip := "Idle"
	if moving:
		clip = "BackWalk" if backing else ("Run" if (planar_speed > 3.8 and not mostly_strafe) else "Walk")
	if animation.current_animation != clip:
		animation.play(clip, .14)
	var cycle := animation.get_animation(clip).length
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
		_apply_gait_shaping()
		var plant_weight := .26 * stride_blend * (1.0 - .65 * absf(_strafe_blend)) * (1.0 - .35 * _run_blend)
		foot_plant.apply(skeleton, plant_weight, .24)
	else:
		idle_phase += dt
		foot_plant.reset()
	_fit_equipment()


func _apply_gait_shaping() -> void:
	var root_idx: int = _bones.get("root", -1)
	if root_idx >= 0:
		var root_pos := skeleton.get_bone_pose_position(root_idx)
		# Replace steep double-frequency pogo bounce with a settled crouch and modest step bob.
		var base_crouch := lerpf(-.018, -.042, _run_blend) * stride_blend
		var bob_damp := lerpf(.32, .40, _run_blend)
		root_pos.y = base_crouch + (root_pos.y - base_crouch) * bob_damp
		root_pos.x = root_pos.x * .55 + sin(walk_phase) * .022 * stride_blend - _strafe_blend * .024
		skeleton.set_bone_pose_position(root_idx, root_pos)
	# Amplify thigh/shin swing excursion so capped cadence covers longer apparent ground strides.
	var thigh_warp := lerpf(1.0, 1.32, stride_blend) + .12 * absf(_strafe_blend)
	var shin_warp := lerpf(1.0, 1.16, stride_blend)
	for side in ["L", "R"]:
		var thigh_idx: int = _bones.get("thigh." + side, -1)
		if thigh_idx >= 0:
			var r_rest: Quaternion = _rest_rot[thigh_idx]
			var r_cur := skeleton.get_bone_pose_rotation(thigh_idx)
			skeleton.set_bone_pose_rotation(thigh_idx, r_rest.slerp(r_cur, thigh_warp).normalized())
		var shin_idx: int = _bones.get("shin." + side, -1)
		if shin_idx >= 0:
			var s_rest: Quaternion = _rest_rot[shin_idx]
			var s_cur := skeleton.get_bone_pose_rotation(shin_idx)
			skeleton.set_bone_pose_rotation(shin_idx, s_rest.slerp(s_cur, shin_warp).normalized())
	# Steer pelvis into lateral strafe in model space while counter-twisting spine/chest so upper body stays aimed forward.
	var strafe_sign := -1.0 if _forward_blend < -.1 else 1.0
	var strafe_yaw := clampf(-_strafe_blend * strafe_sign * .44, -.42, .42)
	var step_sway := sin(walk_phase) * .042 * stride_blend
	var forward_lean := -_forward_blend * (.045 + .045 * _run_blend)
	var pelvis_idx: int = _bones.get("pelvis", -1)
	if pelvis_idx >= 0:
		var p_model := Quaternion(Vector3.UP, strafe_yaw) * Quaternion(Vector3.BACK, -_strafe_blend * .045 + step_sway) * Quaternion(Vector3.RIGHT, forward_lean * .55)
		_rotate_bone_model_space(pelvis_idx, p_model)
	var spine_idx: int = _bones.get("spine", -1)
	if spine_idx >= 0:
		var sp_model := Quaternion(Vector3.UP, -strafe_yaw * .55) * Quaternion(Vector3.BACK, -_strafe_blend * .03 - step_sway * .5) * Quaternion(Vector3.RIGHT, forward_lean * .65)
		_rotate_bone_model_space(spine_idx, sp_model)
	var chest_idx: int = _bones.get("chest", -1)
	if chest_idx >= 0:
		var ch_model := Quaternion(Vector3.UP, -strafe_yaw * .45) * Quaternion(Vector3.BACK, -_strafe_blend * .025 - step_sway * .4) * Quaternion(Vector3.RIGHT, forward_lean * .60)
		_rotate_bone_model_space(chest_idx, ch_model)
	skeleton.force_update_all_bone_transforms()


func _rotate_bone_model_space(bone: int, model_q: Quaternion) -> void:
	var g_q := skeleton.get_bone_global_pose(bone).basis.get_rotation_quaternion()
	var local_q := skeleton.get_bone_pose_rotation(bone)
	skeleton.set_bone_pose_rotation(bone, (local_q * g_q.inverse() * model_q * g_q).normalized())


func set_combat_pose(flash_timer: float, air_active: bool) -> void:
	_kick = clampf(flash_timer / .14, 0, 1) * .065
	_air_active = air_active


func muzzle_position(index: int) -> Vector3:
	return (_prop_sockets[TOOL_IDS[clampi(index,1,4)-1]]["Emitter"] as Node3D).global_position


func _fit_equipment() -> void:
	if held_tool == null: return
	# Preserve animated torso/legs, overlay the authored arm pose, then fit each
	# hand to its actual equipment grip using a bounded two-bone solve.
	for bone: int in _holds[tool_index - 1]:
		skeleton.set_bone_pose_rotation(bone, _holds[tool_index - 1][bone])
	skeleton.force_update_all_bone_transforms()
	var root_bone := skeleton.find_bone("root")
	var bob := skeleton.get_bone_pose_position(root_bone).y
	var recoil := _kick if tool_index == 2 else 0.0
	var flutter := sin(idle_phase * 28 + walk_phase) * .008 if tool_index == 3 and _air_active else 0.0
	held_tool.position = MOUNTS[tool_index - 1] + Vector3(0, bob + flutter, recoil)
	held_tool.rotation.x = -recoil * .4
	for side in ["R", "L"]:
		var socket: Node3D = _prop_sockets[tool_id][side]
		var target := skeleton.global_transform.affine_inverse() * socket.global_transform
		_solve_arm(side, target * (_sockets[side] as Transform3D).affine_inverse())


func _solve_arm(side: String, target: Transform3D) -> void:
	var upper: int = _bones["upper_arm." + side]
	var lower: int = _bones["forearm." + side]
	var hand: int = _bones["hand." + side]
	var shoulder := skeleton.get_bone_global_pose(upper).origin
	var elbow := skeleton.get_bone_global_pose(lower).origin
	var wrist := skeleton.get_bone_global_pose(hand).origin
	var a := shoulder.distance_to(elbow)
	var b := elbow.distance_to(wrist)
	var delta := target.origin - shoulder
	var distance := clampf(delta.length(), absf(a-b) + .001, a+b - .001)
	var axis := delta.normalized()
	var bend := elbow - shoulder
	bend -= axis * bend.dot(axis)
	if bend.length_squared() < .0001: bend = axis.cross(Vector3.FORWARD)
	if bend.length_squared() < .0001: bend = axis.cross(Vector3.UP)
	var along := (a*a + distance*distance - b*b) / (2*distance)
	var joint := shoulder + axis*along + bend.normalized()*sqrt(maxf(0, a*a - along*along))
	_point_bone(upper, elbow - shoulder, joint - shoulder)
	elbow = skeleton.get_bone_global_pose(lower).origin
	wrist = skeleton.get_bone_global_pose(hand).origin
	_point_bone(lower, wrist - elbow, shoulder + axis*distance - elbow)
	_set_bone_basis(hand, target.basis.orthonormalized())


func _point_bone(bone: int, from: Vector3, to: Vector3) -> void:
	if from.length_squared() < .0001 or to.length_squared() < .0001: return
	var turn := Quaternion(from.normalized(), to.normalized())
	_set_bone_basis(bone, Basis(turn) * skeleton.get_bone_global_pose(bone).basis)


func _set_bone_basis(bone: int, desired: Basis) -> void:
	var parent := skeleton.get_bone_parent(bone)
	var basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	skeleton.set_bone_pose_rotation(bone, (basis.inverse() * desired).get_rotation_quaternion())
	skeleton.force_update_all_bone_transforms()


func grip_error(side: String) -> float:
	var bone: int = _bones["hand." + side]
	var hand := skeleton.global_transform * skeleton.get_bone_global_pose(bone) * (_sockets[side] as Transform3D)
	var grip: Node3D = _prop_sockets[tool_id][side]
	return hand.origin.distance_to(grip.global_position)
