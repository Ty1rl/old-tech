extends SceneTree

const OUT_DIR := "/home/mattlongname/game-jams/state/old-tech-jam-4/exports/round-j/"
const Cover = preload("res://scenes/prototype/cover.gd")

const EXPECTED_TEXTURES := {
	"floor": "res://assets/modelWallsFloors/floor_floor_BaseColor.png",
	"leftWallDouble": "res://assets/modelWallsFloors/leftWallDouble_leftWallDouble_BaseColor.png",
	"leftWallSingle": "res://assets/modelWallsFloors/leftWallSingle_leftWallSingle_BaseColor.png",
	"rightWallDouble": "res://assets/modelWallsFloors/rightWallDouble_rightWallDouble_BaseColor.png",
	"rightWallSingle": "res://assets/modelWallsFloors/rightWallSingle_rightWallSingle_BaseColor.png",
	"uniColumn": "res://assets/modelWallsFloors/uniColumn_uniColumn_BaseColor.png",
}

const REMOVED_DUPLICATES := [
	"res://assets/modelWallsFloors/floor_BaseColor.png",
	"res://assets/modelWallsFloors/leftWallDouble_BaseColor.png",
	"res://assets/modelWallsFloors/leftWallSingle_BaseColor.png",
	"res://assets/modelWallsFloors/rightWallDouble_BaseColor.png",
	"res://assets/modelWallsFloors/rightWallSingle_BaseColor.png",
	"res://assets/modelWallsFloors/uniColumn_BaseColor.png",
]

