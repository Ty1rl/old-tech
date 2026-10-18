extends SceneTree

# Round K actual-motion & attack-phase posture review at ortho 22 and close inspection.
const OUT_DIR := "/home/mattlongname/frankenstein/.daedalus-dev-state/game-jams/state/old-tech-jam-2/exports/round-k/"
const PlayerVisual = preload("res://scenes/prototype/player_visual.gd")
const CreatureVisual = preload("res://scenes/prototype/creature_visual.gd")
const ENEMY_KINDS: Array[StringName] = [&"blue", &"yellow", &"orange", &"front_guard", &"side_guard"]

var pass_tag := "pass1"
var stage: Node3D
var actors_root: Node3D
var camera: Camera3D
var label: Label
var saved_images: Array[String] = []
var metrics: Dictionary = {}


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pass="):
			pass_tag = arg.trim_prefix("--pass=")
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
	_box(stage, Vector3(44, 0.1, 44), Vector3(0, -0.05, 0), _mat("2d343a"))
	var grid_mat := _mat("3f4952")
	var accent_mat := _mat("566470")
	for i in range(-14, 15, 2):
		var m := accent_mat if i % 4 == 0 else grid_mat
		_box(stage, Vector3(0.025, 0.003, 28), Vector3(i, 0.002, 0), m)
		_box(stage, Vector3(28, 0.003, 0.025), Vector3(0, 0.002, i), m)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -32, 0)
	sun.light_energy = 1.18
	stage.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-35, 145, 0)
	fill.light_energy = 0.42
	stage.add_child(fill)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("1d2328")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("cfd8de")
	env.environment.ambient_light_energy = 0.68
	stage.add_child(env)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	stage.add_child(camera)
	camera.current = true
	actors_root = Node3D.new()
	stage.add_child(actors_root)
	var layer := CanvasLayer.new()
	layer.layer = 100
	label = Label.new()
	label.position = Vector2(24, 18)
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", Color("f0f4f8"))
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


func _spawn_player_sample(world_pos: Vector3, facing_yaw_deg: float, tool_idx: int, world_vel: Vector3, sim_duration: float, slow_scale: float = 1.0) -> Node3D:
	var holder := Node3D.new()
	holder.position = world_pos + Vector3(0, 0.5, 0)
	holder.rotation_degrees.y = facing_yaw_deg
	actors_root.add_child(holder)
	var pv := PlayerVisual.new()
	holder.add_child(pv)
	pv.build()
	pv.scale = Vector3.ONE * 1.3
	pv.set_tool_index(tool_idx)
	var local_move := holder.global_basis.inverse() * world_vel
	if slow_scale < 1.0:
		for w in range(6):
			pv.step_visual(0.04, local_move.length(), 6.0, local_move)
	var steps := maxi(1, int(round(sim_duration / 0.04)))
	var real_dt := sim_duration / float(steps)
	var world_dt := real_dt * slow_scale
	var start_pos := world_pos - world_vel * (sim_duration * slow_scale)
	holder.position = start_pos + Vector3(0, 0.5, 0)
	for s in range(steps):
		holder.position += world_vel * world_dt
		pv.step_visual(world_dt, local_move.length(), 6.0, local_move)
	return pv


func _spawn_enemy_sample(kind: StringName, world_pos: Vector3, facing_yaw_deg: float, speed: float, phase_name: StringName, staggered: bool, sim_duration: float) -> Node3D:
	var holder := Node3D.new()
	holder.position = world_pos
	holder.rotation_degrees.y = facing_yaw_deg
	actors_root.add_child(holder)
	var cv := CreatureVisual.new()
	holder.add_child(cv)
	cv.build(kind)
	var steps := maxi(1, int(round(sim_duration / 0.04)))
	var dt := sim_duration / float(steps)
	var move_vec := -holder.global_basis.z * (speed if phase_name == &"approach" and not staggered else 0.0)
	holder.position = world_pos - move_vec * sim_duration
	for s in range(steps):
		holder.position += move_vec * dt
		cv.step_visual(dt, speed, staggered, false, phase_name)
	return cv


