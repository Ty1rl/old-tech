extends SceneTree

# Isolated art review. This scene never loads or changes the playable prototype.
const OUT := "/home/mattlongname/frankenstein/.daedalus-dev-state/game-jams/state/old-tech-jam-5/exports/character-upgrade/"
const ASSET := "res://assets/characters/protagonist/protagonist.glb"
const CLIPS := ["Idle", "Walk", "RingHold", "FlashHold", "ConeHold", "ClockHold"]
var checks := 0
var failures: Array[String] = []
var stage: Node3D
var model: Node3D
var skeleton: Skeleton3D
var player: AnimationPlayer
var camera: Camera3D
var label: Label
var meshes: Array[MeshInstance3D] = []
var samples: Array[Dictionary] = []
var sockets: Dictionary = {}
var triangles := 0
var materials: Dictionary = {}
var saved_images := 0


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func material(hex: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(hex)
	mat.roughness = 0.82
	return mat


func box(parent: Node3D, size: Vector3, position: Vector3, mat: Material) -> MeshInstance3D:
	var ob := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	ob.mesh = mesh
	ob.material_override = mat
	ob.position = position
	parent.add_child(ob)
	return ob


func setup_stage() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	box(stage, Vector3(40, 0.1, 40), Vector3(0, -0.05, 0), material("353d43"))
	var grid := material("465058")
	for i in range(-8, 9, 2):
		box(stage, Vector3(0.015, 0.002, 16), Vector3(i, 0.001, 0), grid)
		box(stage, Vector3(16, 0.002, 0.015), Vector3(0, 0.001, i), grid)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-65, -30, 0)
	light.light_energy = 1.1
	stage.add_child(light)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("20282d")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("d1d9dd")
	world.environment.ambient_light_energy = 0.65
	stage.add_child(world)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	stage.add_child(camera)
	camera.current = true
	var layer := CanvasLayer.new()
	layer.layer = 100
	label = Label.new()
	label.position = Vector2(24, root.get_visible_rect().size.y - 70)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(label)
	stage.add_child(layer)


func collect(node: Node) -> void:
	if node is Skeleton3D:
		skeleton = node
	if node is AnimationPlayer:
		player = node
	if node is MeshInstance3D:
		meshes.append(node)
	for child in node.get_children():
		collect(child)


func pose(clip: String, time: float) -> void:
	player.play(clip)
	player.seek(time, true)
	player.advance(0)
	skeleton.force_update_all_bone_transforms()


func snapshot() -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for i in range(skeleton.get_bone_count()):
		result.append(skeleton.get_bone_global_pose(i))
	return result


func deformation(clip: String, time: float) -> Dictionary:
	pose(clip, time)
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	var feet := {"L": INF, "R": INF}
	var bad := false
	for instance in meshes:
		var skin := instance.skin
		var palette: Array[Transform3D] = []
		for bind in range(skin.get_bind_count()):
			var bone := skin.get_bind_bone(bind)
			if bone < 0:
				bone = skeleton.find_bone(skin.get_bind_name(bind))
			palette.append(skeleton.global_transform * skeleton.get_bone_global_pose(bone) * skin.get_bind_pose(bind))
		for surface in range(instance.mesh.get_surface_count()):
			var arrays := instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var influences: int = weights.size() / vertices.size()
			for v in range(vertices.size()):
				var p := Vector3.ZERO
				for influence in range(influences):
					var weight := weights[v * influences + influence]
					if weight > 0:
						p += (palette[bones[v * influences + influence]] * vertices[v]) * weight
				bad = bad or not p.is_finite()
				low = low.min(p)
				high = high.max(p)
				if str(instance.name).begins_with("Boot sole"):
					var side := "L" if str(instance.name).ends_with("L") else "R"
					feet[side] = minf(feet[side], p.y)
	var sample := {"clip": clip, "time_s": time, "min_m": [low.x, low.y, low.z],
		"max_m": [high.x, high.y, high.z], "foot_min_y_m": feet, "finite": not bad}
	samples.append(sample)
	return sample


