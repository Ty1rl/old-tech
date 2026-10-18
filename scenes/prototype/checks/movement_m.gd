extends SceneTree

const ScrubView = preload("res://scenes/prototype/scrub_view.gd")
const Tuning = preload("res://scenes/prototype/tuning.gd")
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)


func bone_pose(visual: Node3D, bone: String) -> Transform3D:
	return visual.skeleton.get_bone_global_pose(visual.skeleton.find_bone(bone))


func run() -> void:
	var arena: Node3D = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	root.get_node("GameState").resume()
	arena.set_physics_process(false)

	var player: CharacterBody3D = arena.player
	var visual: Node3D = player.visual
	var cam: Camera3D = player.camera

	# 1. Verify gameplay perspective camera contract and manual world-time animation.
	expect(cam.projection == Camera3D.PROJECTION_PERSPECTIVE and is_equal_approx(cam.fov, float(Tuning.VIEW.fov)),
		"Arena uses gameplay perspective camera")
	expect(not visual.is_processing() and not visual.is_physics_processing()
		and visual.animation.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL,
		"Player visual runs exclusively on manual world-time clock")

	# 2. Verify Walk <-> Run phase synchronization and hysteresis.
	player.reset_state()
	for tick in range(7):
		visual.step_visual(0.05, 3.2, 6.0, Vector3(0, 0, -3.2))
	expect(visual.animation.current_animation == "Walk", "Moderate forward speed selects Walk")
	var walk_norm_phase := fposmod(visual.animation.current_animation_position / visual.animation.current_animation_length, 1.0)
	visual.step_visual(0.02, 5.8, 6.0, Vector3(0, 0, -5.8))
	expect(visual.animation.current_animation == "Run", "Accelerating to full speed transitions to Run")
	var run_norm_phase := fposmod(visual.animation.current_animation_position / visual.animation.current_animation_length, 1.0)
	var phase_diff := absf(walk_norm_phase - run_norm_phase)
	phase_diff = minf(phase_diff, 1.0 - phase_diff)
	expect(phase_diff < 0.12, "Walk->Run transition preserves normalized leg phase (diff %.4f)" % phase_diff)

	# Hysteresis band (between 3.55 and 3.95 m/s) keeps Run without clip chatter.
	visual.step_visual(0.04, 3.7, 6.0, Vector3(0, 0, -3.7))
	expect(visual.animation.current_animation == "Run", "Hysteresis prevents Walk/Run chatter at 3.7 m/s")

	# 3. Verify braking/stopping transition settles smoothly rather than snapping in 1 frame.
	for tick in range(6):
		visual.step_visual(0.04, 6.0, 6.0, Vector3(0, 0, -6.0))
	var run_root_y: float = visual.skeleton.get_bone_pose_position(visual.skeleton.find_bone("root")).y
	visual.step_visual(0.03, 0.0, 6.0, Vector3.ZERO)
	var stop_frame1_root_y: float = visual.skeleton.get_bone_pose_position(visual.skeleton.find_bone("root")).y
	expect(visual._stop_settle > 0.2 and visual.stride_blend > 0.2,
		"Stopping from full run triggers braking settle instead of instant zeroing")
	expect(absf(stop_frame1_root_y) > 0.008 and absf(run_root_y) < 0.065,
		"Stopping frame retains settled crouch while damping pogo bounce")
	for tick in range(12):
		visual.step_visual(0.04, 0.0, 6.0, Vector3.ZERO)
	expect(visual.stride_blend < 0.02 and visual._stop_settle < 0.05 and visual.foot_plant.contacts.is_empty(),
		"Braking settle decays cleanly to Idle and releases foot plant")

	# 4. Verify turning follow-through while moving and aiming.
	player.reset_state()
	player.model.rotation.y = 0.0
	visual.step_visual(0.04, 5.0, 6.0, Vector3(0, 0, -5.0))
	player.model.rotation.y = 0.45
	visual.step_visual(0.04, 5.0, 6.0, Vector3(0, 0, -5.0))
	expect(absf(visual._turn_sway) > 0.02, "Sharp facing turn induces upper-body/equipment rotational follow-through")
	expect(visual.grip_error("L") < 0.025 and visual.grip_error("R") < 0.025,
		"Hands remain locked to weapon grips during sharp turn")

	# 5. Verify sideways strafing steers pelvis while counter-twisting torso and preserving forward emitter.
	player.reset_state()
	for tick in range(8):
		visual.step_visual(0.04, 5.6, 6.0, Vector3(0, 0, -5.6))
	var fwd_pelvis_yaw := bone_pose(visual, "pelvis").basis.get_euler().y
	for tick in range(8):
		visual.step_visual(0.04, 5.6, 6.0, Vector3(5.6, 0, 0))
	var right_pelvis_yaw := bone_pose(visual, "pelvis").basis.get_euler().y
	for tick in range(10):
		visual.step_visual(0.04, 5.6, 6.0, Vector3(-5.6, 0, 0))
	var left_pelvis_yaw := bone_pose(visual, "pelvis").basis.get_euler().y
	expect(absf(right_pelvis_yaw - fwd_pelvis_yaw) > 0.08 and absf(left_pelvis_yaw - right_pelvis_yaw) > 0.16,
		"Left and right strafes steer pelvis in opposite directions")
	var emitter: Node3D = visual.tool_attachments[visual.tool_id].find_child("Emitter", true, false)
	expect(emitter.global_position.z < player.global_position.z, "Counter-twisted torso keeps emitter aimed forward during strafe")

	# 6. Verify combat recoil kick and active bellows heave across all 4 tools.
	player.reset_state()
	player.set_visual_tool(2)
	visual.set_combat_pose(0.0, false, 0.0)
	visual.step_visual(0.04, 0.0, 6.0, Vector3.ZERO)
	var neutral_chest_q := bone_pose(visual, "chest").basis.get_rotation_quaternion()
	var neutral_tool_z: float = visual.held_tool.position.z
	visual.set_combat_pose(0.14, false, 0.0)
	visual.step_visual(0.04, 0.0, 6.0, Vector3.ZERO)
	var recoil_chest_q := bone_pose(visual, "chest").basis.get_rotation_quaternion()
	var recoil_tool_z: float = visual.held_tool.position.z
	expect(recoil_tool_z > neutral_tool_z + 0.05 and neutral_chest_q.angle_to(recoil_chest_q) > 0.03,
		"Flash recoil kicks weapon back and rocks chest/spine")
	expect(visual.grip_error("L") < 0.025 and visual.grip_error("R") < 0.025,
		"Hands track Flash Camera handles through peak recoil")

	player.set_visual_tool(3)
	visual.set_combat_pose(0.0, true, 0.0)
	visual.step_visual(0.04, 3.5, 6.0, Vector3(0, 0, -3.5))
	var cone_pos_a: Vector3 = visual.held_tool.position
	visual.step_visual(0.10, 3.5, 6.0, Vector3(0, 0, -3.5))
	var cone_pos_b: Vector3 = visual.held_tool.position
	expect(cone_pos_a.distance_to(cone_pos_b) > 0.004 and visual.grip_error("L") < 0.025 and visual.grip_error("R") < 0.025,
		"Active Heat Bellows pumps visibly while preserving exact two-hand grip")
	visual.set_combat_pose(0.0, false, 0.0)

	# 7. Verify slow-time (0.18x) and normal-time movement ratio & rewind freeze.
	player.reset_state()
	var slow_start: float = visual.walk_phase
	for tick in range(10):
		visual.step_visual(0.04 * float(arena.time_controller.settings.slow_scale), 6.0, 6.0, Vector3(0, 0, -6.0))
	var slow_delta: float = visual.walk_phase - slow_start
	var norm_start: float = visual.walk_phase
	for tick in range(10):
		visual.step_visual(0.04, 6.0, 6.0, Vector3(0, 0, -6.0))
	var norm_delta: float = visual.walk_phase - norm_start
	expect(absf(slow_delta / norm_delta - float(arena.time_controller.settings.slow_scale)) < 0.01,
		"Slow-time gait phase scales by exact world_scale ratio")

	var scrub := ScrubView.new()
	var from_pose: Dictionary = scrub.capture_pose(player, arena.director, arena.weapons)
	player.position += Vector3(2.5, 0, -1.5)
	var frozen_phase: float = visual.walk_phase
	var frozen_shin := bone_pose(visual, "shin.L")
	scrub.begin(from_pose, player, arena.director, arena.weapons)
	scrub.step(ScrubView.DURATION * 0.5)
	expect(is_equal_approx(visual.walk_phase, frozen_phase) and bone_pose(visual, "shin.L").is_equal_approx(frozen_shin),
		"Rewind scrub freezes gait phase and bone poses")
	scrub.finish()

	# 8. Round N Wave 1: Bounded joint/foot regression across walk, run, turn, backward, strafe, and slow.
	# Verifies the flying-leg regression (foot.y ~ 1.68 m, knee.y ~ 1.31 m in 2809608) is completely eliminated
	# and that thigh/shin/foot rotations match the authored AnimationPlayer clips with zero procedural distortion.
	var skel: Skeleton3D = visual.skeleton
	var foot_l := skel.find_bone("foot.L")
	var foot_r := skel.find_bone("foot.R")
	var shin_l := skel.find_bone("shin.L")
	var shin_r := skel.find_bone("shin.R")
	var thigh_l := skel.find_bone("thigh.L")
	var thigh_r := skel.find_bone("thigh.R")
	var pelvis_b := skel.find_bone("pelvis")

	var regimes := [
		{"name": "walk", "vel": Vector3(0, 0, -3.0), "dt": 0.04, "yaw_step": 0.0},
		{"name": "run", "vel": Vector3(0, 0, -6.0), "dt": 0.04, "yaw_step": 0.0},
		{"name": "turn", "vel": Vector3(2.5, 0, -4.5), "dt": 0.04, "yaw_step": deg_to_rad(4.8)},
		{"name": "backward", "vel": Vector3(0, 0, 4.5), "dt": 0.04, "yaw_step": 0.0},
		{"name": "strafe", "vel": Vector3(5.5, 0, 0), "dt": 0.04, "yaw_step": 0.0},
		{"name": "slow", "vel": Vector3(0, 0, -6.0), "dt": 0.04 * float(arena.time_controller.settings.slow_scale), "yaw_step": 0.0},
	]
	for reg: Dictionary in regimes:
		player.reset_state()
		var min_fy := 999.0
		var max_fy := -999.0
		var max_ky := -999.0
		var min_hy := 999.0
		var max_step_jump := 0.0
		var prev_fl := Vector3.ZERO
		var prev_fr := Vector3.ZERO
		var hierarchy_valid := true
		for step_i in range(40):
			var dt: float = reg["dt"]
			var v: Vector3 = reg["vel"]
			player.model.rotation.y += float(reg["yaw_step"])
			player.position += (player.model.global_basis * v) * dt
			visual.step_visual(dt, v.length(), 6.0, v)
			var fl := skel.get_bone_global_pose(foot_l).origin
			var fr := skel.get_bone_global_pose(foot_r).origin
			var kl := skel.get_bone_global_pose(shin_l).origin
			var kr := skel.get_bone_global_pose(shin_r).origin
			var hp := skel.get_bone_global_pose(pelvis_b).origin
			min_fy = minf(min_fy, minf(fl.y, fr.y))
			max_fy = maxf(max_fy, maxf(fl.y, fr.y))
			max_ky = maxf(max_ky, maxf(kl.y, kr.y))
			min_hy = minf(min_hy, hp.y)
			if not (fl.y + 0.18 < kl.y and kl.y + 0.15 < hp.y and fr.y + 0.18 < kr.y and kr.y + 0.15 < hp.y):
				hierarchy_valid = false
			if step_i > 0:
				max_step_jump = maxf(max_step_jump, maxf(fl.distance_to(prev_fl), fr.distance_to(prev_fr)))
			prev_fl = fl
			prev_fr = fr
		expect(hierarchy_valid and min_fy >= 0.14 and max_fy <= 0.36 and max_ky <= 0.70 and max_step_jump <= 0.19,
			"Regime '%s' keeps feet grounded and bounded below knees/hips (foot_y=[%.3f..%.3f], max_knee_y=%.3f, max_jump=%.3f)" % [
				reg["name"], min_fy, max_fy, max_ky, max_step_jump
			])

	# Verify leg bone local rotations match authored AnimationPlayer clip evaluation with zero procedural distortion.
	player.reset_state()
	for tick in range(10):
		visual.step_visual(0.04, 6.0, 6.0, Vector3(0, 0, -6.0))
	var actual_leg_rots := [
		skel.get_bone_pose_rotation(thigh_l), skel.get_bone_pose_rotation(shin_l), skel.get_bone_pose_rotation(foot_l),
		skel.get_bone_pose_rotation(thigh_r), skel.get_bone_pose_rotation(shin_r), skel.get_bone_pose_rotation(foot_r),
	]
	skel.reset_bone_poses()
	visual.animation.advance(0)
	var authored_leg_rots := [
		skel.get_bone_pose_rotation(thigh_l), skel.get_bone_pose_rotation(shin_l), skel.get_bone_pose_rotation(foot_l),
		skel.get_bone_pose_rotation(thigh_r), skel.get_bone_pose_rotation(shin_r), skel.get_bone_pose_rotation(foot_r),
	]
	var max_leg_rot_diff := 0.0
	for b_i in range(actual_leg_rots.size()):
		max_leg_rot_diff = maxf(max_leg_rot_diff, (actual_leg_rots[b_i] as Quaternion).angle_to(authored_leg_rots[b_i] as Quaternion))
	expect(max_leg_rot_diff < 0.0001 and visual.foot_plant.contacts.is_empty(),
		"Thigh/shin/foot poses match authored AnimationPlayer clips with procedural planting disabled (rot diff %.6f rad)" % max_leg_rot_diff)

	# 9. Profile repeated animation work: verify single full-skeleton update per step and fast execution.
	player.reset_state()
	var t0 := Time.get_ticks_usec()
	var max_force_updates := 0
	for i in range(240):
		var tool_num := (i % 4) + 1
		if i % 60 == 0:
			player.set_visual_tool(tool_num)
		var dir := Vector3(sin(float(i) * 0.1), 0, -cos(float(i) * 0.1)).normalized() * 5.8
		visual.step_visual(1.0 / 60.0, dir.length(), 6.0, dir)
		max_force_updates = maxi(max_force_updates, visual.force_update_count)
	var elapsed_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	expect(max_force_updates <= 1,
		"Single full-skeleton transform rebuild per step (max %d per tick vs 15 baseline)" % max_force_updates)
	expect(elapsed_ms < 180.0, "240 varied gait+IK steps complete well within frame budget (%.2f ms)" % elapsed_ms)

	arena.feedback.reset_state()
	arena.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	# Let native compressed playback leave the mixer before process teardown.
	await create_timer(.3).timeout
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures, "profile_240_steps_ms": snappedf(elapsed_ms, 0.01), "max_force_updates_per_step": max_force_updates}))
	quit(0 if failures.is_empty() else 1)
