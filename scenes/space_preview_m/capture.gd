extends SceneTree
const OUT := "/home/mattlongname/game-jams/state/old-tech-jam-5/exports/round-m/"
const Rooms = preload("res://scenes/prototype/rooms.gd")
const RoomEnvironment = preload("res://scenes/prototype/room_environment.gd")
const Flow = preload("res://scenes/prototype/flow.gd")
var arena: Node3D
var museum: Node3D
var title: Label
var pass_name := "before"
var images: Array[String] = []
var reports: Array[Dictionary] = []
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func shot(name: String, caption: String) -> void:
	title.text = caption + "\nActual gameplay perspective · FOV 52° · normal distance · 1280×800"
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var path := pass_name + "-" + name + ".png"
	checks += 1
	if root.get_texture().get_image().save_png(OUT + path) == OK: images.append(path)
	else: failures.append("Cannot save " + path)
func circle_blocked(point: Vector3, extent: float) -> bool:
	for i in range(32):
		var a := point + Vector3(cos(i * TAU / 32), 0, sin(i * TAU / 32)) * extent
		var b := point + Vector3(cos((i + 1) * TAU / 32), 0, sin((i + 1) * TAU / 32)) * extent
		if arena.cover.clip_segment(a, b, .4).blocked: return true
	return false
func room(def: Dictionary) -> void:
	arena.director.clear()
	museum.apply_room(def, arena.cover, arena)
	museum.sync_cover_colliders(arena)
	arena.player.position = Vector3(0, .55, 5)
func run() -> void:
	if FileAccess.file_exists(OUT + "capture-pass.txt"): pass_name = FileAccess.get_file_as_string(OUT + "capture-pass.txt").strip_edges()
	arena = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	arena.set_physics_process(false)
	root.get_node("GameState").resume()
	arena.museum.hide()
	museum = RoomEnvironment.new()
	arena.add_child(museum)
	arena.status_hud.hide()
	arena.hud.hide()
	arena.slow_bar.hide()
	var layer := CanvasLayer.new()
	title = Label.new()
	title.position = Vector2(20, 16)
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_shadow_color", Color.BLACK)
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(title)
	arena.add_child(layer)
	for def in Rooms.definitions():
		room(def)
		var chosen_seed := 0
		if pass_name == "before":
			for seed in range(32):
				var slots: Array = Flow.new().layout(&"curve", [&"loop"], arena.player.position, arena.cover, seed, [])
				if not slots.is_empty() and circle_blocked(slots[0].position, 3.0):
					chosen_seed = seed
					break
			FileAccess.open(OUT + String(def.id) + "-seed.txt", FileAccess.WRITE).store_string(str(chosen_seed))
		else: chosen_seed = int(FileAccess.get_file_as_string(OUT + String(def.id) + "-seed.txt"))
		var nodes: Array = arena.director.spawn_formation(&"curve", [&"loop"], arena.player, chosen_seed)
		var e: Node3D = nodes[0] if not nodes.is_empty() else null
		reports.append({"room": String(def.id), "seed": chosen_seed, "spawned": nodes.size(), "stroke_blocked": circle_blocked(e.position, 3) if e else true, "readable": Flow.readable_from_player(e.position, Flow.placement_radius(e.kind), Vector3(0, 0, 5)) if e else false, "position": str(e.position) if e else "missing"})
		await shot(String(def.id) + "-loop", "%s · %s · full loop space · seed %d" % [pass_name.to_upper(), String(def.id), chosen_seed])
	room(Rooms.definitions()[3])
	arena.player.position = Vector3(0, .55, 0)
	var enemy: Node3D = arena.director.spawn(&"blue", Vector3(0, 0, -5))
	enemy.facing = Vector3.BACK
	var visual: Node3D = enemy.part_visual
	reports.append({"blue_mesh_names": visual.model.find_children("*", "MeshInstance3D", true, false).map(func(n): return String(n.name)), "split_meshes": visual.split_companion.size()})
	await shot("blue-intact", "%s · conjoined · intact body and blue connection" % pass_name.to_upper())
	var state: Dictionary = enemy.capture_state()
	enemy.cable_cut = true
	enemy._update_warden_visuals()
	await shot("blue-split", "%s · conjoined · severed companion must leave no body remnants" % pass_name.to_upper())
	enemy.restore_state(state)
	await shot("blue-rewind", "%s · conjoined · rewind restores both halves" % pass_name.to_upper())
	arena.director.clear()
	var guard: Node3D = arena.director.spawn(&"side_guard", Vector3(0, 0, -5))
	guard.facing = Vector3.BACK
	var guard_state: Dictionary = guard.capture_state()
	await shot("side-intact", "%s · Borrowed Heart · tethered companion" % pass_name.to_upper())
	guard.cable_cut = true
	guard._update_warden_visuals()
	await shot("side-split", "%s · Borrowed Heart · disconnected companion and collars removed" % pass_name.to_upper())
	guard.restore_state(guard_state)
	await shot("side-rewind", "%s · Borrowed Heart · rewind restores companion and conduit" % pass_name.to_upper())
	arena.director.clear()
	for i in range(4):
		var e: Node3D = arena.director.spawn(&"yellow", Vector3((i - 1.5) * 2.5, 0, -5))
		e.facing = [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT][i]
	await shot("yellow-facings", "%s · yellow query-aligned cores · four facings" % pass_name.to_upper())
	arena.director.clear()
	for i in range(3):
		var e: Node3D = arena.director.spawn([&"orange", &"front_guard", &"side_guard"][i], Vector3((i - 1) * 3, 0, -5))
		e.facing = Vector3.BACK
		e.plate_broken = true
		e._update_warden_visuals()
	await shot("orange-removed", "%s · heat-opened bodies · orange must be completely removed" % pass_name.to_upper())
	arena.director.clear()
	var boss: Node3D = arena.director.spawn(&"final_boss", Vector3(0, 0, -5))
	boss.facing = Vector3.BACK
	boss.debug_set_phase(1)
	await shot("boss-zigzag", "%s · boss zigzag · readable exposed spans and removed phase section" % pass_name.to_upper())
	if pass_name != "before":
		arena.director.clear()
		var moving: Array = []
		for i in range(3):
			moving.append(arena.director.spawn([&"blue", &"side_guard", &"front_guard"][i], Vector3((i - 1) * 3, 0, -6)))
		for frame in range(4):
			for tick in range(8):
				for unit: Node3D in moving: unit.step_enemy(1.0 / 60, arena.player, moving)
			await shot("motion-%02d" % frame, "%s · actual approach motion · %.2f world seconds" % [pass_name.to_upper(), (frame + 1) * 8.0 / 60])
		for unit: Node3D in moving:
			unit.attack_phase = &"commit"
			unit.part_visual.step_visual(.1, 2.0, false, false, &"commit")
		await shot("motion-commit", "%s · committed attack · legs hold instead of cycling" % pass_name.to_upper())
	var result := {"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures, "images": images, "reports": reports}
	FileAccess.open(OUT + pass_name + "-visuals.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t") + "\n")
	print(JSON.stringify(result))
	arena.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