func save_image(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(OUT + path)
	if error != OK:
		failures.append("Could not save image: " + path)
	else:
		saved_images += 1


func standin(clip: String) -> Node3D:
	var prop := Node3D.new()
	var grip := model.find_child("Grip_R", true, false) as Node3D
	grip.add_child(prop)
	var brass := material("a28e60")
	var leather := material("5c4635")
	var dark := material("292d2c")
	var canvas := material("626b64")
	box(prop, Vector3(0.031, 0.10, 0.036), Vector3(0, -0.015, 0), leather)
	if clip == "FlashHold":
		box(prop, Vector3(0.30, 0.15, 0.16), Vector3(-0.15, 0.095, -0.055), dark)
		box(prop, Vector3(0.16, 0.13, 0.09), Vector3(-0.15, 0.095, -0.16), canvas)
		box(prop, Vector3(0.09, 0.07, 0.07), Vector3(-0.15, 0.22, -0.06), brass)
		box(prop, Vector3(0.031, 0.10, 0.036), Vector3(-0.30, -0.015, -0.04), leather)
		var lens := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.056
		cylinder.bottom_radius = 0.056
		cylinder.height = 0.06
		lens.mesh = cylinder
		lens.material_override = brass
		lens.rotation.x = PI / 2
		lens.position = Vector3(-0.15, 0.095, -0.22)
		prop.add_child(lens)
	elif clip == "RingHold":
		for i in range(13):
			var angle := deg_to_rad(-20 + i * 220.0 / 12)
			var p := Vector3(-0.122 + 0.18 * cos(angle), 0.075, -0.14 + 0.18 * sin(angle))
			var segment := box(prop, Vector3(0.055, 0.045, 0.06), p, brass)
			segment.rotation.y = -angle
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.085
		torus.outer_radius = 0.102
		ring.mesh = torus
		ring.material_override = dark
		ring.position = Vector3(-0.122, 0.077, -0.14)
		prop.add_child(ring)
	elif clip == "ConeHold":
		box(prop, Vector3(0.20, 0.15, 0.20), Vector3(-0.105, 0.09, -0.10), canvas)
		box(prop, Vector3(0.17, 0.14, 0.075), Vector3(-0.105, 0.09, -0.245), brass)
		box(prop, Vector3(0.13, 0.10, 0.008), Vector3(-0.105, 0.09, -0.285), dark)
	else:
		box(prop, Vector3(0.21, 0.14, 0.08), Vector3(-0.105, 0.065, -0.025), leather)
		box(prop, Vector3(0.12, 0.12, 0.012), Vector3(-0.105, 0.065, -0.071), brass)
	return prop


func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT + "godot")
	for sequence in ["idle-gameplay", "walk-gameplay", "walk-close"]:
		DirAccess.make_dir_recursive_absolute(OUT + "godot/" + sequence)
	setup_stage()
	model = (load(ASSET) as PackedScene).instantiate() as Node3D
	stage.add_child(model)
	collect(model)
	expect(skeleton != null and player != null, "Missing skeleton or AnimationPlayer")
	if skeleton == null or player == null:
		finish()
		return
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	expect(skeleton.get_bone_count() == 20, "Expected the documented 20-bone rig")
	expect(meshes.size() == 80, "Review stand-ins leaked into character GLB or parts are missing")
	var normals_ok := true
	var weights_ok := true
	var all_skinned := true
	for instance in meshes:
		all_skinned = all_skinned and instance.skin != null
		for surface in range(instance.mesh.get_surface_count()):
			var arrays := instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			triangles += indices.size() / 3
			normals_ok = normals_ok and normals.size() == vertices.size()
			for normal in normals:
				normals_ok = normals_ok and normal.is_finite() and absf(normal.length() - 1) < 0.02
			var influences: int = weights.size() / vertices.size()
			weights_ok = weights_ok and influences > 0 and influences <= 4
			for v in range(vertices.size()):
				var total := 0.0
				for w in range(influences):
					total += weights[v * influences + w]
				weights_ok = weights_ok and absf(total - 1) < 0.002
			var mat := instance.get_active_material(surface) as StandardMaterial3D
			if mat:
				materials[mat.resource_name] = true
				normals_ok = normals_ok and mat.cull_mode == BaseMaterial3D.CULL_BACK
	expect(all_skinned, "All visible parts must use the deforming skeleton")
	expect(weights_ok, "Skin weights must be normalized with at most four influences")
	expect(normals_ok, "Invalid normals or unexpected double-sided materials")
	expect(materials.size() == 9, "Expected the existing nine-material palette")
	expect(triangles < 40000, "Geometry exceeds the focused refinement budget")
	for name in ["hand.R", "hand.L", "upper_arm.R", "forearm.L", "thigh.R", "shin.L"]:
		expect(skeleton.find_bone(name) >= 0, "Missing documented bone: " + name)
	for clip in CLIPS:
		expect(player.has_animation(clip), "Missing animation: " + clip)
		if not player.has_animation(clip):
			continue
		var animation := player.get_animation(clip)
		expect(animation.loop_mode == Animation.LOOP_LINEAR, "Clip must loop on import: " + clip)
		pose(clip, 0)
		var start := snapshot()
		pose(clip, animation.length - 0.00001)
		var end := snapshot()
		var loop_ok := true
		for i in range(start.size()):
			loop_ok = loop_ok and start[i].origin.distance_to(end[i].origin) < 0.0002
			loop_ok = loop_ok and start[i].basis.get_rotation_quaternion().angle_to(end[i].basis.get_rotation_quaternion()) < 0.002
		expect(loop_ok, "Loop boundary discontinuity: " + clip)
	if not all_skinned:
		finish()
		return
	var deformation_ok := true
	var stance_ok := true
	for clip in CLIPS:
		var times := [0.0, 0.5, 1.0] if clip == "Idle" else ([0.0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875, 0.99999] if clip == "Walk" else [0.0])
		for time in times:
			var sample := deformation(clip, time)
			deformation_ok = deformation_ok and sample.finite and sample.min_m[1] >= -0.008 and sample.max_m[1] < 2.0
			if clip == "Walk":
				var feet: Dictionary = sample.foot_min_y_m
				stance_ok = stance_ok and minf(feet.L, feet.R) < 0.012
	expect(deformation_ok, "Non-finite deformation, ground penetration, or implausible pose bounds")
	expect(stance_ok, "Walk loses planted-foot ground contact")
	pose("Walk", 0)
	var knee0 := skeleton.get_bone_global_pose(skeleton.find_bone("shin.L"))
	pose("Walk", 0.25)
	var knee1 := skeleton.get_bone_global_pose(skeleton.find_bone("shin.L"))
	expect(knee0.basis.get_rotation_quaternion().angle_to(knee1.basis.get_rotation_quaternion()) > 0.1, "Walk must bend the knee, not just move rigid legs")
	for clip in ["RingHold", "FlashHold", "ConeHold", "ClockHold"]:
		pose(clip, 0)
		# BoneAttachment3D publishes transforms at the frame boundary. Reading
		# immediately after seek() observes the previous pose's socket transform.
		await process_frame
		await RenderingServer.frame_post_draw
		var transforms := {}
		var targets := {
			"RingHold": [Vector3(0.115, 1.17, -0.31), Vector3(-0.130, 1.17, -0.44)],
			"FlashHold": [Vector3(0.150, 1.21, -0.32), Vector3(-0.150, 1.21, -0.36)],
			"ConeHold": [Vector3(0.115, 1.16, -0.29), Vector3(-0.115, 1.19, -0.44)],
			"ClockHold": [Vector3(0.105, 1.16, -0.27), Vector3(-0.105, 1.16, -0.29)]}
		for name in ["Grip_R", "Grip_L"]:
			var grip := model.find_child(name, true, false) as Node3D
			expect(grip != null, "Missing hand attachment: " + name)
			if grip:
				var relative := model.global_transform.affine_inverse() * grip.global_transform
				transforms[name] = {"origin_m": [relative.origin.x, relative.origin.y, relative.origin.z],
					"quaternion_xyzw": [relative.basis.get_rotation_quaternion().x, relative.basis.get_rotation_quaternion().y, relative.basis.get_rotation_quaternion().z, relative.basis.get_rotation_quaternion().w]}
				expect(relative.basis.get_rotation_quaternion().angle_to(Quaternion.IDENTITY) < 0.01, "Holding socket axes must match character root: " + clip + "/" + name)
				var target: Vector3 = targets[clip][0 if name == "Grip_R" else 1]
				expect(relative.origin.distance_to(target) < 0.012, "Socket must follow its posed hand: " + clip + "/" + name)
		sockets[clip] = transforms
	model.rotation.y = deg_to_rad(155)
	# Exact current gameplay camera contract, in a neutral isolated grid stage.
	camera.position = Vector3(0, 20, 14)
	camera.rotation_degrees = Vector3(-55, 0, 0)
	camera.size = 22
	for clip in ["Idle", "Walk"]:
		label.text = "PROTAGONIST / %s  •  Actual gameplay camera: ortho 22 m, pitch −55°\nSkinned in-place animation · isolated review stage · 1280×800" % clip
		var sequence := "idle-gameplay" if clip == "Idle" else "walk-gameplay"
		var duration := 2.0 if clip == "Idle" else 1.0
		var count := 30 if clip == "Idle" else 16
		for frame in range(count):
			pose(clip, duration * frame / count)
			await save_image("godot/%s/frame-%02d.png" % [sequence, frame])
		pose(clip, 0.22 if clip == "Walk" else 0)
		await save_image("godot/%s.png" % sequence)
	camera.position = Vector3(2.7, 2.15, 4.8)
	camera.look_at(Vector3(0, 0.95, 0))
	camera.size = 2.45
	label.text = "PROTAGONIST / WALK  •  Deformation inspection\nSame imported skeleton, weights and loop · no runtime IK"
	for frame in range(16):
		pose("Walk", frame / 16.0)
		await save_image("godot/walk-close/frame-%02d.png" % frame)
	for clip in ["RingHold", "FlashHold", "ConeHold", "ClockHold"]:
		pose(clip, 0)
		var prop := standin(clip)
		label.text = "PROTAGONIST / %s  •  Holding pose and socket review\nCrude prop stand-in · Grip_R follows hand.R · final equipment fitting belongs to integration" % clip
		await save_image("godot/%s.png" % clip)
		prop.free()
	expect(saved_images == 68, "Expected 62 loop frames plus six review stills")
	finish()


func finish() -> void:
	var result := {"status": "passed" if failures.is_empty() else "failed", "checks": checks,
		"failures": failures, "mesh_objects": meshes.size(), "triangles": triangles, "materials": materials.size(),
		"bones": skeleton.get_bone_count() if skeleton else 0, "animations": player.get_animation_list() if player else [],
		"deformation_samples": samples, "exported_socket_transforms": sockets,
		"images": saved_images, "gameplay_camera": {"position": [0, 20, 14], "pitch": -55, "size": 22, "resolution": [1280, 800]},
		"playable_build_changed": false}
	var file := FileAccess.open(OUT + "godot-verification.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t") + "\n")
	file.close()
	print(JSON.stringify({"status": result.status, "checks": checks, "failures": failures, "images": saved_images, "bones": result.bones, "triangles": triangles}))
	quit(0 if failures.is_empty() else 1)
