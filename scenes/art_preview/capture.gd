extends SceneTree

# Offline asset review only. Uses the real arena and its unchanged gameplay
# camera, with the trial model placed in this capture's temporary scene tree.
const OUT := "/home/mattlongname/frankenstein/.daedalus-dev-state/game-jams/state/old-tech-jam-5/exports/character-art/"
const ASSET := "res://assets/characters/protagonist/protagonist.glb"
var failures: Array[String] = []
var checks := 0
var triangle_count := 0
var mesh_count := 0
var materials: Dictionary = {}
var bounds := AABB()
var have_bounds := false


func _initialize() -> void:
	call_deferred("capture")


func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func inspect(node: Node) -> void:
	if node is MeshInstance3D:
		mesh_count += 1
		var instance := node as MeshInstance3D
		var box := instance.global_transform * instance.get_aabb()
		bounds = bounds.merge(box) if have_bounds else box
		have_bounds = true
		for surface in range(instance.mesh.get_surface_count()):
			var arrays := instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			triangle_count += (indices.size() if not indices.is_empty() else vertices.size()) / 3
			expect(normals.size() == vertices.size(), "Missing vertex normals: " + str(instance.name))
			var normals_ok := true
			for normal in normals:
				if not normal.is_finite() or absf(normal.length() - 1.0) > 0.02:
					normals_ok = false
					break
			expect(normals_ok, "Invalid normals: " + str(instance.name))
			var mat := instance.get_active_material(surface) as StandardMaterial3D
			expect(mat != null, "Missing material: " + str(instance.name))
			if mat:
				materials[mat.resource_name] = true
				expect(mat.cull_mode == BaseMaterial3D.CULL_BACK, "Unexpected two-sided material: " + str(instance.name))
	expect(not node is Skeleton3D, "Unexpected skeleton before art approval")
	for child in node.get_children():
		inspect(child)


func save_image(filename: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(OUT + filename)
	expect(error == OK, "Could not save " + filename)


func capture() -> void:
	var packed := load(ASSET) as PackedScene
	expect(packed != null, "GLB failed to import as PackedScene")
	if not packed:
		finish()
		return
	var arena: Node3D = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.set_physics_process(false)
	arena.player.model.hide()
	var model := packed.instantiate() as Node3D
	arena.add_child(model)
	model.position = Vector3.ZERO
	inspect(model)
	expect(mesh_count > 10, "Expected editable character components")
	expect(triangle_count >= 10000 and triangle_count <= 27000, "Unexpected triangle budget")
	expect(materials.size() == 9, "Expected the nine-material palette")
	expect(absf(bounds.position.y) < 0.003, "Boot soles must sit on y=0")
	expect(bounds.size.y > 1.7 and bounds.size.y < 2.0, "Human scale must use metres")
	expect(absf(bounds.get_center().x) < 0.03, "Origin must sit between boots")
	var camera: Camera3D = arena.player.camera
	expect(camera.projection == Camera3D.PROJECTION_ORTHOGONAL and is_equal_approx(camera.size, 30.0), "Gameplay camera settings changed")
	expect(camera.position.is_equal_approx(Vector3(0, 20, 14)) and is_equal_approx(camera.rotation_degrees.x, -55), "Gameplay camera angle changed")
	# Label includes the exact camera settings; the capture itself is full frame.
	var layer := CanvasLayer.new()
	layer.layer = 100
	var label := Label.new()
	label.text = "PROTAGONIST / FIRST MODEL TRIAL     •     Actual gameplay camera: orthographic 30 m, −55°\nUnrigged A-pose · feet at ground · no playable scene changes"
	label.position = Vector2(24, root.get_visible_rect().size.y - 70)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_font_size_override("font_size", 16)
	layer.add_child(label)
	arena.add_child(layer)
	# Turn slightly toward the gameplay camera to show the face and silhouette.
	model.rotation.y = deg_to_rad(155)
	await save_image("gameplay-scale.png")
	# Same asset and arena lighting, tighter inspection camera for normals/materials.
	for other in arena.find_children("*", "CanvasLayer", true, false):
		if other != layer:
			other.visible = false
	camera.position = Vector3(3, 2.5, 5)
	camera.look_at(Vector3(0, 0.94, 0))
	camera.size = 2.5
	label.text = "PROTAGONIST / GODOT MATERIAL REVIEW     •     Enlarged inspection view\nSame GLB, arena lighting and floor · actual gameplay scale shown separately"
	await save_image("godot-detail.png")
	finish()


func finish() -> void:
	var result := {"status": "passed" if failures.is_empty() else "failed", "checks": checks,
		"failures": failures, "mesh_objects": mesh_count, "triangles": triangle_count,
		"materials": materials.size(), "bounds_min_m": [bounds.position.x, bounds.position.y, bounds.position.z],
		"dimensions_m": [bounds.size.x, bounds.size.y, bounds.size.z],
		"gameplay_camera": {"position": [0, 20, 14], "pitch_degrees": -55, "orthographic_size": 30},
		"asset": ASSET, "playable_build_changed": false}
	var file := FileAccess.open(OUT + "godot-verification.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t") + "\n")
	file.close()
	print(JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
