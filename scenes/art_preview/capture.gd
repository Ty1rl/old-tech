extends SceneTree

# Round M gameplay-perspective motion, transition, strafe, grip, and recoil review.
const OUT_DIR := "/home/mattlongname/frankenstein/.daedalus-dev-state/game-jams/state/old-tech-jam-2/exports/round-m/"
const PlayerVisual = preload("res://scenes/prototype/player_visual.gd")
const Tuning = preload("res://scenes/prototype/tuning.gd")

var pass_tag := "pass1"
var stage: Node3D
var actors_root: Node3D
var camera: Camera3D
var label: Label
var saved_images: Array[String] = []


func _initialize() -> void:
	if FileAccess.file_exists(OUT_DIR + "pass_mode.txt"):
		var f := FileAccess.open(OUT_DIR + "pass_mode.txt", FileAccess.READ)
		if f:
			var t := f.get_as_text().strip_edges()
			if t != "":
				pass_tag = t
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
	fill.light_energy = 0.40
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
	label.add_theme_font_size_override("font_size", 17)
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


func _spawn_trajectory_sample(target_pos: Vector3, tool_idx: int, steps_spec: Array) -> Node3D:
	var holder := Node3D.new()
	actors_root.add_child(holder)
	var pv := PlayerVisual.new()
	holder.add_child(pv)
	pv.build()
	pv.scale = Vector3.ONE * float(Tuning.PLAYER.visual_scale)
	pv.set_tool_index(tool_idx)

	var total_disp := Vector3.ZERO
	for seg: Dictionary in steps_spec:
		var count: int = seg["count"]
		var dt: float = seg["dt"]
		var lvel: Vector3 = seg["vel"]
		var y_s: float = seg["yaw_start"]
		var y_e: float = seg.get("yaw_end", y_s)
		for i in range(count):
			var t := float(i + 1) / float(maxi(1, count))
			var b := Basis(Vector3.UP, deg_to_rad(lerpf(y_s, y_e, t)))
			total_disp += (b * lvel) * dt

	holder.position = target_pos + Vector3(0, 0.5, 0) - total_disp
	for seg: Dictionary in steps_spec:
		var count: int = seg["count"]
		var dt: float = seg["dt"]
		var local_move: Vector3 = seg["vel"]
		var yaw_start: float = seg["yaw_start"]
		var yaw_end: float = seg.get("yaw_end", yaw_start)
		var flash_t: float = seg.get("flash", 0.0)
		var air_on: bool = seg.get("air", false)
		var charge_r: float = seg.get("charge", 0.0)
		for i in range(count):
			var t := float(i + 1) / float(maxi(1, count))
			holder.rotation_degrees.y = lerpf(yaw_start, yaw_end, t)
			var world_vel := holder.global_basis * local_move
			holder.position += world_vel * dt
			pv.set_combat_pose(flash_t, air_on, charge_r)
			pv.step_visual(dt, local_move.length(), 6.0, local_move)
	return pv


