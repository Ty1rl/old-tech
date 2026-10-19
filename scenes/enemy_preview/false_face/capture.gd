extends SceneTree

# Isolated asset review only. No runtime arena/combat script is loaded.
const STATE := "/home/mattlongname/frankenstein/.daedalus-dev-state/game-jams/state/old-tech-jam-6/exports/round-j/"
var stage: Node3D
var model: Node3D
var camera: Camera3D
var skeleton: Skeleton3D
var player: AnimationPlayer
var meshes: Array[MeshInstance3D] = []
var label: Label
var checks := 0
var failures: Array[String] = []
var evidence: Dictionary = {}
var out: String


func _initialize() -> void:
	call_deferred("run")


func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr(message)


func collect(node: Node) -> void:
	if node is Skeleton3D: skeleton = node
	if node is AnimationPlayer: player = node
	if node is MeshInstance3D: meshes.append(node)
	for child in node.get_children(): collect(child)


func mat(color: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color)
	m.roughness = 0.85
	return m


func setup() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	floor_mesh.mesh = plane
	floor_mesh.material_override = mat("41494b")
	stage.add_child(floor_mesh)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("252d30")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("d6deea")
	env.environment.ambient_light_energy = 0.65
	stage.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52, -32, 0)
	light.light_energy = 1.2
	light.shadow_enabled = true
	stage.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, 155, 0)
	fill.light_energy = 0.65
	stage.add_child(fill)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	stage.add_child(camera)
	camera.current = true
	var canvas := CanvasLayer.new()
	label = Label.new()
	label.position = Vector2(24, 730)
	label.add_theme_font_size_override("font_size", 20)
	canvas.add_child(label)
	stage.add_child(canvas)


func pose(clip: String, time: float) -> void:
	player.play(clip)
	player.seek(time, true)
	player.advance(0)
	player.pause()
	skeleton.force_update_all_bone_transforms()


func bounds() -> Dictionary:
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	var bad := 0
	var vertices := 0
	for instance in meshes:
		for surface in range(instance.mesh.get_surface_count()):
			var arrays := instance.mesh.surface_get_arrays(surface)
			var vs: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var stride := bones.size() / vs.size()
			for i in range(vs.size()):
				var point := Vector3.ZERO
				var total := 0.0
				for k in range(stride):
					var w := weights[i * stride + k]
					if w <= 0.0: continue
					var bind := bones[i * stride + k]
					var bi := instance.skin.get_bind_bone(bind)
					if bi < 0:
						bi = skeleton.find_bone(instance.skin.get_bind_name(bind))
					point += (skeleton.global_transform * skeleton.get_bone_global_pose(bi) * instance.skin.get_bind_pose(bind) * vs[i]) * w
					total += w
				if absf(total - 1.0) > 0.001 or not point.is_finite(): bad += 1
				low = low.min(point)
				high = high.max(point)
				vertices += 1
	return {"low": [low.x, low.y, low.z], "high": [high.x, high.y, high.z], "bad_weights": bad, "vertices": vertices}


func shot(name: String, size: float, location: Vector3, target: Vector3, text: String) -> void:
	camera.size = size
	camera.position = location
	camera.look_at(target)
	label.text = text
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(out + name + ".png") == OK, "save " + name)


