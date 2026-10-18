extends SceneTree
const OUT := "/home/mattlongname/frankenstein/.daedalus-dev-state/game-jams/state/old-tech-jam-5/exports/round-k/"
const Preview = preload("res://scenes/pattern_preview/main.gd")
var scene: Node3D
var images: Array[String] = []
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: call_deferred("run")
func capture(name: String, text: String) -> void:
	scene.hud.text = text + "\nGameplay camera · ortho 22 · pitch −55° · 1280×800"
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if name in ["loop-intact", "zigzag-intact", "boss-zigzag"]:
		var points: Array = scene.enemy.cable_world_points()
		for i in range(points.size() / 2):
			var center: Vector2 = scene.camera.unproject_position((points[i * 2] + points[i * 2 + 1]) * 0.5)
			center *= Vector2(img.get_size()) / scene.camera.get_viewport().get_visible_rect().size
			var visible := false
			for dy in range(-3, 4):
				for dx in range(-3, 4):
					var c := img.get_pixel(int(center.x) + dx, int(center.y) + dy)
					visible = visible or (c.b > 0.75 and c.g > 0.3 and c.r < 0.3)
			checks += 1
			if not visible: failures.append(name + ": link %d hidden at gameplay camera" % (i + 1))
	checks += 1
	var error := img.save_png(OUT + name + ".png")
	if error == OK: images.append(name + ".png")
	else: failures.append("Cannot save " + name)
func cut(index: int, already: bool = true) -> void:
	var e: Node3D = scene.enemy
	var p: Array = e.cable_world_points()
	e.receive_attack(&"ring", 36, p[index * 2], {"segment_start": p[index * 2], "segment_end": p[index * 2 + 1], "radius": 0.01, "already_hit": already})
func shot() -> void:
	var e: Node3D = scene.enemy
	var p: Vector3 = e.core_world_position()
	e.receive_attack(&"beam", 100, p, {"segment_start": p - Vector3(0, 0, 0.1), "segment_end": p + Vector3(0, 0, 0.1), "radius": 0.01, "charge": 1})
func reset(index: int) -> void:
	scene.chosen = index
	scene.reset_enemy()
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	scene = Preview.new()
	root.add_child(scene)
	scene.set_physics_process(false)
	await process_frame
	reset(0)
	await capture("loop-intact", "CRAWLING LUNG · four blue supports · one launch")
	cut(0, false)
	cut(1)
	await capture("loop-partial", "PARTIAL LOOP · 2/4 supports · reconnects after 3 world seconds")
	cut(2)
	cut(3)
	await capture("loop-open", "COMPLETE LOOP · permanent yellow opening · charged shot finishes")
	reset(1)
	await capture("zigzag-intact", "CROOKED SPINE · three staggered blue spans · one launch")
	for i in range(3): cut(i, i > 0)
	await capture("zigzag-open", "ZIGZAG COMPLETE · permanent opening · damaged body stays damaged")
	reset(2)
	await capture("pair-a", "TWIN VALVE · quick accurate shot at A opens B")
	shot()
	await capture("pair-b", "TWIN VALVE · shoot B before its 2.4-world-second shutter closes")
	reset(3)
	await capture("boss-pair", "BURIAL DEVICE · phase 1/4 · A → B → charged core")
	shot()
	shot()
	shot()
	await capture("boss-zigzag", "BURIAL DEVICE · phase 2/4 · upper yoke removed · zigzag")
	for i in range(3): cut(i, i > 0)
	shot()
	await capture("boss-loop", "BURIAL DEVICE · phase 3/4 · side columns removed · loop")
	for i in range(4): cut(i, i > 0)
	shot()
	await capture("boss-core", "BURIAL DEVICE · phase 4/4 · outriggers removed · final core")
	reset(0)
	scene.player.position = Vector3(0, 0, 1.4)
	scene.enemy.step_enemy(0.01, scene.player)
	await capture("attack-warning", "ATTACK WARNING · 0.8s anticipation → commit → 1.9s recovery")
	var result := {"status": "passed" if failures.is_empty() else "failed", "images": images, "failures": failures, "checks": checks}
	FileAccess.open(OUT + "visuals.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t") + "\n")
	print(JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
