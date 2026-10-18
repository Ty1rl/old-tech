extends SceneTree

const OUT := "/home/mattlongname/frankenstein/.daedalus-dev-state/game-jams/state/old-tech-jam-5/exports/round-j/"
const KINDS := ["patient", "conjoined", "bellows_belly"]
const PARTS := {"patient": "YellowCore", "conjoined": "BlueConnector", "bellows_belly": "OrangePlate"}
var stage: Node3D
var camera: Camera3D
var label: Label
var models: Dictionary = {}
var reports: Dictionary = {}
var failures: Array[String] = []
var checks := 0
var images := 0


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func material(color: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color)
	m.roughness = 0.85
	return m


func setup() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var ground := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(60, 0.1, 60)
	ground.mesh = mesh
	ground.position.y = -0.05
	ground.material_override = material("384047")
	stage.add_child(ground)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-65, -30, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40
	stage.add_child(sun)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("232c32")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("ccd5da")
	world.environment.ambient_light_energy = 0.65
	stage.add_child(world)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	stage.add_child(camera)
	var layer := CanvasLayer.new()
	layer.layer = 100
	label = Label.new()
	label.position = Vector2(24, root.get_visible_rect().size.y - 65)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(label)
	stage.add_child(layer)


func pose(kind: String, clip: String, time: float) -> void:
	var info: Dictionary = models[kind]
	var player: AnimationPlayer = info.player
	player.play(clip)
	player.seek(time, true)
	player.advance(0)
	var skeleton: Skeleton3D = info.skeleton
	skeleton.force_update_all_bone_transforms()


func count_colors(img: Image) -> Dictionary:
	var found := {"patient": 0, "conjoined": 0, "bellows_belly": 0}
	# Sample every fourth pixel: only a visibility diagnostic, not an art score.
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var c := img.get_pixel(x, y)
			if c.r > 0.75 and c.g > 0.70 and c.b < 0.5:
				found.patient += 1
			if c.b > 0.65 and c.b > c.r * 1.8 and c.g < 0.8:
				found.conjoined += 1
			if c.r > 0.65 and c.g > 0.25 and c.g < 0.70 and c.b < 0.35:
				found.bellows_belly += 1
	return found


func capture(path: String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var error := image.save_png(OUT + path)
	if error == OK:
		images += 1
	else:
		failures.append("Cannot save " + path)
	return image


func bounds_at(kind: String, time: float) -> Dictionary:
	pose(kind, "Walk", time)
	var info: Dictionary = models[kind]
	var skeleton: Skeleton3D = info.skeleton
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for instance: MeshInstance3D in info.meshes:
		var palette: Array[Transform3D] = []
		if instance.skin:
			for bind in range(instance.skin.get_bind_count()):
				var bone := instance.skin.get_bind_bone(bind)
				if bone < 0:
					bone = skeleton.find_bone(instance.skin.get_bind_name(bind))
				palette.append(skeleton.global_transform * skeleton.get_bone_global_pose(bone) * instance.skin.get_bind_pose(bind))
		for surface in range(instance.mesh.get_surface_count()):
			var a := instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var weights: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS] if instance.skin else PackedFloat32Array()
			var bones: PackedInt32Array = a[Mesh.ARRAY_BONES] if instance.skin else PackedInt32Array()
			var n: int = weights.size() / vertices.size()
			for i in range(vertices.size()):
				var p := Vector3.ZERO
				if instance.skin:
					for j in range(n):
						if weights[i * n + j] > 0:
							p += (palette[bones[i * n + j]] * vertices[i]) * weights[i * n + j]
				else:
					p = instance.global_transform * vertices[i]
				low = low.min(p)
				high = high.max(p)
	return {"time": time, "min_m": [low.x, low.y, low.z], "max_m": [high.x, high.y, high.z]}


