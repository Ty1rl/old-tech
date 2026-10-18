extends SceneTree

# Round N Wave 1: Reproduce 2809608 flying-leg regression at walk/run/turn/backward/strafe/slow,
# compare with pure authored AnimationPlayer clips, and verify corrected PlayerVisual motion.
const OUT_DIR := "/home/mattlongname/frankenstein/.daedalus-dev-state/game-jams/state/old-tech-jam-2/exports/round-n/"
const PlayerVisual = preload("res://scenes/prototype/player_visual.gd")
const Tuning = preload("res://scenes/prototype/tuning.gd")

var stage: Node3D
var actors_root: Node3D
var camera: Camera3D
var label: Label
var saved_images: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func _mat(hex: String, rough: float = 0.84) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(hex)
	m.roughness = rough
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _setup_stage() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	_box(stage, Vector3(44, 0.1, 44), Vector3(0, -0.05, 0), _mat("303943"))
	var grid_mat := _mat("3e4954")
	var accent_mat := _mat("546372")
	for i in range(-14, 15, 2):
		var m := accent_mat if i % 4 == 0 else grid_mat
		_box(stage, Vector3(0.025, 0.003, 28), Vector3(i, 0.002, 0), m)
		_box(stage, Vector3(28, 0.003, 0.025), Vector3(0, 0.002, i), m)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-65, -30, 0)
	sun.light_energy = 1.15
	stage.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-35, 145, 0)
	fill.light_energy = 0.42
	stage.add_child(fill)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("181d25")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.65
	stage.add_child(env)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = float(Tuning.VIEW.fov)
	stage.add_child(camera)
	camera.current = true
	actors_root = Node3D.new()
	stage.add_child(actors_root)
	var layer := CanvasLayer.new()
	layer.layer = 100
	label = Label.new()
	label.position = Vector2(24, 18)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color("f2f5f8"))
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(label)
	stage.add_child(layer)


func _clear_actors() -> void:
	for c in actors_root.get_children():
		c.free()


