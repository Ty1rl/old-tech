extends SceneTree
const OUT := "/home/mattlongname/game-jams/state/old-tech-jam-5/exports/round-n-wave2/"
var bench: Node3D
var images: Array[String] = []
var failures: Array[String] = []
var pass_name := "initial"
func _initialize() -> void: call_deferred("run")
func mouse(down: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	return e
func capture(name: String, caption: String) -> void:
	bench.readout.text = caption + "\nThree named scene components · perspective 52° · actual player attachments"
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var path := pass_name + "-" + name + ".png"
	if root.get_texture().get_image().save_png(OUT + path) == OK: images.append(path)
	else: failures.append("Cannot save " + path)
func run() -> void:
	if FileAccess.file_exists(OUT + "capture-pass.txt"): pass_name = FileAccess.get_file_as_string(OUT + "capture-pass.txt").strip_edges()
	bench = preload("res://scenes/weapons/preview.tscn").instantiate()
	root.add_child(bench)
	bench.set_physics_process(false)
	bench.time.auto_advance = false
	var w: WeaponController = bench.weapons
	var player: Node3D = bench.player
	w.select_tool(1)
	w.handle_event(mouse(true), player, Vector3(-3.6, 0, -8.1))
	for p in [Vector3(-2.8, 0, -8), Vector3(-2.2, 0, -7.2), Vector3(-3, 0, -6.8), Vector3(-3.6, 0, -7.6)]:
		w.handle_event(InputEventMouseMotion.new(), player, p)
	bench.advance(0, Vector3(-3, 0, -7), 0)
	await capture("cutter-guide", "RingCutter · raw turns and endpoints stay exact; only guide is smoothed")
	w.handle_event(mouse(false), player, Vector3(-3.6, 0, -7.6))
	bench.advance(.12, Vector3(-3, 0, -7), .12)
	await capture("cutter-arc", "RingCutter · outbound arc, then raw stroke sweeps and harmless return")
	bench.reset_targets()
	w.select_tool(2)
	w.handle_event(mouse(true), player, Vector3(0, 0, -12))
	bench.advance(.9, Vector3(0, 0, -12), 0)
	await capture("flash-ready", "FocusedFlash · charged aperture at the actual lens · release to pierce")
	w.handle_event(mouse(false), player, Vector3(0, 0, -12))
	bench.advance(.12, Vector3(0, 0, -12), .12)
	await capture("flash-flight", "FocusedFlash · straight traveling light · stored muzzle · actual intersections")
	bench.advance(.24, Vector3(0, 0, -12), .24)
	await capture("flash-pierced", "FocusedFlash · two yellow contacts pierced · one shot of condition")
	bench.reset_targets()
	player.position = Vector3(3, 0, -3)
	w.select_tool(3)
	w.handle_event(mouse(true), player, Vector3(3, 0, -7))
	bench.advance(.12, Vector3(3, 0, -7), .12)
	await capture("bellows", "HeatBellows · nozzle air, bounded cone, world-time shove; real-time wear")
	FileAccess.open(OUT + pass_name + "-visuals.json", FileAccess.WRITE).store_string(JSON.stringify({"status":"passed" if failures.is_empty() else "failed", "checks":images.size(), "failures":failures, "images":images}, "\t"))
	bench.free()
	await process_frame
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed", "checks":images.size(), "failures":failures, "images":images}))
	quit(0 if failures.is_empty() else 1)