var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func _save_shot(filename: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var err := img.save_png(OUT_DIR + filename)
	expect(err == OK and img.get_width() == 1280 and img.get_height() == 800,
		"Saved 1280x800 preview image: " + filename)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	var preview_scene := load("res://scenes/museum_preview/museum_preview.tscn") as PackedScene
	var preview := preview_scene.instantiate()
	root.add_child(preview)
	current_scene = preview
	await physics_frame
	await physics_frame

	var arena: Node3D = preview.arena
	var museum: Node3D = preview.museum
	arena.set_physics_process(false)
	arena.set_process(false)

	# 1. Verify MuseumEnvironment structure and zero physics colliders
	expect(museum != null and museum.has_method("build"), "MuseumEnvironment node exists and exposes build()")
	expect(museum.floor_root != null and museum.floor_root.get_child_count() == 64,
		"FloorTiles builds 8x8 (64) parquet-alternated tiles covering the 40x40m arena")
	expect(museum.walls_root != null and museum.walls_root.get_child_count() == 40,
		"PerimeterWalls builds 40 wall/curb segments across the 4 perimeter sides")
	expect(museum.columns_root != null and museum.columns_root.get_child_count() == 31,
		"PerimeterColumns builds 31 perimeter bay/corner columns")
	expect(museum.cover_root != null and museum.cover_root.get_child_count() == Cover.RECTANGLES.size(),
		"CoverDecorations matches Cover.RECTANGLES count (2)")

	var collider_count := 0
	var stack: Array[Node] = [museum]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CollisionObject3D or n is CollisionShape3D:
			collider_count += 1
		for c in n.get_children():
			stack.append(c)
	expect(collider_count == 0, "MuseumEnvironment adds zero physics colliders (arena physics remain authoritative)")

	# 2. Verify floor at y=0, perimeter walls outside [-20, 20], and cover decorations aligned to Cover.RECTANGLES
	var floor_bounds_ok := true
	for tile in museum.floor_root.get_children():
		if tile is MeshInstance3D:
			var aabb: AABB = tile.transform * tile.get_aabb()
			var top_y := aabb.position.y + aabb.size.y
			if absf(top_y - 0.003) > 0.015:
				floor_bounds_ok = false
	expect(floor_bounds_ok, "All floor tiles sit at y ~= 0.0")

	var walls_outside_ok := true
	for wall in museum.walls_root.get_children():
		if wall is MeshInstance3D:
			var pos: Vector3 = wall.position
			if absf(pos.x) < 20.0 and absf(pos.z) < 20.0:
				walls_outside_ok = false
	expect(walls_outside_ok, "All perimeter walls sit outside the [-20, 20] playable arena bounds")

	for i in range(Cover.RECTANGLES.size()):
		var rect: Rect2 = Cover.RECTANGLES[i]
		var pillar := museum.cover_root.get_child(i) as MeshInstance3D
		var aabb: AABB = pillar.transform * pillar.get_aabb()
		expect(absf(pillar.position.x - rect.get_center().x) < 0.02 and absf(pillar.position.z - rect.get_center().y) < 0.02,
			"Cover decoration %d centered on Cover.RECTANGLES[%d]" % [i, i])
		expect(absf(aabb.size.x - rect.size.x) < 0.08 and absf(aabb.size.z - rect.size.y) < 0.08,
			"Cover decoration %d footprint matches Cover.RECTANGLES[%d]" % [i, i])

	# 3. Verify all 6 GLB assets use the retained <name>_<name>_BaseColor.png textures and removed duplicates stay absent
	for key in EXPECTED_TEXTURES.keys():
		var mesh: ArrayMesh = museum._shared_meshes.get(key)
		expect(mesh != null and mesh.get_surface_count() > 0, "Shared mesh loaded for " + key)
		if mesh != null and mesh.get_surface_count() > 0:
			var mat := mesh.surface_get_material(0)
			var texture: Texture2D
			if mat is ShaderMaterial: texture = mat.get_shader_parameter("floor_texture")
			elif mat is StandardMaterial3D: texture = mat.albedo_texture
			var tex_path := texture.resource_path if texture else ""
			expect(tex_path == EXPECTED_TEXTURES[key],
				"%s uses texture %s (got %s)" % [key, EXPECTED_TEXTURES[key], tex_path])

	for dup_path in REMOVED_DUPLICATES:
		expect(not FileAccess.file_exists(dup_path) and not FileAccess.file_exists(dup_path + ".import"),
			"Removed duplicate texture and .import remain absent: " + dup_path)

	# 4. Verify gameplay camera framing (ortho 22, pos (0, 20, 14), pitch -55 deg) and capture views
	var camera: Camera3D = arena.player.camera
	expect(camera.projection == Camera3D.PROJECTION_ORTHOGONAL and is_equal_approx(camera.size, 22.0),
		"Combat camera uses orthographic size 22.0")
	expect(camera.position.is_equal_approx(Vector3(0, 20, 14)) and is_equal_approx(camera.rotation_degrees.x, -55.0),
		"Combat camera uses offset (0, 20, 14) and pitch -55 deg")

	# Shot 1: Center arena gameplay framing (ortho 22, pitch -55) with player, cover pillars, and mixed enemies
	arena.director.clear()
	arena.director.spawn_group()
	arena.director.spawn(&"target", Vector3(0.0, 0.0, -5.0))
	arena.player.position = Vector3(0.0, 0.55, 0.0)
	arena._update_hud()
	await _save_shot("01-gameplay-ortho22-center.png")

	# Shot 2: North-West gallery perimeter framing at actual gameplay scale (ortho 22, pitch -55)
	arena.player.position = Vector3(-8.5, 0.55, -9.5)
	camera.position = Vector3(0, 20, 14)
	camera.rotation_degrees = Vector3(-55, 0, 0)
	camera.size = 22.0
	arena._update_hud()
	await _save_shot("02-gameplay-ortho22-perimeter.png")

	# Shot 3: Close architectural & cover inspection (ortho 11, showing all 4 wall variants, column, cover, and floor)
	arena.player.position = Vector3(-5.0, 0.55, -6.0)
	camera.position = Vector3(-2.5, 11.5, 4.5)
	camera.look_at(Vector3(-9.5, 1.8, -14.5))
	camera.size = 11.5
	await _save_shot("03-close-detail-assets.png")

	# Restore gameplay camera and test idempotent rebuild
	camera.position = Vector3(0, 20, 14)
	camera.rotation_degrees = Vector3(-55, 0, 0)
	camera.size = 22.0
	museum.build()
	expect(museum.floor_root.get_child_count() == 64 and museum.walls_root.get_child_count() == 40,
		"museum.build() is idempotent when called again")

	var summary := {
		"status": "passed" if failures.is_empty() else "failed",
		"checks": checks,
		"failures": failures,
		"shots": [
			OUT_DIR + "01-gameplay-ortho22-center.png",
			OUT_DIR + "02-gameplay-ortho22-perimeter.png",
			OUT_DIR + "03-close-detail-assets.png",
		],
	}
	print(JSON.stringify(summary))
	quit(0 if failures.is_empty() else 1)