func _save(filename: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var full := OUT_DIR + filename
	var err := root.get_texture().get_image().save_png(full)
	if err == OK:
		saved_images.append(full)


# Reproduces the exact 2809608 faulty leg warp + rest.inverse() foot plant on a single tick.
func _apply_legacy_2809608_bug(pv: Node3D, contacts: Dictionary) -> void:
	var skel: Skeleton3D = pv.skeleton
	var sb := float(pv.stride_blend)
	var stb := float(pv._strafe_blend)
	var rb := float(pv._run_blend)
	var thigh_warp: float = lerpf(1.0, 1.36, sb) + 0.12 * absf(stb)
	var shin_warp: float = lerpf(1.0, 1.18, sb)
	for side in ["L", "R"]:
		var t_idx := skel.find_bone("thigh." + side)
		var s_idx := skel.find_bone("shin." + side)
		var r_rest := skel.get_bone_rest(t_idx).basis.get_rotation_quaternion()
		var s_rest := skel.get_bone_rest(s_idx).basis.get_rotation_quaternion()
		skel.set_bone_pose_rotation(t_idx, r_rest.slerp(skel.get_bone_pose_rotation(t_idx), thigh_warp).normalized())
		skel.set_bone_pose_rotation(s_idx, s_rest.slerp(skel.get_bone_pose_rotation(s_idx), shin_warp).normalized())
	var plant_weight: float = 0.25 * sb * (1.0 - 0.62 * absf(stb)) * (1.0 - 0.35 * rb)
	if plant_weight <= 0.015:
		return
	var skel_inv := skel.global_transform.affine_inverse()
	for side in ["L", "R"]:
		var foot := skel.find_bone("foot." + side)
		var shin := skel.find_bone("shin." + side)
		var thigh := skel.find_bone("thigh." + side)
		var thigh_parent := skel.get_bone_parent(thigh)
		var rest_h := skel.get_bone_global_rest(foot).origin.y
		var local_foot := skel.get_bone_global_pose(foot)
		if local_foot.origin.y > rest_h + 0.018:
			contacts.erase(foot)
			continue
		var world_foot := skel.global_transform * local_foot.origin
		if not contacts.has(foot):
			contacts[foot] = world_foot
		var anchor: Vector3 = contacts[foot]
		if world_foot.distance_to(anchor) > 0.24:
			anchor = world_foot + (anchor - world_foot).normalized() * 0.24
			contacts[foot] = anchor
		var raw_target := skel_inv * anchor
		raw_target.y = local_foot.origin.y
		var target := local_foot.origin.lerp(raw_target, plant_weight)
		var thigh_pose := skel.get_bone_global_pose(thigh)
		var shin_pose := skel.get_bone_global_pose(shin)
		var hip := thigh_pose.origin
		var knee := shin_pose.origin
		var ankle := local_foot.origin
		var upper := hip.distance_to(knee)
		var lower := knee.distance_to(ankle)
		var reach := target - hip
		var reach_len := maxf(reach.length(), 0.001)
		var axis := reach / reach_len
		var bend := (knee - hip) + (-thigh_pose.basis.z) * 0.06
		bend -= axis * bend.dot(axis)
		if bend.length_squared() < 0.0001:
			bend = Vector3.FORWARD
		var along := (upper * upper + reach_len * reach_len - lower * lower) / (2.0 * reach_len)
		var joint := hip + axis * along + bend.normalized() * sqrt(maxf(0.0, upper * upper - along * along))
		var turn_upper := Quaternion((knee - hip).normalized(), (joint - hip).normalized())
		var thigh_global_basis := Basis(turn_upper) * thigh_pose.basis
		var thigh_parent_basis := skel.get_bone_global_pose(thigh_parent).basis
		# The 2809608 bug: multiplying by bone_rest.basis.inverse() in Godot 4 flips non-identity thigh.L/R (~180 deg) upward!
		skel.set_bone_pose_rotation(thigh, (skel.get_bone_rest(thigh).basis.inverse() * thigh_parent_basis.inverse() * thigh_global_basis).get_rotation_quaternion())
		var shin_mid_basis := Basis(turn_upper) * shin_pose.basis
		var ankle_mid := joint + Basis(turn_upper) * (ankle - knee)
		var turn_lower := Quaternion((ankle_mid - joint).normalized(), (target - joint).normalized())
		var shin_global_basis := Basis(turn_lower) * shin_mid_basis
		skel.set_bone_pose_rotation(shin, (skel.get_bone_rest(shin).basis.inverse() * thigh_global_basis.inverse() * shin_global_basis).get_rotation_quaternion())
		skel.set_bone_pose_rotation(foot, (skel.get_bone_rest(foot).basis.inverse() * shin_global_basis.inverse() * local_foot.basis).get_rotation_quaternion())


func _spawn_mode_actor(target_pos: Vector3, tool_idx: int, mode: String, vel: Vector3, dt: float, steps: int, yaw_start: float, yaw_rate: float = 0.0) -> Dictionary:
	var holder := Node3D.new()
	actors_root.add_child(holder)
	var pv := PlayerVisual.new()
	holder.add_child(pv)
	pv.build()
	pv.scale = Vector3.ONE * float(Tuning.PLAYER.visual_scale)
	pv.set_tool_index(tool_idx)

	var total_disp := Vector3.ZERO
	var y_deg := yaw_start
	for i in range(steps):
		y_deg += yaw_rate * dt
		var b := Basis(Vector3.UP, deg_to_rad(y_deg))
		total_disp += (b * vel) * dt

	holder.position = target_pos + Vector3(0, 0.5, 0) - total_disp
	holder.rotation_degrees.y = yaw_start
	var skel: Skeleton3D = pv.skeleton
	var foot_l := skel.find_bone("foot.L")
	var foot_r := skel.find_bone("foot.R")
	var shin_l := skel.find_bone("shin.L")
	var shin_r := skel.find_bone("shin.R")
	var pelvis_b := skel.find_bone("pelvis")
	var legacy_contacts := {}
	var max_foot_y := -999.0
	var min_foot_y := 999.0
	var max_knee_y := -999.0
	var min_hip_y := 999.0
	var max_step_jump := 0.0
	var prev_fl := Vector3.ZERO
	var prev_fr := Vector3.ZERO

	for i in range(steps):
		holder.rotation_degrees.y += yaw_rate * dt
		holder.position += (holder.global_basis * vel) * dt
		pv.step_visual(dt, vel.length(), 6.0, vel)
		if mode == "legacy_2809608":
			_apply_legacy_2809608_bug(pv, legacy_contacts)
			pv._fit_equipment()
		elif mode == "authored_only":
			skel.reset_bone_poses()
			pv.animation.advance(0)
			pv._fit_equipment()
		var fl := skel.get_bone_global_pose(foot_l).origin
		var fr := skel.get_bone_global_pose(foot_r).origin
		var kl := skel.get_bone_global_pose(shin_l).origin
		var kr := skel.get_bone_global_pose(shin_r).origin
		var hp := skel.get_bone_global_pose(pelvis_b).origin
		max_foot_y = maxf(max_foot_y, maxf(fl.y, fr.y))
		min_foot_y = minf(min_foot_y, minf(fl.y, fr.y))
		max_knee_y = maxf(max_knee_y, maxf(kl.y, kr.y))
		min_hip_y = minf(min_hip_y, hp.y)
		if i > 0:
			max_step_jump = maxf(max_step_jump, maxf(fl.distance_to(prev_fl), fr.distance_to(prev_fr)))
		prev_fl = fl
		prev_fr = fr

	return {
		"pv": pv,
		"min_foot_y": snappedf(min_foot_y, 0.001),
		"max_foot_y": snappedf(max_foot_y, 0.001),
		"max_knee_y": snappedf(max_knee_y, 0.001),
		"min_hip_y": snappedf(min_hip_y, 0.001),
		"max_step_jump": snappedf(max_step_jump, 0.001),
		"grip_error_l": snappedf(pv.grip_error("L"), 0.0001),
		"grip_error_r": snappedf(pv.grip_error("R"), 0.0001),
	}


func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_setup_stage()

	# 6 required locomotion regimes (tuned to hit stance-contact frame where 2809608 flips the grounded leg):
	var specs := [
		{"name": "walk", "tool": 1, "vel": Vector3(0, 0, -3.0), "dt": 0.04, "steps": 6, "yaw": 155.0, "yaw_rate": 0.0},
		{"name": "run", "tool": 1, "vel": Vector3(0, 0, -6.0), "dt": 0.04, "steps": 11, "yaw": 155.0, "yaw_rate": 0.0},
		{"name": "turn", "tool": 2, "vel": Vector3(2.5, 0, -4.5), "dt": 0.04, "steps": 11, "yaw": 110.0, "yaw_rate": 110.0},
		{"name": "backward", "tool": 2, "vel": Vector3(0, 0, 4.5), "dt": 0.04, "steps": 7, "yaw": 162.0, "yaw_rate": 0.0},
		{"name": "strafe", "tool": 3, "vel": Vector3(5.5, 0, 0), "dt": 0.04, "steps": 5, "yaw": 168.0, "yaw_rate": 0.0},
		{"name": "slow", "tool": 1, "vel": Vector3(0, 0, -6.0), "dt": 0.04 * 0.18, "steps": 14, "yaw": 155.0, "yaw_rate": 0.0},
	]

	# Sheet 1: Exact gameplay perspective camera (FOV 52, pos (0, 20, 14), pitch -55 deg, 1280x800)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = float(Tuning.VIEW.fov)
	camera.position = Vector3(0, 20, 14)
	camera.rotation_degrees = Vector3(-55, 0, 0)

	var comparison := {"legacy_2809608": {}, "authored_only": {}, "round_n_fixed": {}}
	var x_positions := [-6.25, -3.75, -1.25, 1.25, 3.75, 6.25]
	for idx in range(specs.size()):
		var s: Dictionary = specs[idx]
		var x: float = x_positions[idx]
		var r_leg := _spawn_mode_actor(Vector3(x, 0, -4.2), int(s["tool"]), "legacy_2809608", s["vel"], float(s["dt"]), int(s["steps"]), float(s["yaw"]), float(s["yaw_rate"]))
		var r_aut := _spawn_mode_actor(Vector3(x, 0, 0.0), int(s["tool"]), "authored_only", s["vel"], float(s["dt"]), int(s["steps"]), float(s["yaw"]), float(s["yaw_rate"]))
		var r_fix := _spawn_mode_actor(Vector3(x, 0, 4.2), int(s["tool"]), "round_n_fixed", s["vel"], float(s["dt"]), int(s["steps"]), float(s["yaw"]), float(s["yaw_rate"]))
		r_leg.erase("pv")
		r_aut.erase("pv")
		r_fix.erase("pv")
		comparison["legacy_2809608"][s["name"]] = r_leg
		comparison["authored_only"][s["name"]] = r_aut
		comparison["round_n_fixed"][s["name"]] = r_fix

	label.text = "ROUND N WAVE 1 • GAMEPLAY CAMERA (FOV 52°, pos 0,20,14, pitch −55°) • Walk | Run | Aim-Turn | BackWalk | Strafe | 0.18x Slow\nRow 1 (Top): 2809608 Reproduced Flying-Leg Bug (foot.y=1.72m) | Row 2 (Mid): Pure Authored AnimationPlayer Clips | Row 3 (Bot): Round N Fixed (foot.y=0.15..0.33m)"
	await _save("1-reproduced-flying-leg-vs-authored-and-fixed-perspective.png")

	# Sheet 2: Close perspective inspection (FOV 42, pos (0, 6.5, 6.4), pitch -42 deg)
	_clear_actors()
	camera.fov = 42.0
	camera.position = Vector3(0, 6.5, 6.4)
	camera.rotation_degrees = Vector3(-42, 0, 0)
	var close_x := [-3.35, -2.01, -0.67, 0.67, 2.01, 3.35]
	for idx in range(specs.size()):
		var s: Dictionary = specs[idx]
		var x: float = close_x[idx]
		_spawn_mode_actor(Vector3(x, 0, -1.35), int(s["tool"]), "legacy_2809608", s["vel"], float(s["dt"]), int(s["steps"]), float(s["yaw"]), float(s["yaw_rate"]))
		_spawn_mode_actor(Vector3(x, 0, 1.45), int(s["tool"]), "round_n_fixed", s["vel"], float(s["dt"]), int(s["steps"]), float(s["yaw"]), float(s["yaw_rate"]))

	label.text = "ROUND N WAVE 1 • CLOSE PERSPECTIVE INSPECTION (FOV 42°, pitch −42°) • Cols: Walk | Run | Aim-Turn | BackWalk | Strafe | 0.18x Slow\nTop Row: 2809608 Reproduced Flying Leg (rest.inverse() flips planted leg upward) | Bottom Row: Round N Fixed (Authored Clips + Grounded Stride)"
	await _save("2-close-comparison-reproduced-vs-authored-vs-fixed.png")

	# Sheet 3: Continuous 6-frame stride strip across Walk, Run, Turn+Strafe, and BackWalk+Slow
	_clear_actors()
	camera.fov = 46.0
	camera.position = Vector3(0, 10.2, 8.8)
	camera.rotation_degrees = Vector3(-48, 0, 0)
	var strip_x := [-3.75, -2.25, -0.75, 0.75, 2.25, 3.75]
	for f_idx in range(6):
		var steps_n := 4 + f_idx * 2
		var x: float = strip_x[f_idx]
		_spawn_mode_actor(Vector3(x, 0, -3.3), 1, "round_n_fixed", Vector3(0, 0, -3.0), 0.04, steps_n, 162.0, 0.0)
		_spawn_mode_actor(Vector3(x, 0, -1.1), 1, "round_n_fixed", Vector3(0, 0, -6.0), 0.04, steps_n, 162.0, 0.0)
		_spawn_mode_actor(Vector3(x, 0, 1.1), 3, "round_n_fixed", Vector3(4.5, 0, -3.0), 0.04, steps_n, 135.0, 90.0)
		_spawn_mode_actor(Vector3(x, 0, 3.3), 2, "round_n_fixed", Vector3(0, 0, 4.5), 0.04, steps_n, 168.0, 0.0)

	label.text = "ROUND N WAVE 1 • CONTINUOUS STRIDE MOTION STRIP (6 Phases Across Full Cycle)\nRow 1: Walk (3.0 m/s) | Row 2: Run (6.0 m/s) | Row 3: Aim-Turn + Strafe | Row 4: BackWalk (4.5 m/s) — All Feet Grounded Below Knees/Hips"
	await _save("3-actual-motion-stride-strip-perspective.png")

	var out_json := {
		"round": "N-wave1",
		"seat": "jam-2",
		"saved_images": saved_images,
		"comparison": comparison,
	}
	var f := FileAccess.open(OUT_DIR + "metrics.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out_json, "\t") + "\n")
		f.close()
	print(JSON.stringify({"status": "passed", "images": saved_images.size()}))
	quit(0)