func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_setup_stage()

	# 1. Exact gameplay PERSPECTIVE camera (FOV 52, pos (0, 20, 14), pitch -55 deg, 1280x800).
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = float(Tuning.VIEW.fov)
	camera.position = Vector3(0, 20, 14)
	camera.rotation_degrees = Vector3(-55, 0, 0)

	# Row 1 (z = -4.8): Accelerate -> Full Run -> Sharp 85 deg Aim Turn while Moving -> Braking Stop Settle
	_spawn_trajectory_sample(Vector3(-5.4, 0, -4.8), 1, [
		{"count": 5, "dt": 0.04, "vel": Vector3(0, 0, -4.2), "yaw_start": 160.0}
	])
	_spawn_trajectory_sample(Vector3(-1.8, 0, -4.8), 1, [
		{"count": 9, "dt": 0.04, "vel": Vector3(0, 0, -6.0), "yaw_start": 160.0}
	])
	_spawn_trajectory_sample(Vector3(1.8, 0, -4.8), 1, [
		{"count": 6, "dt": 0.04, "vel": Vector3(3.2, 0, -4.8), "yaw_start": 115.0, "yaw_end": 195.0}
	])
	_spawn_trajectory_sample(Vector3(5.4, 0, -4.8), 1, [
		{"count": 7, "dt": 0.04, "vel": Vector3(0, 0, -6.0), "yaw_start": 160.0},
		{"count": 2, "dt": 0.03, "vel": Vector3(0, 0, -0.1), "yaw_start": 160.0}
	])

	# Row 2 (z = -1.6): Sideways Strafe Right, Sideways Strafe Left, Diagonal Strafe-Run, Strafe Direction Reversal
	_spawn_trajectory_sample(Vector3(-5.4, 0, -1.6), 3, [
		{"count": 9, "dt": 0.04, "vel": Vector3(5.6, 0, 0), "yaw_start": 180.0}
	])
	_spawn_trajectory_sample(Vector3(-1.8, 0, -1.6), 3, [
		{"count": 9, "dt": 0.04, "vel": Vector3(-5.6, 0, 0), "yaw_start": 180.0}
	])
	_spawn_trajectory_sample(Vector3(1.8, 0, -1.6), 2, [
		{"count": 9, "dt": 0.04, "vel": Vector3(4.2, 0, -4.2), "yaw_start": 180.0}
	])
	_spawn_trajectory_sample(Vector3(5.4, 0, -1.6), 3, [
		{"count": 6, "dt": 0.04, "vel": Vector3(-5.6, 0, 0), "yaw_start": 180.0},
		{"count": 3, "dt": 0.04, "vel": Vector3(5.6, 0, 0), "yaw_start": 180.0}
	])

	# Row 3 (z = 1.6): Slow-Time (0.18x) Run, Slow-Time Strafe, Normal BackWalk, Slow-Time BackWalk
	_spawn_trajectory_sample(Vector3(-5.4, 0, 1.6), 4, [
		{"count": 6, "dt": 0.04, "vel": Vector3(0, 0, -6.0), "yaw_start": 160.0},
		{"count": 6, "dt": 0.04 * 0.18, "vel": Vector3(0, 0, -6.0), "yaw_start": 160.0}
	])
	_spawn_trajectory_sample(Vector3(-1.8, 0, 1.6), 4, [
		{"count": 6, "dt": 0.04, "vel": Vector3(5.5, 0, 0), "yaw_start": 180.0},
		{"count": 6, "dt": 0.04 * 0.18, "vel": Vector3(5.5, 0, 0), "yaw_start": 180.0}
	])
	_spawn_trajectory_sample(Vector3(1.8, 0, 1.6), 2, [
		{"count": 9, "dt": 0.04, "vel": Vector3(0, 0, 4.8), "yaw_start": 180.0}
	])
	_spawn_trajectory_sample(Vector3(5.4, 0, 1.6), 4, [
		{"count": 6, "dt": 0.04, "vel": Vector3(0, 0, 4.8), "yaw_start": 180.0},
		{"count": 6, "dt": 0.04 * 0.18, "vel": Vector3(0, 0, 4.8), "yaw_start": 180.0}
	])

	# Row 4 (z = 4.8): Combat Grip & Recoil across all 4 tools (Ring Stride, Flash Charge Brace, Flash Recoil Kick, Cone Bellows Heave)
	var pv_ring := _spawn_trajectory_sample(Vector3(-5.4, 0, 4.8), 1, [
		{"count": 8, "dt": 0.04, "vel": Vector3(0, 0, -5.8), "yaw_start": 160.0}
	])
	var pv_charge := _spawn_trajectory_sample(Vector3(-1.8, 0, 4.8), 2, [
		{"count": 8, "dt": 0.04, "vel": Vector3(3.2, 0, -2.0), "yaw_start": 175.0, "charge": 0.95}
	])
	var pv_recoil := _spawn_trajectory_sample(Vector3(1.8, 0, 4.8), 2, [
		{"count": 6, "dt": 0.04, "vel": Vector3(0, 0, -2.2), "yaw_start": 165.0, "flash": 0.135}
	])
	var pv_cone := _spawn_trajectory_sample(Vector3(5.4, 0, 4.8), 3, [
		{"count": 9, "dt": 0.04, "vel": Vector3(0, 0, -4.4), "yaw_start": 165.0, "air": true}
	])

	var force_updates: int = pv_ring.force_update_count
	var grip_summary := {
		"ring_run": [snappedf(pv_ring.grip_error("L"), 0.0001), snappedf(pv_ring.grip_error("R"), 0.0001)],
		"flash_charge": [snappedf(pv_charge.grip_error("L"), 0.0001), snappedf(pv_charge.grip_error("R"), 0.0001)],
		"flash_recoil": [snappedf(pv_recoil.grip_error("L"), 0.0001), snappedf(pv_recoil.grip_error("R"), 0.0001)],
		"cone_heave": [snappedf(pv_cone.grip_error("L"), 0.0001), snappedf(pv_cone.grip_error("R"), 0.0001)],
	}

	label.text = "ROUND M (%s) • GAMEPLAY PERSPECTIVE (FOV 52°, pos 0,20,14, pitch −55°, 1280×800)\nRow 1: Start -> Run -> Aim-Turn -> Brake Settle | Row 2: Strafe R/L/Diag/Reverse | Row 3: 0.18x Slow & BackWalk | Row 4: Ring / Flash Charge / Flash Recoil / Cone Heave" % pass_tag.to_upper()
	await _save("%s-perspective-gameplay-motion.png" % pass_tag)

	# 2. Closer perspective view (FOV 42, pos (0, 5.8, 5.4), pitch -42 deg) to inspect step articulation, hip steering, grip, and recoil.
	_clear_actors()
	camera.fov = 42.0
	camera.position = Vector3(0, 5.8, 5.4)
	camera.rotation_degrees = Vector3(-42, 0, 0)

	_spawn_trajectory_sample(Vector3(-2.35, 0, -1.2), 1, [
		{"count": 9, "dt": 0.04, "vel": Vector3(0, 0, -6.0), "yaw_start": 158.0}
	])
	_spawn_trajectory_sample(Vector3(-0.78, 0, -1.2), 3, [
		{"count": 9, "dt": 0.04, "vel": Vector3(5.6, 0, 0), "yaw_start": 180.0}
	])
	_spawn_trajectory_sample(Vector3(0.78, 0, -1.2), 1, [
		{"count": 7, "dt": 0.04, "vel": Vector3(0, 0, -6.0), "yaw_start": 160.0},
		{"count": 2, "dt": 0.03, "vel": Vector3(0, 0, -0.05), "yaw_start": 160.0}
	])
	_spawn_trajectory_sample(Vector3(2.35, 0, -1.2), 4, [
		{"count": 6, "dt": 0.04, "vel": Vector3(0, 0, 4.8), "yaw_start": 165.0},
		{"count": 6, "dt": 0.04 * 0.18, "vel": Vector3(0, 0, 4.8), "yaw_start": 165.0}
	])

	_spawn_trajectory_sample(Vector3(-2.35, 0, 1.4), 2, [
		{"count": 6, "dt": 0.04, "vel": Vector3(0, 0, 0.0), "yaw_start": 160.0, "charge": 1.0}
	])
	_spawn_trajectory_sample(Vector3(-0.78, 0, 1.4), 2, [
		{"count": 6, "dt": 0.04, "vel": Vector3(0, 0, 0.0), "yaw_start": 160.0, "flash": 0.14}
	])
	_spawn_trajectory_sample(Vector3(0.78, 0, 1.4), 3, [
		{"count": 9, "dt": 0.04, "vel": Vector3(0, 0, -3.8), "yaw_start": 165.0, "air": true}
	])
	_spawn_trajectory_sample(Vector3(2.35, 0, 1.4), 1, [
		{"count": 6, "dt": 0.04, "vel": Vector3(3.5, 0, -4.2), "yaw_start": 120.0, "yaw_end": 200.0}
	])

	label.text = "ROUND M (%s) • PERSPECTIVE CLOSE INSPECTION (FOV 42°, pitch −42°)\nTop: Run Stride, Strafe Right (hip-steered), Braking Stop Settle, 0.18x BackWalk | Bottom: Flash Charge Brace, Flash Recoil Kick, Cone Heave, Aim-Turn Follow-Through" % pass_tag.to_upper()
	await _save("%s-perspective-close-inspection.png" % pass_tag)

	var metrics := {
		"pass": pass_tag,
		"saved_images": saved_images,
		"force_update_count_per_step": force_updates,
		"grip_errors": grip_summary,
	}
	var f := FileAccess.open(OUT_DIR + "%s-metrics.json" % pass_tag, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(metrics, "\t") + "\n")
		f.close()
	print(JSON.stringify({"status": "passed", "pass": pass_tag, "images": saved_images.size()}))
	quit(0)
