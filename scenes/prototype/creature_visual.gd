extends Node3D

# Art adapter only. Enemy owns health, part queries and the world-time tick.
const FootPlant = preload("res://scenes/prototype/foot_plant.gd")
const MODELS := {
	&"blue": preload("res://assets/enemies/conjoined.glb"),
	&"yellow": preload("res://assets/enemies/patient.glb"),
	&"orange": preload("res://assets/enemies/bellows_belly.glb"),
	&"front_guard": preload("res://assets/enemies/false_face/false_face.glb"),
	&"side_guard": preload("res://assets/enemies/borrowed_heart/borrowed_heart.glb"),
}
const PART_NAMES := {
	&"blue": ["BlueConnector", "", ""],
	&"yellow": ["", "YellowCore", ""],
	&"orange": ["", "", "OrangePlate"],
	&"front_guard": ["Cable_Blue", "Core_Yellow", "Shield_Orange"],
	&"side_guard": ["CutConduit", "CoreTarget", "HeatCover"],
}


static func warmup(parent: Node) -> void:
	if DisplayServer.get_name() == "headless": return
	# Render each skin/material once off-screen at startup, rather than
	# compiling all five on the first mixed-pack frame. No gameplay nodes.
	var viewport := SubViewport.new()
	viewport.name = "CreatureShaderWarmup"
	viewport.size = Vector2i(64, 64)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	parent.add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var i := 0
	for packed: PackedScene in MODELS.values():
		var instance := packed.instantiate()
		stage.add_child(instance)
		instance.position.x = (i - 2) * 3.0
		for animation_player: AnimationPlayer in instance.find_children("*", "AnimationPlayer", true, false):
			animation_player.active = false
		i += 1
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(0, 7, 12)
	camera.look_at(Vector3(0, 1, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 19
	camera.current = true
	stage.add_child(DirectionalLight3D.new())
	parent.get_tree().create_timer(1.0).timeout.connect(viewport.queue_free)

var foot_plant := FootPlant.new()
var skeleton: Skeleton3D
var kind: StringName
var model: Node3D
var animation: AnimationPlayer
var cable: Node3D
var core: Node3D
var plate: Node3D
var shield_rim: Node3D
var phase := 0.0
var gait_phase := 0.0
var playback_rate := 1.0
var cadence_hz := 0.0
var leg_cycling := false
var attack_phase: StringName = &"approach"
var height := 2.5
var _meshes: Array[MeshInstance3D] = []
var _flash: StandardMaterial3D
var _body_groups: Array[Dictionary] = []
var _phase_blend := {
	"windup": 0.0,
	"recover": 0.0,
	"stagger": 0.0,
}


func build(p_kind: StringName) -> void:
	kind = p_kind
	model = MODELS[kind].instantiate()
	add_child(model)
	var names: Array = PART_NAMES[kind]
	if names[0] != "": cable = model.find_child(names[0], true, false)
	if names[1] != "": core = model.find_child(names[1], true, false)
	if names[2] != "": plate = model.find_child(names[2], true, false)
	if kind == &"front_guard": shield_rim = model.find_child("Shield_Rim", true, false)
	height = 2.75 if kind == &"side_guard" else 2.5
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	animation = model.find_children("*", "AnimationPlayer", true, false)[0]
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animation.play("Idle")
	animation.advance(0)
	_cache_body_groups()
	_flash = StandardMaterial3D.new()
	_flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash.albedo_color = Color(1, 1, 1, .45)
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh not in [cable, core, plate, shield_rim]: _meshes.append(mesh)
	set_process(false)
	set_physics_process(false)


func _cache_body_groups() -> void:
	_body_groups.clear()
	if skeleton == null:
		return
	for prefix in ["", "A.", "B."]:
		var tl := skeleton.find_bone(prefix + "thigh.L")
		var tr := skeleton.find_bone(prefix + "thigh.R")
		if tl < 0 or tr < 0:
			continue
		var arm_l := skeleton.find_bone(prefix + "upper_arm.L")
		if arm_l < 0:
			arm_l = skeleton.find_bone(prefix + "arm.L")
		var arm_r := skeleton.find_bone(prefix + "upper_arm.R")
		if arm_r < 0:
			arm_r = skeleton.find_bone(prefix + "arm.R")
		var pelvis := skeleton.find_bone(prefix + "pelvis")
		var pelvis_rest_pos := skeleton.get_bone_rest(pelvis).origin if pelvis >= 0 else Vector3.ZERO
		_body_groups.append({
			"prefix": prefix,
			"pelvis": pelvis,
			"pelvis_rest_pos": pelvis_rest_pos,
			"chest": skeleton.find_bone(prefix + "chest"),
			"head": skeleton.find_bone(prefix + "head"),
			"thigh_l": tl,
			"shin_l": skeleton.find_bone(prefix + "shin.L"),
			"foot_l": skeleton.find_bone(prefix + "foot.L"),
			"thigh_r": tr,
			"shin_r": skeleton.find_bone(prefix + "shin.R"),
			"foot_r": skeleton.find_bone(prefix + "foot.R"),
			"arm_l": arm_l,
			"forearm_l": skeleton.find_bone(prefix + "forearm.L"),
			"arm_r": arm_r,
			"forearm_r": skeleton.find_bone(prefix + "forearm.R"),
		})


func set_attack_phase(p_phase: StringName) -> void:
	attack_phase = p_phase


func sync(cut: bool, exposed: bool, broken: bool, _heat_ratio: float) -> void:
	if cable: cable.visible = not cut
	if core: core.visible = exposed and not broken
	if plate: plate.visible = not exposed
	if shield_rim: shield_rim.visible = not exposed


func _resolve_attack_phase(motion_state: Variant) -> StringName:
	if motion_state is StringName:
		return motion_state
	if motion_state is String and motion_state != "":
		return StringName(motion_state)
	if motion_state is Dictionary:
		if motion_state.has("attack_phase"):
			return StringName(motion_state["attack_phase"])
		if motion_state.has("phase"):
			return StringName(motion_state["phase"])
	var p := get_parent()
	if p != null and p.get_parent() != null:
		var host := p.get_parent()
		if "attack_phase" in host:
			return host.attack_phase
	return attack_phase


func step_visual(world_delta: float, speed: float, staggered: bool, hit_flash: bool, motion_state: Variant = null) -> void:
	if world_delta <= 0: return
	attack_phase = _resolve_attack_phase(motion_state)
	var held_in_action := staggered or attack_phase in [&"windup", &"recover", &"recovery", &"stun", &"stagger", &"hold"]
	leg_cycling = speed > 0.1 and not held_in_action
	var clip := "Walk" if leg_cycling else "Idle"
	if animation.current_animation != clip:
		animation.play(clip)
	var natural_speed := 1.45 if kind in [&"blue", &"yellow", &"orange"] else 1.55
	if leg_cycling:
		var speed_ratio := clampf(speed / natural_speed, 0.0, 1.8)
		playback_rate = clampf(0.68 + 0.44 * speed_ratio, 0.62, 1.42)
		cadence_hz = playback_rate
		gait_phase = fposmod(gait_phase + world_delta * cadence_hz, 1.0)
	else:
		playback_rate = 0.85 if not staggered else 0.35
		cadence_hz = 0.0
	phase += world_delta * playback_rate
	skeleton.reset_bone_poses()
	animation.advance(world_delta * playback_rate)

	var blend_step := clampf(world_delta * 10.0, 0.0, 1.0)
	_phase_blend["windup"] = lerpf(_phase_blend["windup"], 1.0 if (attack_phase == &"windup" and not staggered) else 0.0, blend_step)
	_phase_blend["recover"] = lerpf(_phase_blend["recover"], 1.0 if (attack_phase in [&"recover", &"recovery"] and not staggered) else 0.0, blend_step)
	_phase_blend["stagger"] = lerpf(_phase_blend["stagger"], 1.0 if (staggered or attack_phase in [&"stun", &"stagger"]) else 0.0, blend_step)

	_apply_motion_posture(speed)
	if not leg_cycling:
		foot_plant.reset()
	else:
		var plant_strength := clampf((1.45 - speed) * 0.20, 0.05, 0.22)
		foot_plant.apply(skeleton, plant_strength, 0.22)
	for mesh in _meshes:
		mesh.material_overlay = _flash if hit_flash else null


func _apply_motion_posture(speed: float) -> void:
	if skeleton == null or _body_groups.is_empty():
		return
	var is_shuffle_rig := kind in [&"blue", &"yellow", &"orange"]
	var thigh_warp := 2.05 if is_shuffle_rig else 1.38
	var shin_warp := 1.55 if is_shuffle_rig else 1.24
	var arm_warp := 1.50 if is_shuffle_rig else 1.20
	var move_weight := clampf(speed / 1.5, 0.0, 1.2) if leg_cycling else 0.0
	var windup_w: float = _phase_blend["windup"]
	var recover_w: float = _phase_blend["recover"]
	var stagger_w: float = _phase_blend["stagger"]

	for idx in _body_groups.size():
		var g: Dictionary = _body_groups[idx]
		var head: int = g["head"]
		var saved_head_global := skeleton.get_bone_global_pose(head) if (kind == &"front_guard" and head >= 0) else Transform3D.IDENTITY
		var phase_offset := 0.18 * float(idx)
		var cycle_angle := (gait_phase + phase_offset) * TAU
		var stride_wave := sin(cycle_angle)
		var bob_wave := cos(cycle_angle * 2.0)

		if leg_cycling:
			_scale_bone_delta(skeleton, g["thigh_l"], thigh_warp)
			_scale_bone_delta(skeleton, g["thigh_r"], thigh_warp)
			_scale_bone_delta(skeleton, g["shin_l"], shin_warp)
			_scale_bone_delta(skeleton, g["shin_r"], shin_warp)
			_scale_bone_delta(skeleton, g["arm_l"], arm_warp)
			_scale_bone_delta(skeleton, g["arm_r"], arm_warp)

		var pelvis: int = g["pelvis"]
		if pelvis >= 0:
			var rest_pos: Vector3 = g["pelvis_rest_pos"]
			var cur_pos := skeleton.get_bone_pose_position(pelvis)
			var damp_pos := rest_pos.lerp(cur_pos, 0.45)
			if leg_cycling:
				damp_pos.y += 0.020 * bob_wave * move_weight
				damp_pos.x += 0.028 * stride_wave * move_weight
			damp_pos.y -= 0.038 * windup_w + 0.025 * recover_w
			skeleton.set_bone_pose_position(pelvis, damp_pos)

			var pelvis_sway := Quaternion(Vector3.BACK, 0.06 * stride_wave * move_weight - 0.10 * stagger_w)
			var pelvis_yaw := Quaternion(Vector3.UP, 0.08 * stride_wave * move_weight + 0.10 * windup_w)
			var pelvis_pitch := Quaternion(Vector3.RIGHT, -0.04 * move_weight + 0.10 * windup_w - 0.08 * recover_w + 0.10 * stagger_w)
			_rotate_bone_model_space(skeleton, pelvis, pelvis_yaw * pelvis_sway * pelvis_pitch)

		var chest: int = g["chest"]
		if chest >= 0:
			var chest_roll := Quaternion(Vector3.BACK, -0.045 * stride_wave * move_weight + 0.15 * stagger_w)
			var chest_yaw := Quaternion(Vector3.UP, -0.07 * stride_wave * move_weight - 0.16 * windup_w + 0.08 * recover_w)
			var chest_pitch := Quaternion(Vector3.RIGHT, -0.06 * move_weight + 0.18 * windup_w - 0.22 * recover_w + 0.16 * stagger_w)
			var chest_rot := chest_yaw * chest_roll * chest_pitch
			_rotate_bone_model_space(skeleton, chest, chest_rot)
			if kind == &"front_guard" and head >= 0:
				var head_parent := skeleton.get_bone_parent(head)
				if head_parent >= 0:
					var local_head := skeleton.get_bone_global_pose(head_parent).affine_inverse() * saved_head_global
					skeleton.set_bone_pose_position(head, local_head.origin)
					skeleton.set_bone_pose_rotation(head, local_head.basis.get_rotation_quaternion().normalized())

		if windup_w > 0.01 or recover_w > 0.01 or stagger_w > 0.01:
			var arm_pitch := 0.52 * windup_w - 0.24 * recover_w + 0.18 * stagger_w
			var arm_spread := 0.24 * windup_w + 0.18 * stagger_w
			_rotate_bone_model_space(skeleton, g["arm_l"], Quaternion(Vector3.RIGHT, arm_pitch) * Quaternion(Vector3.BACK, -arm_spread))
			_rotate_bone_model_space(skeleton, g["arm_r"], Quaternion(Vector3.RIGHT, arm_pitch * 0.88) * Quaternion(Vector3.BACK, arm_spread))
			_rotate_bone_model_space(skeleton, g["forearm_l"], Quaternion(Vector3.RIGHT, 0.32 * windup_w - 0.16 * recover_w))
			_rotate_bone_model_space(skeleton, g["forearm_r"], Quaternion(Vector3.RIGHT, 0.32 * windup_w - 0.16 * recover_w))
	skeleton.force_update_all_bone_transforms()


static func _scale_bone_delta(skeleton: Skeleton3D, bone: int, scale_factor: float) -> void:
	if bone < 0:
		return
	var rest_q := skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
	var pose_q := skeleton.get_bone_pose_rotation(bone)
	var delta_q := rest_q.inverse() * pose_q
	if delta_q.w < 0.0:
		delta_q = -delta_q
	var angle := delta_q.get_angle()
	if angle > 0.0001 and angle < 2.8:
		var warped_q := rest_q * Quaternion(delta_q.get_axis().normalized(), angle * scale_factor)
		skeleton.set_bone_pose_rotation(bone, warped_q.normalized())


static func _rotate_bone_model_space(skeleton: Skeleton3D, bone: int, model_q: Quaternion) -> void:
	if bone < 0:
		return
	var g_q := skeleton.get_bone_global_pose(bone).basis.get_rotation_quaternion()
	var local_q := skeleton.get_bone_pose_rotation(bone)
	var next_q := local_q * g_q.inverse() * model_q * g_q
	skeleton.set_bone_pose_rotation(bone, next_q.normalized())