func inspect(kind: String) -> void:
	var model := (load("res://assets/enemies/" + kind + ".glb") as PackedScene).instantiate() as Node3D
	stage.add_child(model)
	var skeleton := model.find_child("*", false, false) as Skeleton3D
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	expect(skeletons.size() == 1 and players.size() == 1, kind + ": one skeleton and animation player")
	if skeletons.is_empty() or players.is_empty():
		return
	skeleton = skeletons[0]
	var player := players[0] as AnimationPlayer
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	var part := model.find_child(PARTS[kind], true, false) as Node3D
	models[kind] = {"model": model, "skeleton": skeleton, "player": player, "meshes": meshes, "part": part}
	var triangle_count := 0
	var materials: Dictionary = {}
	var normals_ok := true
	var weights_ok := true
	var body_skinned := true
	var marker_unlit := true
	for instance: MeshInstance3D in meshes:
		if str(instance.name).begins_with("A_") or str(instance.name).begins_with("B_"):
			body_skinned = body_skinned and instance.skin != null
		for surface in range(instance.mesh.get_surface_count()):
			var a := instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = a[Mesh.ARRAY_INDEX]
			triangle_count += indices.size() / 3
			normals_ok = normals_ok and normals.size() == vertices.size()
			for normal in normals:
				normals_ok = normals_ok and normal.is_finite() and absf(normal.length() - 1) < 0.02
			if instance.skin:
				var weights: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
				var n: int = weights.size() / vertices.size()
				weights_ok = weights_ok and n > 0 and n <= 4
				for i in range(vertices.size()):
					var total := 0.0
					for j in range(n):
						total += weights[i * n + j]
					weights_ok = weights_ok and absf(total - 1) < 0.002
			var mat := instance.get_active_material(surface) as StandardMaterial3D
			if mat:
				materials[mat.resource_name] = true
				normals_ok = normals_ok and mat.cull_mode == BaseMaterial3D.CULL_BACK
				if mat.resource_name in ["Blue", "Yellow", "Orange"]:
					marker_unlit = marker_unlit and mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
	expect(triangle_count >= 10000 and triangle_count <= 25000, kind + ": moderate triangle budget")
	expect(materials.size() <= 8, kind + ": compact material palette")
	expect(normals_ok and weights_ok and body_skinned, kind + ": normals, skinning and normalized weights")
	expect(marker_unlit and part != null, kind + ": separate, readable target material")
	for clip in ["Idle", "Walk"]:
		expect(player.has_animation(clip), kind + ": missing " + clip)
		if player.has_animation(clip):
			var animation := player.get_animation(clip)
			expect(animation.loop_mode == Animation.LOOP_LINEAR, kind + ": imported looping " + clip)
			pose(kind, clip, 0)
			var start: Array[Transform3D] = []
			for i in range(skeleton.get_bone_count()):
				start.append(skeleton.get_bone_global_pose(i))
			pose(kind, clip, animation.length - 0.00001)
			var matches := true
			for i in range(start.size()):
				var end := skeleton.get_bone_global_pose(i)
				matches = matches and start[i].origin.distance_to(end.origin) < 0.0002
				matches = matches and start[i].basis.get_rotation_quaternion().angle_to(end.basis.get_rotation_quaternion()) < 0.002
			expect(matches, kind + ": seamless loop endpoints " + clip)
	var pose_samples: Array[Dictionary] = []
	var valid_deformation := true
	for time in [0.0, 0.3, 0.6, 0.9]:
		var sample := bounds_at(kind, time)
		pose_samples.append(sample)
		valid_deformation = valid_deformation and sample.min_m[1] > -0.01 and sample.min_m[1] < 0.015 and sample.max_m[1] > 1.60 and sample.max_m[1] < 1.91
		valid_deformation = valid_deformation and sample.max_m[0] - sample.min_m[0] < 2.5 and sample.max_m[2] - sample.min_m[2] < 1.6
	expect(valid_deformation, kind + ": metre scale, floor contact and bounded visible deformation")
	pose(kind, "Idle", 0)
	var marker_position := part.global_position if part else Vector3.INF
	var target := Vector3(0, 1.75, 0) if kind == "patient" else (Vector3(0, 0.85, 0) if kind == "conjoined" else Vector3(0, 0.12, -0.95))
	expect(marker_position.distance_to(target) < 0.001, kind + ": unchanged part_visual marker position")
	if kind == "conjoined":
		var start := model.find_child("CableStart", true, false) as Node3D
		var end := model.find_child("CableEnd", true, false) as Node3D
		expect(start != null and start.global_position.distance_to(Vector3(-0.4, 0.85, 0)) < 0.001, "Conjoined: original bridge start anchor")
		expect(end != null and end.global_position.distance_to(Vector3(0.4, 0.85, 0)) < 0.001, "Conjoined: original bridge end anchor")
	reports[kind] = {"triangles": triangle_count, "meshes": meshes.size(), "materials": materials.keys(),
		"bones": skeleton.get_bone_count(), "animations": player.get_animation_list(), "deformation_samples": pose_samples,
		"part": PARTS[kind], "marker_position_m": [marker_position.x, marker_position.y, marker_position.z]}
	model.hide()


