extends SceneTree

# Bounded private-display render and verification script for Round K (JAM-4).
# Captures all 4 museum rooms + exit/boss ceremony cues and verifies data/visual/collision agreement.

const OUT_DIR := "/home/mattlongname/game-jams/state/old-tech-jam-4/exports/round-k/"
const Rooms = preload("res://scenes/prototype/rooms.gd")
const Cover = preload("res://scenes/prototype/cover.gd")

var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func _rects_match(a: Array[Rect2], b: Array[Rect2], eps: float = 0.05) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if (
			absf(a[i].position.x - b[i].position.x) > eps
			or absf(a[i].position.y - b[i].position.y) > eps
			or absf(a[i].size.x - b[i].size.x) > eps
			or absf(a[i].size.y - b[i].size.y) > eps
		):
			return false
	return true


func _save_shot(filename: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var err := img.save_png(OUT_DIR + filename)
	expect(
		err == OK and img.get_width() == 1280 and img.get_height() == 800,
		"Saved 1280x800 room preview image: " + filename
	)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	var preview_scene := load("res://scenes/room_preview/room_preview.tscn") as PackedScene
	var preview := preview_scene.instantiate()
	root.add_child(preview)
	current_scene = preview
	await physics_frame
	await physics_frame

	root.get_node("GameState").resume()
	var arena: Node3D = preview.arena
	var room_env: Node3D = preview.room_env
	arena.set_physics_process(false)
	arena.set_process(false)

	var defs := Rooms.definitions()
	expect(defs.size() == 4, "Rooms.definitions() provides 4 museum rooms")

	var shot_files := [
		"01-room1-gallery.png",
		"02-room2-collections.png",
		"03-room3-restoration.png",
		"04-room4-burial-boss-court.png",
	]

	for i in range(defs.size()):
		var def: Dictionary = preview.apply_room_by_index(i)
		var room_id: StringName = def["id"]
		preview.spawn_preview_cohort_for_room(room_id)
		if room_id == &"burial":
			room_env.set_boss_ceremony_phase(&"active")
		else:
			room_env.set_exit_open(i % 2 == 1)

		var expected_cover: Array[Rect2] = def["cover"]
		var visual_cover: Array[Rect2] = room_env.get_cover_world_rectangles()
		var collider_cover: Array[Rect2] = room_env.get_collider_world_rectangles(arena)
		var clip_cover: Array[Rect2] = arena.cover.get_rectangles()

		expect(
			_rects_match(expected_cover, visual_cover),
			"%s rendered cover matches definition['cover']" % String(room_id)
		)
		expect(
			_rects_match(expected_cover, collider_cover),
			"%s StaticBody3D colliders match definition['cover']" % String(room_id)
		)
		expect(
			_rects_match(expected_cover, clip_cover),
			"%s Cover.rectangles clipping list matches definition['cover']" % String(room_id)
		)

		# Position player in central lane so the entire room kit + North/South doorways are framed at gameplay ortho 22, pitch -55
		var cam: Camera3D = arena.player.camera
		arena.player.position = Vector3(def["player_spawn"].x * 0.35, 0.55, 1.2)
		cam.position = Vector3(0.0, 20.0, 14.0)
		cam.rotation_degrees = Vector3(-55.0, 0.0, 0.0)
		cam.size = 22.0
		arena._update_hud()
		await _save_shot(shot_files[i])

	# Shot 5: Close inspection of North Exit Doorway open cue & cover kit pieces in Gallery
	preview.apply_room_by_id(&"gallery")
	room_env.set_exit_open(true)
	preview.spawn_preview_cohort_for_room(&"gallery")
	var cam: Camera3D = arena.player.camera
	arena.player.position = Vector3(0.0, 0.55, -5.0)
	cam.position = Vector3(0.0, 16.0, 10.5)
	cam.rotation_degrees = Vector3(-55.0, 0.0, 0.0)
	cam.size = 16.5
	arena._update_hud()
	await _save_shot("05-doorway-exit-open-and-kit.png")

	var summary := {
		"status": "passed" if failures.is_empty() else "failed",
		"checks": checks,
		"failures": failures,
		"shots": [
			OUT_DIR + "01-room1-gallery.png",
			OUT_DIR + "02-room2-collections.png",
			OUT_DIR + "03-room3-restoration.png",
			OUT_DIR + "04-room4-burial-boss-court.png",
			OUT_DIR + "05-doorway-exit-open-and-kit.png",
		],
	}
	print(JSON.stringify(summary))
	quit(0 if failures.is_empty() else 1)