func run() -> void:
	var iteration: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://art-source/enemies/false_face/iteration.json"))
	out = STATE + "pass-%d/" % int(iteration["pass"])
	setup()
	var asset := load("res://assets/enemies/false_face/false_face.glb") as PackedScene
	expect(asset != null, "GLB loads")
	if asset == null:
		quit(1)
		return
	model = asset.instantiate()
	stage.add_child(model)
	collect(model)
	expect(skeleton != null, "deform skeleton imports")
	expect(player != null, "animation player imports")
	if skeleton == null or player == null:
		quit(1)
		return
	expect(skeleton.get_bone_count() == 18, "18 mechanism and deform bones")
	expect(meshes.size() == 8, "8 consolidated mesh objects")
	evidence["clips"] = player.get_animation_list()
	for clip in ["Idle", "Walk", "ShieldOpen"]:
		expect(player.has_animation(clip), "clip " + clip)
	if failures.size() > 0:
		print(JSON.stringify({"status":"failed", "checks":checks, "failures":failures, "evidence":evidence}))
		quit(1)
		return
	expect(player.get_animation("Idle").loop_mode == Animation.LOOP_LINEAR, "Idle imports as a loop")
	expect(player.get_animation("Walk").loop_mode == Animation.LOOP_LINEAR, "Walk imports as a loop")
	expect(player.get_animation("ShieldOpen").loop_mode == Animation.LOOP_NONE, "mechanism sample remains one-shot")
	var target_meshes := {}
	for name in ["Cable_Blue", "Shield_Orange", "Shield_Rim", "Core_Yellow"]:
		var found := model.find_child(name, true, false) as MeshInstance3D
		expect(found != null, name + " remains an independent mesh")
		if found != null: target_meshes[name] = found
	pose("Idle", 0)
	var rest := bounds()
	evidence["rest_bounds"] = rest
	expect(rest.bad_weights == 0, "normalized imported skin weights and finite vertices")
	expect(absf(rest.low[1]) < 0.04, "feet at ground")
	expect(rest.high[1] > 2.10 and rest.high[1] < 2.25, "human height in metres")
	expect(rest.low[2] < -0.90, "shield faces Godot -Z")
	var socket_data := {}
	for name in ["CoreSocket", "CableStart", "CableEnd", "ShieldPivot"]:
		var node := model.find_child(name, true, false) as Node3D
		expect(node != null, name + " imports")
		if node != null:
			var p := node.global_position
			socket_data[name] = [p.x, p.y, p.z]
			expect(p.is_finite() and p.y > 1.0 and p.y < 1.9, name + " is at the mechanism")
	evidence["sockets_godot"] = socket_data
	if socket_data.has("CoreSocket") and socket_data.has("CableStart"):
		expect(socket_data["CoreSocket"][1] - socket_data["CableStart"][1] > 0.25, "coupling clears the exposed yellow aperture")
	await shot("close-front", 3.5, Vector3(0, 2.3, -6), Vector3(0, 1.15, -0.20), "FALSE FACE / pass %d / front" % iteration["pass"])
	await shot("close-quarter", 3.8, Vector3(-4, 3.1, -5), Vector3(0, 1.1, -0.2), "FALSE FACE / three quarter / separate blue conduit, orange shield, yellow core")
	await shot("close-back", 3.5, Vector3(3, 2.5, 5), Vector3(0, 1.1, -0.1), "FALSE FACE / rear / hunched wrapped human silhouette")
	# Actual prescribed gameplay scale and pitch, without enlarging the model.
	var target := Vector3(0, 0.8, 0)
	var offset := Vector3(0, sin(deg_to_rad(55)), -cos(deg_to_rad(55))) * 20
	await shot("gameplay", 22, target + offset, target, "FALSE FACE / actual scale / ortho 22 / pitch -55 / 1280 x 800")
	var thigh := skeleton.find_bone("thigh.L")
	pose("Walk", 0.0)
	var before := skeleton.get_bone_global_pose(thigh)
	pose("Walk", 0.25)
	var after := skeleton.get_bone_global_pose(thigh)
	expect(not before.is_equal_approx(after), "Walk visibly deforms thigh")
	var walking := bounds()
	expect(walking.bad_weights == 0, "walking vertices finite with normalized weights")
	evidence["walk_bounds"] = walking
	await shot("walk", 3.8, Vector3(-4, 3.1, -5), Vector3(0, 1.1, -0.2), "FALSE FACE / in-place walk / deformed limbs")
	pose("ShieldOpen", 0.99)
	var opened := bounds()
	expect(opened.bad_weights == 0, "opened mechanism has finite weighted vertices")
	evidence["open_bounds"] = opened
	await shot("open", 3.8, Vector3(-3, 2.8, -6), Vector3(0, 1.1, -0.2), "FALSE FACE / shield displaced / exposed yellow core; preview timing only")
	if target_meshes.has("Cable_Blue"):
		target_meshes["Cable_Blue"].visible = false
		expect(target_meshes["Core_Yellow"].visible and target_meshes["Shield_Orange"].visible, "cut cable leaves other target parts independent")
		await shot("cut-open", 3.8, Vector3(-3, 2.8, -6), Vector3(0, 1.1, -0.2), "FALSE FACE / cut route demonstration / blue conduit hidden, yellow core available")
	var result := {"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures, "evidence": evidence}
	var f := FileAccess.open(out + "verification.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(result, "  "))
	print(JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