func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT + "godot/walk-gameplay")
	setup()
	for kind in KINDS:
		inspect(kind)
	if models.size() != 3:
		finish()
		return
	for i in range(KINDS.size()):
		var model: Node3D = models[KINDS[i]].model
		model.position.x = (i - 1) * 2.4
		model.rotation.y = deg_to_rad(165)
		model.show()
	camera.position = Vector3(0, 20, 14)
	camera.rotation_degrees = Vector3(-55, 0, 0)
	camera.size = 22
	label.text = "CREATURE FAMILY / Patient · Conjoined · Bellows Belly\nActual gameplay camera: ortho 22, pitch −55°, 1280×800 · metre-scale exports, no gameplay enlargement"
	for kind in KINDS:
		pose(kind, "Idle", 0)
	var img: Image = await capture("godot/gameplay-idle.png")
	var colors := count_colors(img)
	for kind in KINDS:
		expect(colors[kind] > 3, kind + ": colored part visible at gameplay scale")
		reports[kind].gameplay_color_samples_stride4 = colors[kind]
	label.text = "CREATURE FAMILY / Walk · 1.2-second in-place cycle\nActual gameplay camera: ortho 22, pitch −55°, 1280×800 · no runtime integration"
	for frame in range(16):
		for kind in KINDS:
			pose(kind, "Walk", frame * 1.2 / 16)
		await capture("godot/walk-gameplay/frame-%02d.png" % frame)
	camera.position = Vector3(0.8, 3.2, 7)
	camera.look_at(Vector3(0, 0.9, 0))
	camera.size = 4.3
	label.text = "CREATURE FAMILY / close silhouette review\nPatient · Conjoined · Bellows Belly — existing colored-part rules retained"
	for kind in KINDS:
		pose(kind, "Idle", 0)
	await capture("godot/family-close.png")
	for kind in KINDS:
		for other in KINDS:
			models[other].model.visible = other == kind
		var model: Node3D = models[kind].model
		var part: Node3D = models[kind].part
		model.position = Vector3.ZERO
		camera.position = Vector3(0, 3.6, 4)
		camera.look_at(Vector3(0, 0.85, 0))
		camera.size = 2.4 if kind != "conjoined" else 2.8
		var facing_samples := {}
		for angle in [0, 90, 180, 270]:
			model.rotation.y = deg_to_rad(angle)
			label.text = "%s / overhead-facing review, yaw %d°\nTarget is a separate node; no gameplay attachment or hit tests changed" % [kind, angle]
			img = await capture("godot/%s-facing-%d.png" % [kind, angle])
			colors = count_colors(img)
			facing_samples[str(angle)] = colors[kind]
		expect(facing_samples.values().min() > 3, kind + ": part remains visible from all overhead facings")
		reports[kind].facing_color_samples_stride4 = facing_samples
		model.rotation.y = deg_to_rad(155)
		camera.position = Vector3(3, 2.5, 5)
		camera.look_at(Vector3(0, 0.9, 0))
		label.text = "%s / Idle · close engine review\nSkinning, materials and independently removable %s" % [kind, PARTS[kind]]
		await capture("godot/%s-close.png" % kind)
		part.hide()
		label.text = "%s / target removed\nOnly the independently removable colored part is hidden; body remains" % kind
		img = await capture("godot/%s-removed.png" % kind)
		colors = count_colors(img)
		expect(colors[kind] == 0, kind + ": no colored remnants after target hide")
		part.show()
	expect(images == 36, "Expected 36 Godot review images/frames")
	finish()


func finish() -> void:
	var result := {"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures,
		"models": reports, "images": images, "camera": {"ortho": 22, "position": [0, 20, 14], "pitch": -55, "resolution": [1280, 800]},
		"playable_files_changed": false}
	var file := FileAccess.open(OUT + "godot-verification.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t") + "\n")
	file.close()
	print(JSON.stringify({"status": result.status, "checks": checks, "failures": failures, "images": images}))
	quit(0 if failures.is_empty() else 1)