func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_setup_stage()

	# 1. Ortho 22 gameplay camera: Player forward, backward, sideways strafe, and 0.18x slow motion across 4 stride phases.
	camera.position = Vector3(0, 20, 14)
	camera.rotation_degrees = Vector3(-55, 0, 0)
	camera.size = 22.0
	var lane_specs := [
		{"title": "Forward Run (6.0 m/s, 1.0x)", "z": -4.8, "vel": Vector3(0, 0, -6.0), "yaw": 155.0, "tool": 1, "slow": 1.0},
		{"title": "BackWalk Retreat (4.8 m/s, 1.0x)", "z": -1.6, "vel": Vector3(0, 0, 4.8), "yaw": 180.0, "tool": 2, "slow": 1.0},
		{"title": "Sideways Strafe Right (5.6 m/s, 1.0x)", "z": 1.6, "vel": Vector3(5.6, 0, 0), "yaw": 180.0, "tool": 3, "slow": 1.0},
		{"title": "Slow-Time Strafe/Run (6.0 m/s, 0.18x)", "z": 4.8, "vel": Vector3(4.2, 0, -4.2), "yaw": 180.0, "tool": 4, "slow": 0.18},
	]
	var player_samples: Array = []
	for row_idx in range(lane_specs.size()):
		var spec: Dictionary = lane_specs[row_idx]
		var yaw_deg: float = spec["yaw"]
		var local_v: Vector3 = spec["vel"]
		var z_row: float = spec["z"]
		var tool_num: int = spec["tool"]
		var slow_val: float = spec["slow"]
		for col in range(4):
			var x_pos := -5.4 + col * 3.6
			var sim_t := 0.18 + col * 0.18
			var world_vel: Vector3 = Basis(Vector3.UP, deg_to_rad(yaw_deg)) * local_v
			var pv := _spawn_player_sample(Vector3(x_pos, 0, z_row), yaw_deg, tool_num, world_vel, sim_t, slow_val)
			if col == 2:
				player_samples.append({
					"lane": spec["title"],
					"clip": pv.animation.current_animation,
					"cadence_hz": snappedf(pv.cadence_hz, 0.001),
					"playback_rate": snappedf(pv.playback_rate, 0.001),
					"grip_error_l": snappedf(pv.grip_error("L"), 0.0001),
					"grip_error_r": snappedf(pv.grip_error("R"), 0.0001),
				})
	label.text = "ROUND K (%s) • PLAYER ACTUAL MOTION AT ORTHO 22 (1280×800, pitch −55°)\nRows: 1) Forward Run 1.0x  2) BackWalk 1.0x  3) Sideways Strafe 1.0x (hip-steered)  4) Slow-Time 0.18x  |  Cols: 4 actual translating stride samples" % pass_tag.to_upper()
	await _save("%s-ortho22-player-motion.png" % pass_tag)

	# 2. Ortho 22 gameplay camera: All 5 enemies across Approach Walk, Windup Anticipation, Recovery, and Stun.
	_clear_actors()
	var enemy_metrics: Array = []
	var phases := [
		{"name": &"approach", "stagger": false, "speed": 2.0, "x": -6.0},
		{"name": &"windup", "stagger": false, "speed": 2.0, "x": -2.0},
		{"name": &"recover", "stagger": false, "speed": 1.6, "x": 2.0},
		{"name": &"stun", "stagger": true, "speed": 1.8, "x": 6.0},
	]
	for r in range(ENEMY_KINDS.size()):
		var kind: StringName = ENEMY_KINDS[r]
		var z_pos := -5.2 + r * 2.6
		for c in range(phases.size()):
			var p: Dictionary = phases[c]
			var px: float = p["x"]
			var pspeed: float = p["speed"]
			var pname: StringName = p["name"]
			var pstagger: bool = p["stagger"]
			var cv := _spawn_enemy_sample(kind, Vector3(px, 0, z_pos), 155.0, pspeed, pname, pstagger, 0.44)
			if r == 0 or c in [0, 1]:
				enemy_metrics.append({
					"kind": String(kind),
					"phase": String(p["name"]),
					"leg_cycling": cv.leg_cycling,
					"clip": cv.animation.current_animation,
					"cadence_hz": snappedf(cv.cadence_hz, 0.001),
				})
	label.text = "ROUND K (%s) • ENEMY STRIDE & ATTACK-PHASE POSTURES AT ORTHO 22 (1280×800, pitch −55°)\nCols: 1) Approach Walk (natural cadence, longer stride)  2) Windup (no leg-cycle, coiled anticipation)  3) Recover (no leg-cycle, forward slump)  4) Stun/Stagger" % pass_tag.to_upper()
	await _save("%s-ortho22-enemy-phases.png" % pass_tag)

	# 3. Closer inspection strip (ortho 7.4) to critique silhouette, hip steering, foot plant, and windup/recovery posture.
	_clear_actors()
	camera.position = Vector3(0, 7.6, 6.8)
	camera.rotation_degrees = Vector3(-44, 0, 0)
	camera.size = 7.4
	_spawn_player_sample(Vector3(-3.3, 0, -1.2), 160.0, 1, Basis(Vector3.UP, deg_to_rad(160.0)) * Vector3(0, 0, -6.0), 0.36, 1.0)
	_spawn_player_sample(Vector3(-1.1, 0, -1.2), 180.0, 2, Vector3(0, 0, 4.8), 0.36, 1.0)
	_spawn_player_sample(Vector3(1.1, 0, -1.2), 180.0, 3, Vector3(5.6, 0, 0), 0.36, 1.0)
	_spawn_player_sample(Vector3(3.3, 0, -1.2), 180.0, 4, Vector3(-5.6, 0, 0), 0.36 * 0.18, 0.18)

	_spawn_enemy_sample(&"blue", Vector3(-3.3, 0, 1.6), 160.0, 2.0, &"approach", false, 0.42)
	_spawn_enemy_sample(&"blue", Vector3(-1.1, 0, 1.6), 160.0, 2.0, &"windup", false, 0.42)
	_spawn_enemy_sample(&"front_guard", Vector3(1.1, 0, 1.6), 160.0, 2.0, &"windup", false, 0.42)
	_spawn_enemy_sample(&"side_guard", Vector3(3.3, 0, 1.6), 160.0, 1.8, &"recover", false, 0.42)
	label.text = "ROUND K (%s) • CLOSE GAIT & POSTURE INSPECTION (ortho 7.4)\nTop: Player Run, BackWalk, Strafe Right, Slow Strafe Left (0.18x)  |  Bottom: Conjoined Walk, Conjoined Windup, False Face Windup, Borrowed Heart Recover" % pass_tag.to_upper()
	await _save("%s-close-gait-and-windup.png" % pass_tag)

	metrics = {
		"pass": pass_tag,
		"saved_images": saved_images,
		"player_samples": player_samples,
		"enemy_samples": enemy_metrics,
	}
	var f := FileAccess.open(OUT_DIR + "%s-metrics.json" % pass_tag, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(metrics, "\t") + "\n")
		f.close()
	print(JSON.stringify({"status": "passed", "pass": pass_tag, "images": saved_images.size()}))
	quit(0)
